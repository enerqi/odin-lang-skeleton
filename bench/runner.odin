/*
The benchmark harness. You should not need to edit this file - write benchmarks in bench.odin.

`core:time`'s `benchmark()` is a stopwatch, not a harness: it calls your procedure exactly once and
divides. That is enough to answer "roughly how fast", and not enough to answer "did my change make it
slower", which is the question a benchmark suite exists to answer. The difference is warmup,
repetition, and a number that survives being compared against yesterday's number.

What this adds on top of a stopwatch, mostly borrowed from criterion (Haskell first, then Rust):

  * warmup, so the first sample is not measuring cold i-cache, a cold branch predictor and a CPU still
    at its idle clock
  * samples taken across a *ramp* of iteration counts and fitted with a line, so the per-iteration cost
    comes out as the slope and the cost of measuring lands in the intercept instead of in the answer
  * a robust (Theil-Sen) fit, so a couple of preempted samples do not move the number
  * R^2 and Tukey outlier counts, which say whether the samples describe one thing
  * a Mann-Whitney U test against the baseline, so "did it move" is a p-value rather than a guess
  * `keep` / `opaque`, without which an optimizer deletes the loop you are trying to time
  * JSON out carrying every sample, so the comparison has distributions to test rather than summaries

What it deliberately does not add: bootstrap confidence intervals and plots. The first needs real
resampling machinery to be worth trusting; the second needs a renderer. R^2 plus an outlier count
carries most of what the plots would have told you, in one column.
*/
package bench

import "base:intrinsics"
import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:io"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// Handed to every benchmark procedure. `n` is the iteration count the harness wants for this sample;
// the benchmark's only obligation is to loop exactly that many times.
B :: struct {
	// How many iterations to run. Set by the harness before each call - never write to it.
	n:     int,
	// Bytes processed per iteration. Write it once (in setup or on the first call) to get a MB/s
	// column; leave it zero for benchmarks where throughput is not a meaningful unit.
	bytes: int,
	// Anything the benchmark's setup wants to hand to its body and teardown.
	data:  rawptr,
}

// One registered benchmark. `setup` and `teardown` may be nil.
Case :: struct {
	name:     string,
	bench:    proc(b: ^B),
	setup:    proc(b: ^B),
	teardown: proc(b: ^B),
}

Stats :: struct {
	// The headline number: nanoseconds per iteration, as the slope of a line fitted through samples
	// taken at a ramp of iteration counts. See `run_case` for why this is not just `elapsed / iters`.
	slope:     f64,
	// The fitted line's constant term, in nanoseconds: what one *sample* costs before any iteration of
	// the benchmark runs - two clock reads and an indirect call. Not part of the headline number, which
	// is the point of fitting a line rather than dividing.
	intercept: f64,
	// How well the samples fit that line, 0 to 1. Low means the benchmark is not measuring one thing.
	r_squared: f64,
	median:    f64,
	mean:      f64,
	min:       f64,
	max:       f64,
	// Median absolute deviation: the median of each sample's distance from the median. Unlike a
	// standard deviation it is not dragged around by the one sample that landed on a scheduler
	// preemption, which is exactly the shape of noise a benchmark collects.
	mad:       f64,
	// Samples outside Tukey's fences - see `count_outliers`.
	mild:      int,
	severe:    int,
}

Result :: struct {
	name:        string,
	// The largest iteration count in the ramp, which is the last and longest sample.
	iters:       int,
	samples:     int,
	ns_per_iter: Stats,
	mb_per_sec:  f64,
	// True when calibration never got a measurable reading - see `run_case`. The number in this row is
	// not a measurement of anything.
	suspect:     bool,
	// Every sample's ns/iter, intercept-corrected. Kept in the report rather than summarised away
	// because the comparison test needs both runs' distributions, not their summaries - see
	// `mann_whitney`. This is most of the JSON's size and all of its usefulness.
	raw:         []f64,
}

// The on-disk shape. `version` is here so a future change to the format can be detected rather than
// misread: a baseline written by an older harness is worth a clear error, not a silent wrong diff.
Report :: struct {
	version:      int,
	odin_os:      string,
	odin_arch:    string,
	optimization: string,
	results:      []Result,
}

REPORT_VERSION :: 1

