# Benchmarking

`bench/` holds the harness, your benchmarks, and a `bench.just` carrying the recipes. The project
justfile's `import? 'bench/bench.just'` is an *optional* import: it does nothing while the directory is
absent, so the `just bench*` recipes appear the moment it arrives and `rm -rf bench/` takes them away
again. The harness is `package bench` rather than `package main` on purpose — an executable project's
root is already `package main`, and Odin permits only one package of a given name per build.

```
just bench [NAME] [--samples=N …]   # build and run; NAME filters by substring
just bench_build / rerun_bench      # build without running / run without rebuilding
just bench_lint                     # type check and vet bench/, which the root `lint` does not reach
just bench_save / bench_cmp         # record a timing baseline / re-run and diff against it
just bench_count / bench_count_check
```

## Why not `core:time.benchmark`

Odin has no `cargo bench`. `core:time` has a `benchmark()` procedure, and it is worth knowing what it
is before reaching for it: it calls your procedure **once**, wraps it in a stopwatch, and divides. The
`rounds` field is inert — a number your own procedure is expected to loop over. No warmup, no repeat
samples, no spread, no baseline. That is a stopwatch, and a stopwatch cannot answer "did this change
make it slower", which is the question a benchmark suite exists for.

`bench/` is a small harness on top of the same clock, borrowing the ideas that make
[criterion](https://github.com/bheisler/criterion.rs) (Haskell first, then Rust) worth using:

* **warm up**, so the first sample is not measuring a cold i-cache and an idling clock
* **sample across a ramp of iteration counts and fit a line.** Not measure-N-and-divide. The slope is
  the per-iteration cost; the intercept absorbs the cost of measuring — two clock reads and an indirect
  call, which at sub-nanosecond scale is most of what divide-by-N would have reported
* **fit robustly** (Theil–Sen, the median of pairwise slopes), so two preempted samples cannot move the
  answer the way least-squares lets them
* **report R² and outlier counts**, which say whether the samples describe one thing at all
* **test against the baseline** with a two-sided Mann–Whitney U test, so a change is called out on a
  p-value plus a magnitude threshold rather than a percentage alone
* **write JSON** (`--json=PATH`, or `-` for stdout) carrying every sample, because the test needs the
  distributions and not their summaries

```
$ just bench
name                     ns/iter      +/-mad      R^2    throughput  samples
bench.empty_loop        0.117 ns    0.000 ns   0.9998                50 x 165371824
lib.add                 0.419 ns    0.000 ns   0.9999                50 x 46658006
lib.add_sum            56.367 ns    0.098 ns   0.9373  138600.6 MB/s  50 x 342761  <- POOR FIT (3 severe, 1 mild outliers)
```

```
$ just bench_cmp
name                    baseline         current      delta          p
bench.empty_loop        0.120 ns        0.118 ns      -1.5%     0.0000
lib.add                 0.419 ns        0.421 ns      +0.5%     0.0701
lib.add_sum            56.447 ns       56.726 ns      +0.5%     0.2838
```

Read that second table carefully, because it is the whole point. `empty_loop` moved by a **statistically
certain** 1.5% (p = 0.0000) — the machine really did change — and is not called out, because 1.5% is
below the threshold you said you cared about. `lib.add` moved 0.5% at p = 0.07, which is not even real.
Nothing fires. The earlier version of this diff, which compared percentages against a spread heuristic,
printed `+32% REGRESS` on this same unchanged code.

## The part that actually matters: `keep` and `opaque`

Odin has no `black_box`. At `-o:speed` a loop whose result nothing reads is dead code, and LLVM deletes
it — the benchmark then reports the cost of an empty loop and nothing warns you. Two helpers stand in:

* `keep(value)` — volatile-stores the value, so everything that computed it has to run
* `opaque(value)` — round-trips the value through a volatile store and load, so the compiler cannot
  constant-fold through it or hoist it out of the loop

Use both, and read `bench.odin` before writing your first case: it documents the four rules and the two
failure modes that survive them. Both bit this harness during development. A sum over a fixed
1024-element slice reported **13 TB/s** because the slice never changed, so the whole inner loop was
loop-invariant and got hoisted; an `acc = add(acc, i)` chain was replaced outright by the closed form
`n * (n - 1) / 2`. Neither shows up as an error — only as an implausible number.

The harness flags the extreme case: when calibration runs to billions of iterations without a
measurable reading, the row is marked `OPTIMIZED AWAY` rather than printed as a result. The subtler
cases it cannot detect. `bench.empty_loop` is the sanity check to compare against — nothing real is
faster than the loop itself — and `odin build bench -o:speed -build-mode:asm` is the way to settle it,
which is how both of the above were found.

## Reading R² and the outlier counts

`R^2` is how well the samples fit the line, and it is the stand-in for the plots this harness does not
draw. Above ~0.999 on an idle machine. When it drops, the outlier counts say why:

* **a few severe outliers, R² poor** — something else woke up on your core. Re-run. The reported ns/iter
  is a robust fit and survives this; the spread column does not
* **many mild, no severe** — the benchmark itself has two modes: two code paths, a branch predictor
  flipping state, an allocator crossing a size class. One number cannot describe it, and no amount of
  re-running will fix that. Split the benchmark
* **outliers spread evenly through the run** — drift, usually thermal

## Baselines, and where this stops being trustworthy

```
just bench_save     # record target/release/bench-baseline.json
just bench_cmp      # after changing something: re-run and diff against it
```

A row is called out only when the change clears two independent bars, which answer different questions:

* **is it real?** — `p < --alpha` (default 0.05), from the Mann–Whitney U test over both runs' samples.
  A rank test, so it assumes nothing about the shape of the distribution; timing distributions have a
  hard floor and a long tail, and a t-test would read that skew as signal
* **do I care?** — `|delta| >= --threshold` (default 5%). With 50 samples the test finds differences far
  below the size worth acting on, so this is where you say how small is too small

Neither bar covers drift *between* runs. Both are computed within one run, minutes after the baseline's,
and on a machine doing anything else — a laptop warming up, a shared CI runner — identical code drifts
5–10%. That drift is both real and significant, because the machine really did change; the test cannot
tell you whether the machine or the code moved. Baselines are per machine for the same reason, which is
why they live in `target/` and are not committed. The diff warns when the recorded OS, architecture or
optimization level differs from the current run, but it cannot warn about the machine being busy.

So: `--fail-on-regress` exists, and putting it on a shared runner produces a gate people re-trigger
until it goes green, which is worse than no gate. If you want a real regression gate, gate on
instruction counts instead of wall time — `perf stat -e instructions:u ./target/release/bench.exe` on
Linux varies by a fraction of a percent where wall time varies by ten. What this harness is good at is
the local loop: record a baseline, change something, see whether it moved.

### Instruction counts: the gate that does not flake

```
just bench_count           # record bench/instructions.json
just bench_count_check     # re-measure and diff; exits non-zero on a regression
```

Needs [valgrind](https://valgrind.org/) (`apt install valgrind`; not available on Windows).

This measures **executed instructions**, not time, by running the benchmarks under callgrind — which
counts by simulating every instruction rather than sampling a hardware counter. The same binary yields
the same number every time, on any machine, in any VM. That is the property wall time can never have,
and it is what makes this the only one of the two worth gating a merge on.

Two details make the number mean something:

* **the count is the difference between running N and 2N iterations.** Process start, runtime init, the
  benchmark's `setup` and its allocations, valgrind's own instrumentation — all identical in both runs,
  all cancel exactly. What is left is N iterations of the loop body and nothing else
* **the counting build drops `-microarch:native`.** Every other recipe here keeps it; this one must not,
  or the count describes the machine instead of the code

`bench/instructions.json` is meant to be committed, unlike the timing baseline — but only holds across
the same Odin version and the same libc, so regenerate it when either moves. The check warns when the
recorded compiler version differs from the current one.

What it cannot see: instructions are not time. A change that halves the instruction count while
destroying cache locality reads here as an improvement. Use this for "did the work change" and
`just bench_cmp` for "did the time change".

`perf stat -e instructions:u` is the obvious alternative and fails where it is most wanted — GitHub's
hosted runners expose no PMU to the guest, so hardware events come back unsupported. callgrind needs no
PMU.
