/*
SKELETON: your benchmarks go here. Replace these with something real; keep `CASES`.

This is `package bench`, not `package main`. Odin only requires the entry package to *contain* a `main`
procedure - it does not require the package to be called `main` - and the distinction is load-bearing
here. An executable project's root is `package main`, and two packages in one build may not share a
name: naming this one `main` too fails the build with

	Error: Duplicate declaration of 'package main'
	A package name must be unique

before a single benchmark runs. Calling it `bench` means the same directory works for a library and an
executable alike.

To benchmark your own code, import the project root. This is a package build, not `-file` mode, so the
relative import resolves against this directory - one level up, whatever the project shape:

	import app ".."          // executable: the root is `package main`
	import lib ".."          // library: the root is your package

The alias is not optional. Odin derives an import's name from its directory, and a repository directory
is often not a valid identifier - from a checkout named `odin-toml`, a bare `import ".."` fails with
`Import name 'odin-toml' is not a valid identifier`.

The rules that make a microbenchmark mean anything, in the order people get them wrong:

 1. Pass inputs through `opaque()`. Otherwise the compiler folds a literal argument at compile time and
    you time an empty loop.
 2. Feed every result to `keep()`. Otherwise the compiler deletes the call whose result nothing reads
    and you time an empty loop.
 3. Loop exactly `b.n` times. The harness picks `b.n` so that one sample lands near its target
    duration; looping a different number of times reports a per-iteration cost for the wrong divisor.
 4. Do allocation and input generation in `setup`, not in the body - unless allocation is the thing
    being measured.
 5. Make each iteration depend on something the compiler cannot see. Rules 1 and 2 stop constant
    folding and dead code; neither stops *hoisting*. An iteration whose inputs never change is
    loop-invariant, and the compiler may run it once and store the answer `b.n` times.

A benchmark reporting an implausible 0.0ns has lost rule 1 or 2. One reporting an implausible
*throughput* has usually lost rule 5. `bench.empty_loop` below is the floor to compare against: nothing
real is faster than the loop itself. `odin build bench -o:speed -build-mode:asm` settles any argument.
*/
package bench

// The registry. `just bench NAME` filters on a substring of these names, so a dotted prefix keeps
// whole groups selectable with one word.
CASES := []Case {
	{name = "bench.empty_loop", bench = bench_empty_loop},
	{name = "bench.mul_chain", bench = bench_mul_chain},
	{name = "bench.sum_slice", bench = bench_sum_slice, setup = setup_inputs, teardown = teardown_inputs},
}

// The harness's own floor: an iteration that does nothing except what rules 1 and 2 cost. Any
// benchmark reporting a figure below this one is measuring an optimizer, not a procedure.
bench_empty_loop :: proc(b: ^B) {
	x := opaque(1)
	for _ in 0 ..< b.n {
		keep(x)
	}
}

/*
Rule 5, and what it costs to obey.

The barrier has to be *inside* the loop, so each iteration's input is a value the compiler must
re-read. A volatile round trip is a store and a load - more work than the multiply being measured - so
this benchmark is mostly measuring the harness, and it is here to say so. A procedure that compiles to
one or two instructions cannot be timed in isolation by any harness, in any language. Time it inside
the loop that really calls it, the way `bench.sum_slice` does, or not at all.

Feeding the accumulator back in makes the chain sequential, which reports *latency* - how long one
operation takes before the next can start - rather than throughput. That does not save you on its own:
an `acc += i` chain with no inner barrier gets replaced outright by the closed form `n * (n - 1) / 2`,
and the harness then calibrates towards a quadrillion iterations and flags OPTIMIZED AWAY.
*/
bench_mul_chain :: proc(b: ^B) {
	acc := u64(1)
	for i in 0 ..< b.n {
		acc = opaque(acc) * 6364136223846793005 + u64(i)
	}
	keep(acc)
}

// A benchmark with real inputs, showing the setup/teardown pair and the `bytes` field. Setting
// `b.bytes` to the bytes touched per iteration turns on the MB/s column; leave it zero when throughput
// is not the unit anyone thinks in.
Inputs :: struct {
	values: []u64,
}

setup_inputs :: proc(b: ^B) {
	inputs := new(Inputs)
	inputs.values = make([]u64, 1024)
	for i in 0 ..< len(inputs.values) {
		inputs.values[i] = u64(i) * 7
	}
	b.data = inputs
	b.bytes = len(inputs.values) * size_of(u64)
}

teardown_inputs :: proc(b: ^B) {
	inputs := (^Inputs)(b.data)
	delete(inputs.values)
	free(inputs)
}

bench_sum_slice :: proc(b: ^B) {
	inputs := (^Inputs)(b.data)
	for _ in 0 ..< b.n {
		// The slice goes through `opaque`, not just the accumulator. Laundering the seed alone is not
		// enough: the sum of a slice the compiler can see is never written is loop-invariant no matter
		// what it is added to. That draft reported 0.592ns to sum 1024 elements - 13 TB/s - because the
		// inner loop had been hoisted out and one add left behind. Passing the slice itself through a
		// volatile round trip means the compiler no longer knows it is the same slice each iteration,
		// so the loads have to happen. One store and one load per *outer* iteration, which 1024 adds
		// amortise into nothing.
		values := opaque(inputs.values)
		total := u64(0)
		for v in values {
			total += v
		}
		keep(total)
	}
}