Options :: struct {
	filter:          string `args:"pos=0" usage:"Only run benchmarks whose name contains this substring."`,
	exact:           bool `usage:"Match the filter as a whole name rather than a substring."`,
	list:            bool `usage:"List benchmark names and exit."`,
	samples:         int `usage:"Samples to collect per benchmark. (default 50)"`,
	sample_time:     int `usage:"Target wall time per sample, in milliseconds. (default 10)"`,
	warmup:          int `usage:"Warmup time per benchmark, in milliseconds. (default 200)"`,
	json:            string `usage:"Write results as JSON to this path ('-' for stdout)."`,
	baseline:        string `usage:"Compare results against a JSON report written by --json."`,
	threshold:       f64 `usage:"Percent change before a difference is worth calling out. (default 5)"`,
	alpha:           f64 `usage:"Significance level for the Mann-Whitney test. (default 0.05)"`,
	fail_on_regress: bool `usage:"Exit non-zero if any benchmark regressed past both bars."`,
	fixed_iters:     int `usage:"Run each benchmark exactly this many iterations, once, timing nothing. For counting instructions under callgrind - see 'just bench_count'."`,
}

// R^2 below this and the samples are not describing one thing - see `fit_line`. Deliberately strict:
// a clean microbenchmark on an idle machine fits at 0.999+, so 0.99 is already a complaint.
MIN_GOOD_FIT :: 0.99

// A line needs points. Fewer than this and there is no fit, no quartiles and no rank test - the run
// would report zeros rather than fail, which is the worst of the available behaviours. Four is the
// arithmetic floor; anything you would act on wants far more.
MIN_SAMPLES :: 4

/*
Consume a value so the optimizer cannot delete the code that produced it.

Odin has no `black_box`. Without one, `-o:speed` is entitled to notice that a loop body's result is
never read and delete the whole loop, and it does: a loop over `x * x + 7` with the result discarded
measures 97ns for a hundred million iterations, which is to say it measures nothing.

The barrier is a volatile store of the value itself. Volatile means the compiler may not remove,
reorder or coalesce the access, so the store must happen, so everything that computed the stored value
must run. The cost is one store per call.

It has to be the value. The first version of this stored the value's *address* to a global instead, on
the theory that an escaped pointer keeps the pointee alive - and it does not. With no call between the
escape and the end of the procedure, LLVM proves nothing can read the local, drops the store that
filled it, and deletes everything upstream. The generated code for a 1024-element sum was the volatile
store and a loop counter, with no adds and no loads: a benchmark reporting 13 TB/s. Nothing about the
output said so; `-build-mode:asm` did.
*/
keep :: #force_inline proc(value: $T) {
	v: T
	intrinsics.volatile_store(&v, value)
}

/*
Launder a value so the optimizer cannot constant-fold through it.

The mirror of `keep`, for inputs: `format(3.14159)` with a literal argument can be computed at compile
time and hoisted out of the loop entirely. Passing it through a volatile load makes the value opaque -
the compiler must reload it every iteration and cannot reason about what it holds.

	x := bench.opaque(3.14159)   // now the compiler does not know x is 3.14159
*/
opaque :: #force_inline proc(value: $T) -> T {
	v: T
	intrinsics.volatile_store(&v, value)
	return intrinsics.volatile_load(&v)
}

// Below this a sample is measuring the clock rather than the code: `tick_now` resolution plus the
// call overhead is tens of nanoseconds, so a sample has to be several orders of magnitude larger
// than that before its per-iteration figure means anything.
MIN_CALIBRATION_NS :: 1_000_000

// A ceiling on the doubling search. A loop that survives the optimizer costs at least ~0.15ns an
// iteration, so 2^32 of them is several seconds - far past any sane sample. Reaching this ceiling
// without a measurable reading means the loop is not there any more, which is why it is a diagnosis
// (`suspect`) rather than just a stopping condition.
MAX_ITERS :: 1 << 32

run_case :: proc(c: Case, opt: Options) -> Result {
	b: B

	if c.setup != nil {
		b.n = 1
		c.setup(&b)
	}
	defer if c.teardown != nil {
		c.teardown(&b)
	}

	sample :: proc(c: Case, b: ^B, n: int) -> f64 {
		b.n = n
		start := time.tick_now()
		c.bench(b)
		return f64(time.duration_nanoseconds(time.tick_since(start)))
	}

	// Warmup doubles the iteration count until it has both burned the requested warmup time and taken
	// a reading long enough to extrapolate from. Doubling rather than guessing because the harness has
	// no idea whether one iteration costs a nanosecond or a second, and a wrong guess in the cheap
	// direction wastes a minute while a wrong guess in the expensive direction wastes an hour.
	//
	// Once a reading is long enough, `n` stops growing and the remaining warmup runs at that size:
	// warmup exists to get the caches and the clock speed where the measured samples will find them,
	// not to keep inflating the loop.
	warmup_ns := f64(opt.warmup) * 1e6
	n := 1
	burned, per_iter: f64
	converged := false
	for {
		ns := sample(c, &b, n)
		burned += ns
		if ns > 0 {
			per_iter = ns / f64(n)
		}
		if ns >= MIN_CALIBRATION_NS {
			converged = true
			if burned >= warmup_ns {
				break
			}
			continue
		}
		if n >= MAX_ITERS {
			break
		}
		n *= 2
	}

	/*
	Samples are taken at a *ramp* of iteration counts - d, 2d, 3d, ... - rather than all at one count.
	This is criterion's idea and it is the reason the harness can report a per-iteration cost that does
	not include the cost of measuring.

	Measure-N-and-divide folds every fixed cost into the answer: the two `tick_now` calls, the indirect
	call through `c.bench`, the loop setup. At 0.15ns an iteration those are not a rounding error. A ramp
	instead gives points that should lie on a line, `elapsed = intercept + slope * iters`, where the
	intercept *is* that fixed cost and the slope is the part you asked about. Fitting the line separates
	them; dividing cannot.

	`d` is chosen so the ramp's total iteration count fills the requested measurement budget: the sum of
	1..N multiples of d is d*N*(N+1)/2, so d = budget / (N*(N+1)/2). The largest sample runs about twice
	the iterations that the old flat scheme would have used, and the whole run takes the same time.

	A ramp needs distinct iteration counts to be a ramp at all, and that is not free for a slow
	benchmark. N samples cannot use fewer than 1+2+...+N = N(N+1)/2 iterations between them, so once one
	iteration costs more than about `2 * sample_time`, the budget cannot pay for the requested number of
	samples. The first version of this ignored that: `d` fell below 1/N, every sample rounded to a single
	iteration, no two x values differed, the fit had no pair to take a slope from and the row printed
	`0.000 ns` at `R^2 0.0000` - a fabricated number with no flag on it beyond the generic POOR FIT note.
	Any benchmark costing more than ~20ms an iteration hit it under the default flags.

	So the sample count is reduced to what the budget can actually buy, rather than the ramp being
	squashed until it is not one. Fewer samples is a real cost - the comparison test has less to work
	with - but it is a cost the report can state, where a fabricated slope is not.
	*/
	budget_ns := f64(opt.sample_time) * 1e6 * f64(opt.samples)
	total_iters := f64(MAX_ITERS)
	if per_iter > 0 {
		total_iters = min(budget_ns / per_iter, f64(MAX_ITERS))
	}

	// Largest N with N(N+1)/2 <= total_iters, i.e. the most samples whose minimum ramp fits the budget.
	samples := opt.samples
	if affordable := int((math.sqrt(1 + 8 * total_iters) - 1) / 2); affordable < samples {
		samples = clamp(affordable, MIN_SAMPLES, opt.samples)
	}
	d := total_iters / (f64(samples) * f64(samples + 1) / 2)

	xs := make([]f64, samples)
	ys := make([]f64, samples)
	defer delete(xs)
	defer delete(ys)
	largest := 1
	for i in 0 ..< samples {
		// The `i + 1` floor is what guarantees the x values are distinct and increasing even when `d`
		// rounds to nothing. Without it the fit has no pair of points to take a slope from.
		iters := clamp(max(int(d * f64(i + 1) + 0.5), i + 1), 1, MAX_ITERS)
		largest = max(largest, iters)
		xs[i] = f64(iters)
		ys[i] = sample(c, &b, iters)
	}

	slope, intercept, r2 := fit_line(xs, ys)

	// Per-sample figures for the spread and for the comparison test, each corrected by the fitted
	// intercept so a sample taken at 1000 iterations is comparable with one taken at 50000. Without the
	// correction the early, short samples read high purely because they amortise the fixed cost over
	// fewer iterations, and the "spread" would be measuring the ramp rather than the machine.
	raw := make([]f64, samples)
	for i in 0 ..< samples {
		raw[i] = (ys[i] - intercept) / xs[i]
	}

	st := compute_stats(raw)
	st.slope = slope
	st.intercept = intercept
	st.r_squared = r2

	if samples < opt.samples {
		fmt.eprintfln(
			"note: %s costs ~%s an iteration, so %d samples do not fit a %dms budget - used %d",
			c.name,
			format_ns(per_iter),
			opt.samples,
			opt.sample_time,
			samples,
		)
	}

	res := Result {
		name        = c.name,
		iters       = largest,
		samples     = samples,
		ns_per_iter = st,
		raw         = raw,
		// Two ways to end up with a number that measures nothing, both flagged rather than printed as a
		// result. Billions of iterations still timed as free is not a fast procedure, it is an absent
		// one - the optimizer removed the loop. A slope of zero out of a non-degenerate ramp means the
		// fit found nothing to fit, which should now be impossible (the ramp is forced to be strictly
		// increasing) but is worth catching if that ever changes.
		suspect     = !converged || slope <= 0,
	}
	if b.bytes > 0 && slope > 0 {
		res.mb_per_sec = f64(b.bytes) / (slope * 1e-9) / (1024 * 1024)
	}
	return res
}

/*
Theil-Sen regression through (x, y), returning slope, intercept and R^2.

Theil-Sen rather than ordinary least squares, because OLS is not robust and benchmark samples are not
clean. The slope is the *median* of the slopes between every pair of points; the intercept is the
median of `y - slope*x`. Both survive up to ~29% of the samples being garbage, where OLS - which
minimises *squared* error, so one bad point pulls quadratically hard - does not.

That is not a theoretical worry. A 30-sample run of `lib.add_sum` on this machine had 28 samples at
~56.5 ns and two at ~84 ns, from something else waking up on the same core. OLS reported 59.2 ns.
Theil-Sen reports 56.4 ns. A 5% error is exactly the size of regression the diff exists to catch, so an
estimator that manufactures one is not usable.

R^2 is then measured against that robust line, and is the cheap stand-in for the plots this harness does
not draw: the samples *should* lie on a line, and how well they do says whether the benchmark measured
one thing. Note that R^2 against a robust line is not the quantity OLS maximises, so it reads lower for
the same data - which is the honest reading. Below ~0.99 the usual causes are the machine drifting
mid-run, or a benchmark with two modes (two code paths, a branch predictor flipping state, an allocator
crossing a size class). One number cannot describe two modes.

O(n^2) in the sample count: 50 samples is 1225 pairwise slopes, which is nothing next to the seconds
just spent collecting them.
*/
fit_line :: proc(xs, ys: []f64) -> (slope, intercept, r_squared: f64) {
	n := len(xs)
	if n < 2 {
		return
	}

	slopes := make([dynamic]f64, 0, n * (n - 1) / 2)
	defer delete(slopes)
	for i in 0 ..< n {
		for j in i + 1 ..< n {
			dx := xs[j] - xs[i]
			if dx != 0 {
				append(&slopes, (ys[j] - ys[i]) / dx)
			}
		}
	}
	if len(slopes) == 0 {
		return
	}
	slice.sort(slopes[:])
	slope = median_of_sorted(slopes[:])

	residuals := make([]f64, n)
	defer delete(residuals)
	for x, i in xs {
		residuals[i] = ys[i] - slope * x
	}
	slice.sort(residuals)
	intercept = median_of_sorted(residuals)

	sum_y: f64
	for y in ys {
		sum_y += y
	}
	mean_y := sum_y / f64(n)

	ss_res, ss_tot: f64
	for x, i in xs {
		resid := ys[i] - (intercept + slope * x)
		ss_res += resid * resid
		dy := ys[i] - mean_y
		ss_tot += dy * dy
	}
	if ss_tot > 0 {
		r_squared = 1 - ss_res / ss_tot
	}
	return
}

/*
Count samples outside Tukey's fences: beyond 1.5 IQR from the quartiles is mild, beyond 3.0 is severe.

criterion prints this and it is worth copying, because it names what a spread figure only hints at. A
MAD of 5% could mean every sample is a little scattered, or that 28 of 30 are identical and two came
back from a scheduler preemption. Those want different reactions - the first is a noisy machine, the
second is two samples to ignore - and only a count tells them apart.
*/
count_outliers :: proc(sorted: []f64) -> (mild, severe: int) {
	// Quartiles taken from a handful of points are not quartiles. Below this the honest answer is no
	// answer - reporting "2 severe outliers" out of 5 samples invents a diagnosis from nothing.
	n := len(sorted)
	if n < 10 {
		return
	}
	q1 := sorted[n / 4]
	q3 := sorted[(3 * n) / 4]
	iqr := q3 - q1
	if iqr <= 0 {
		return
	}
	for v in sorted {
		switch {
		case v < q1 - 3.0 * iqr, v > q3 + 3.0 * iqr:
			severe += 1
		case v < q1 - 1.5 * iqr, v > q3 + 1.5 * iqr:
			mild += 1
		}
	}
	return
}

compute_stats :: proc(samples: []f64) -> (st: Stats) {
	if len(samples) == 0 {
		return
	}

	xs := slice.clone(samples)
	defer delete(xs)
	slice.sort(xs)

	st.min = xs[0]
	st.max = xs[len(xs) - 1]
	st.median = median_of_sorted(xs)

	total: f64
	for x in xs {
		total += x
	}
	st.mean = total / f64(len(xs))

	dev := make([]f64, len(xs))
	defer delete(dev)
	for x, i in xs {
		dev[i] = abs(x - st.median)
	}
	slice.sort(dev)
	st.mad = median_of_sorted(dev)

	st.mild, st.severe = count_outliers(xs)
	return
}

/*
Two-sided Mann-Whitney U test: the probability that two sets of samples came from the same distribution.

This answers "did it move" properly, where a percentage against a threshold only guesses. It is a rank
test - it throws away the magnitudes and keeps only the order of the pooled samples - which is why it
needs no assumption that timings are normally distributed. They are not: a timing distribution has a
hard floor at the fastest the code can go and a long tail of everything the OS did to it, and a t-test
reads that skew as signal.

The returned p is the chance of seeing an ordering at least this lopsided if the two runs really were
the same. Small p means the difference is real. It does *not* mean the difference is worth caring
about: with 50 samples of a quiet benchmark, a 0.3% change is easily significant. That is why the
caller also applies a magnitude threshold, and why the two are separate ideas rather than one number.

The normal approximation to U is used, with the standard tie correction. It wants both groups above
about 8 samples, which `--samples` defaults far past.
*/
mann_whitney :: proc(a, b: []f64) -> (p: f64) {
	n1, n2 := len(a), len(b)
	if n1 < 2 || n2 < 2 {
		return 1
	}

	Tagged :: struct {
		value: f64,
		is_a:  bool,
	}

	pooled := make([]Tagged, n1 + n2)
	defer delete(pooled)
	for v, i in a {
		pooled[i] = {v, true}
	}
	for v, i in b {
		pooled[n1 + i] = {v, false}
	}
	slice.sort_by(pooled, proc(i, j: Tagged) -> bool {
		return i.value < j.value
	})

	// Ranks are 1-based, and tied values all take the mean of the ranks they span - without that, the
	// result depends on which order equal timings happened to be collected in. `tie_sum` accumulates
	// the correction term the variance needs, one `t^3 - t` per group of ties.
	rank_a, tie_sum: f64
	i := 0
	for i < len(pooled) {
		j := i
		for j + 1 < len(pooled) && pooled[j + 1].value == pooled[i].value {
			j += 1
		}
		count := j - i + 1
		mean_rank := f64(i + j + 2) / 2
		for k in i ..= j {
			if pooled[k].is_a {
				rank_a += mean_rank
			}
		}
		t := f64(count)
		tie_sum += t * t * t - t
		i = j + 1
	}

	nn1, nn2 := f64(n1), f64(n2)
	n := nn1 + nn2
	u1 := rank_a - nn1 * (nn1 + 1) / 2
	u := min(u1, nn1 * nn2 - u1)

	mean_u := nn1 * nn2 / 2
	var_u := (nn1 * nn2 / 12) * ((n + 1) - tie_sum / (n * (n - 1)))
	if var_u <= 0 {
		return 1
	}

	// The 0.5 is the continuity correction: U is discrete and the normal curve is not.
	z := (abs(u - mean_u) - 0.5) / math.sqrt(var_u)
	if z < 0 {
		return 1
	}
	return math.erfc(z / math.SQRT_TWO)
}

median_of_sorted :: proc(xs: []f64) -> f64 {
	n := len(xs)
	switch {
	case n == 0:
		return 0
	case n % 2 == 1:
		return xs[n / 2]
	case:
		return (xs[n / 2 - 1] + xs[n / 2]) * 0.5
	}
}

// "us" rather than "µs" on purpose: this prints to whatever console the user has, and Windows cmd's
// default code page turns a non-ASCII byte into mojibake.
format_ns :: proc(ns: f64) -> string {
	switch {
	case ns < 1e3:
		return fmt.tprintf("%.3f ns", ns)
	case ns < 1e6:
		return fmt.tprintf("%.3f us", ns / 1e3)
	case ns < 1e9:
		return fmt.tprintf("%.3f ms", ns / 1e6)
	case:
		return fmt.tprintf("%.3f s", ns / 1e9)
	}
}

// Every number reaches a `%s` verb as an already-formatted string. Odin's `fmt` pads numeric verbs
// with zeros rather than spaces when a width is given - `%14.1f` on 52735689.8 prints
// `000052735689.8` - so a width on a float verb is a formatting bug waiting to be shipped.
print_results :: proc(results: []Result, w: io.Writer) {
	width := 4
	for r in results {
		width = max(width, len(r.name))
	}

	fmt.wprintfln(
		w,
		"%-*s  %14s  %10s  %7s  %12s  %s",
		width,
		"name",
		"ns/iter",
		"+/-mad",
		"R^2",
		"throughput",
		"samples",
	)
	any_suspect, any_bad_fit := false, false
	for r in results {
		throughput := ""
		if r.mb_per_sec > 0 {
			throughput = fmt.tprintf("%.1f MB/s", r.mb_per_sec)
		}
		mark := ""
		switch {
		case r.suspect:
			mark = "  <- OPTIMIZED AWAY"
			any_suspect = true
		case r.ns_per_iter.r_squared < MIN_GOOD_FIT:
			mark = fmt.tprintf("  <- POOR FIT (%d severe, %d mild outliers)", r.ns_per_iter.severe, r.ns_per_iter.mild)
			any_bad_fit = true
		case r.ns_per_iter.severe > 0:
			mark = fmt.tprintf("  <- %d severe outliers", r.ns_per_iter.severe)
		}
		fmt.wprintfln(
			w,
			"%-*s  %14s  %10s  %7s  %12s  %d x %d%s",
			width,
			r.name,
			format_ns(r.ns_per_iter.slope),
			format_ns(r.ns_per_iter.mad),
			fmt.tprintf("%.4f", r.ns_per_iter.r_squared),
			throughput,
			r.samples,
			r.iters,
			mark,
		)
	}
	if any_suspect {
		fmt.wprintln(w)
		fmt.wprintln(
			w,
			"OPTIMIZED AWAY: calibration never produced a measurable reading - the compiler deleted the loop.",
		)
		fmt.wprintln(w, "Check that every result reaches keep() and that the loop body is not loop-invariant.")
	}
	if any_bad_fit {
		fmt.wprintln(w)
		fmt.wprintfln(
			w,
			"POOR FIT: the samples do not lie on a line (R^2 < %.2f), so one number does not describe them.",
			MIN_GOOD_FIT,
		)
		fmt.wprintln(
			w,
			"A few severe outliers means the machine was busy - re-run on an idle one. Outliers spread across",
		)
		fmt.wprintln(
			w,
			"the run means drift; many mild ones with no severe ones means the benchmark itself has two modes.",
		)
		fmt.wprintln(
			w,
			"The reported ns/iter is a robust (Theil-Sen) fit, so it survives this - but the spread is not real.",
		)
	}
}

/*
Compare against a baseline report and return true if anything regressed.

A row is called out only when it clears two independent bars, which answer two different questions:

  * `p < alpha` - *is it real?* A two-sided Mann-Whitney U test over both runs' samples. This is the
    statistical bar, and it is the one a percentage cannot supply: it knows how much the two runs
    scattered, so a 6% move on a benchmark that scatters by 5% does not clear it, while a 0.4% move on
    one that scatters by 0.02% does.
  * `|delta| >= threshold` - *do I care?* With enough samples the test will find differences far below
    the size worth acting on. The threshold is where you say how small is too small to matter.

Reporting either bar alone produces a diff people stop reading. Significance alone flags every run;
percentage alone flags every warm afternoon.

What neither bar covers is drift *between* runs. Both are computed from samples collected within one
run, minutes apart from the baseline's. On a machine that is doing anything else - a laptop warming up,
a shared CI runner - identical code can differ by 5-10%, and that difference is both real and
significant, because the machine really did change. The test cannot tell you which of the machine and
the code moved. Treat a single red row as a prompt to re-run, and read the note on `--fail-on-regress`
in the README before gating a merge on this.
*/
compare :: proc(current: []Result, base: Report, threshold, alpha: f64, w: io.Writer) -> (regressed: bool) {
	width := 4
	for r in current {
		width = max(width, len(r.name))
	}
	for r in base.results {
		width = max(width, len(r.name))
	}

	// A baseline recorded elsewhere is not wrong to look at, but the diff against it is measuring the
	// two machines as much as the two revisions, so say so rather than letting the percentages imply
	// more than they know.
	now_os, now_arch, now_opt :=
		fmt.tprintf("%v", ODIN_OS), fmt.tprintf("%v", ODIN_ARCH), fmt.tprintf("%v", ODIN_OPTIMIZATION_MODE)
	if base.odin_os != now_os || base.odin_arch != now_arch || base.optimization != now_opt {
		fmt.wprintfln(
			w,
			"\nwarning: baseline was recorded on %s/%s at -o:%s, this run is %s/%s at -o:%s",
			base.odin_os,
			base.odin_arch,
			base.optimization,
			now_os,
			now_arch,
			now_opt,
		)
	}

	fmt.wprintln(w)
	fmt.wprintfln(w, "%-*s  %14s  %14s  %9s  %9s", width, "name", "baseline", "current", "delta", "p")
	for r in current {
		old, found := find_result(base.results, r.name)
		if !found {
			fmt.wprintfln(
				w,
				"%-*s  %14s  %14s  %9s  %9s  new",
				width,
				r.name,
				"-",
				format_ns(r.ns_per_iter.slope),
				"-",
				"-",
			)
			continue
		}

		delta := r.ns_per_iter.slope - old.ns_per_iter.slope
		pct := 0.0
		if old.ns_per_iter.slope > 0 {
			pct = delta / old.ns_per_iter.slope * 100
		}

		// A baseline written before the raw samples were recorded, or by `--samples=1`, leaves nothing
		// to test. Fall back to the threshold alone rather than silently calling everything unchanged.
		p := 1.0
		have_test := len(r.raw) >= 2 && len(old.raw) >= 2
		if have_test {
			p = mann_whitney(old.raw, r.raw)
		}

		verdict := ""
		if abs(pct) >= threshold && (!have_test || p < alpha) {
			if delta > 0 {
				verdict = "REGRESS"
				regressed = true
			} else {
				verdict = "improve"
			}
			if !have_test {
				verdict = fmt.tprintf("%s (no test)", verdict)
			}
		}

		p_text := "-"
		if have_test {
			p_text = fmt.tprintf("%.4f", p)
		}

		fmt.wprintfln(
			w,
			"%-*s  %14s  %14s  %9s  %9s  %s",
			width,
			r.name,
			format_ns(old.ns_per_iter.slope),
			format_ns(r.ns_per_iter.slope),
			fmt.tprintf("%+.1f%%", pct),
			p_text,
			verdict,
		)
	}

	for old in base.results {
		if _, found := find_result(current, old.name); !found {
			fmt.wprintfln(
				w,
				"%-*s  %14s  %14s  %9s  %9s  gone",
				width,
				old.name,
				format_ns(old.ns_per_iter.slope),
				"-",
				"-",
				"-",
			)
		}
	}
	return
}

find_result :: proc(results: []Result, name: string) -> (Result, bool) {
	for r in results {
		if r.name == name {
			return r, true
		}
	}
	return {}, false
}

main :: proc() {
	opt := Options {
		samples     = 50,
		sample_time = 10,
		warmup      = 200,
		threshold   = 5,
		alpha       = 0.05,
	}
	flags.parse_or_exit(&opt, os.args, .Unix)

	if opt.samples < MIN_SAMPLES {
		fmt.eprintfln("--samples=%d is below the minimum of %d; using %d", opt.samples, MIN_SAMPLES, MIN_SAMPLES)
		opt.samples = MIN_SAMPLES
	}

	// Substring by default, because that is what makes a dotted prefix useful for selecting a group.
	// `--exact` exists for callers that hold a name and mean only that one: `just bench_count` feeds
	// each name from `--list` straight back in, and with substring matching a benchmark named
	// `bench.parse` would also run `bench.parse_json` and silently record the sum of the two.
	selected := make([dynamic]Case)
	defer delete(selected)
	for c in CASES {
		matched := opt.filter == "" || (opt.exact ? c.name == opt.filter : strings.contains(c.name, opt.filter))
		if matched {
			append(&selected, c)
		}
	}

	// Before `--list` and before counting mode: every path below is meaningless without a benchmark to
	// run, and counting mode in particular would otherwise exit 0 having measured nothing, leaving the
	// callgrind driver to subtract two identical startup counts and report the difference as a result.
	if len(selected) == 0 {
		fmt.eprintfln("no benchmarks match %q (%d registered)", opt.filter, len(CASES))
		os.exit(1)
	}

	if opt.list {
		for c in selected {
			fmt.println(c.name)
		}
		return
	}

	/*
	Counting mode. No clock is read, nothing is warmed up, and no statistics are produced: each
	benchmark runs its body exactly once with `b.n` fixed, and something outside this process does the
	measuring. That something is callgrind, which counts executed instructions by simulation rather
	than by sampling - see `just bench_count`.

	The point of a fixed iteration count is that the caller can run this twice, at N and 2N, and
	subtract. Everything that is not the loop - process startup, runtime init, `setup`, the allocation
	it did, valgrind's own overhead - happens identically in both runs and cancels exactly. What is
	left is N iterations of the body and nothing else. The harness cannot do that subtraction itself,
	because it cannot see its own instruction count.
	*/
	if opt.fixed_iters > 0 {
		for c in selected {
			b: B
			// `b.n = 1` before setup, matching `run_case`. A setup that sizes a buffer from `b.n` would
			// otherwise allocate one element under `just bench` and `--fixed-iters` elements here, and
			// the timing and counting modes would be measuring different work.
			b.n = 1
			if c.setup != nil {
				c.setup(&b)
			}
			b.n = opt.fixed_iters
			c.bench(&b)
			if c.teardown != nil {
				c.teardown(&b)
			}
			fmt.eprintfln("ran %s x %d", c.name, opt.fixed_iters)
		}
		return
	}

	// Read the baseline before running anything: a typo in the path should cost a second, not the
	// several minutes of measurement that would otherwise be thrown away at the end.
	base: Report
	if opt.baseline != "" {
		data, rerr := os.read_entire_file(opt.baseline, context.allocator)
		if rerr != nil {
			fmt.eprintfln("cannot read baseline %q: %v", opt.baseline, rerr)
			os.exit(1)
		}
		defer delete(data)
		if jerr := json.unmarshal(data, &base); jerr != nil {
			fmt.eprintfln("cannot parse baseline %q: %v", opt.baseline, jerr)
			os.exit(1)
		}
		if base.version != REPORT_VERSION {
			fmt.eprintfln(
				"baseline %q is format version %d, this harness writes version %d - re-record it",
				opt.baseline,
				base.version,
				REPORT_VERSION,
			)
			os.exit(1)
		}
	}

	results := make([]Result, len(selected))
	defer {
		for r in results {
			delete(r.raw)
		}
		delete(results)
	}
	for c, i in selected {
		fmt.eprintfln("running %s ...", c.name)
		results[i] = run_case(c, opt)
	}
	fmt.eprintln()

	// `--json=-` means somebody is piping stdout into a file or another tool, so the human tables move
	// out of the way rather than corrupting it. Progress lines are already on stderr for this reason.
	report_writer := os.to_writer(os.stdout)
	if opt.json == "-" {
		report_writer = os.to_writer(os.stderr)
	}

	print_results(results, report_writer)

	if opt.json != "" {
		report := Report {
			version      = REPORT_VERSION,
			odin_os      = fmt.tprintf("%v", ODIN_OS),
			odin_arch    = fmt.tprintf("%v", ODIN_ARCH),
			optimization = fmt.tprintf("%v", ODIN_OPTIMIZATION_MODE),
			results      = results,
		}
		data, merr := json.marshal(report, {pretty = true, use_spaces = true, spaces = 2})
		if merr != nil {
			fmt.eprintfln("cannot encode results: %v", merr)
			os.exit(1)
		}
		defer delete(data)

		if opt.json == "-" {
			fmt.println(string(data))
		} else if werr := os.write_entire_file(opt.json, data); werr != nil {
			fmt.eprintfln("cannot write %q: %v", opt.json, werr)
			os.exit(1)
		}
	}

	if opt.baseline != "" {
		regressed := compare(results, base, opt.threshold, opt.alpha, report_writer)
		if regressed && opt.fail_on_regress {
			os.exit(1)
		}
	}
}
