# Benchmark recipes, pulled in by the project justfile's `import? 'bench/bench.just'`.
#
# The `import?` is optional: with this directory absent the line is a no-op and `just --list` shows no
# benchmark recipes at all. That is what makes `odin-skel add bench` a pure file copy - there is no
# justfile to patch, no marker block to splice, and nothing to make idempotent. Removing the feature is
# `rm -rf bench/`.
#
# An imported justfile shares one namespace with its importer, so `linker` and the `target_path`
# function come from the project justfile and are not redefined here. `bench_name` is local to the
# feature and lives here, so an executable project that never adds benchmarks carries no trace of it.

bench_name := "bench.exe"

# `-o:speed -microarch:native` because a benchmark exists to measure what the optimizer produces, and a
# debug build measures the optimizer being switched off. `-microarch:native` for the same reason the
# release recipes carry it: the number you want is the one this machine can reach. It does mean a
# result is not comparable against a machine with a different instruction set, which is why the JSON
# report records the architecture and the diff warns when they disagree.
#
# Note the `--`: everything after it goes to the benchmark binary rather than to odin, so
# `just bench sum --samples=200` filters and configures the run. Compiler flags therefore cannot ride
# along on this recipe - use `just bench_build -lto:thin` and then `just rerun_bench`.
#
# `-keep-executable` so `rerun_bench` can skip the recompile. Odin has no build cache, so without it
# every run pays a full rebuild before it measures anything.
# ---
# run the benchmarks, optimized.  just bench [NAME] [--samples=N ...]
bench *args: mktarget_dirs
	odin run bench -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("release", bench_name) }} -- {{args}}

# build the benchmarks without running them
bench_build *args: mktarget_dirs
	odin build bench -o:speed -microarch:native -linker:{{linker}} -out:{{ target_path("release", bench_name) }} {{args}}

# re-run the last built benchmark binary WITHOUT recompiling. Requires a prior `bench`/`bench_build`.
rerun_bench *args:
	{{ target_path("release", bench_name) }} {{args}}

# The root `lint` recipe is `odin check .`, which covers only the root package - bench/ is its own
# package and would drift unchecked without this. Same flags, no `-no-entry-point`: this package has a
# `main` and is meant to.
# ---
# type check and vet the benchmarks
bench_lint *args:
	odin check bench -vet -vet-cast -strict-style -vet-tabs {{args}}

# A baseline is a measurement of one machine on one afternoon, so it lives in target/ and is not
# committed: a baseline recorded on CI and compared against on a laptop is two machines being diffed.
# Record one before you start optimizing, then `just bench_cmp` as you go.
# ---
# record the current numbers as the baseline to compare against
bench_save *args: mktarget_dirs
	odin run bench -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("release", bench_name) }} -- --json={{ target_path("release", "bench-baseline.json") }} {{args}}

# Read the caveat in the harness's `compare` doc comment before wiring this into anything that gates a
# merge: back-to-back runs of identical code drift by several percent on a machine that is doing
# anything else, and the test cannot tell that from a real regression.
# ---
# compare the current numbers against the saved baseline
bench_cmp *args: mktarget_dirs
	odin run bench -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("release", bench_name) }} -- --baseline={{ target_path("release", "bench-baseline.json") }} --json={{ target_path("release", "bench-latest.json") }} {{args}}


# Instruction counts, not wall time. Requires valgrind (Linux/macOS; `apt install valgrind`).
# ---
# count instructions per iteration and record bench/instructions.json
bench_count iters="200": (_bench_count "write" iters)

# compare instruction counts against the recorded bench/instructions.json
bench_count_check iters="200": (_bench_count "check" iters)

# Why this exists next to `bench_cmp`, which already answers "did it get slower":
#
# Wall time on a machine that is doing anything else drifts by 5-10% between runs, and no statistic can
# separate that from a real regression - the machine really did change. Instruction counts do not drift
# at all. callgrind counts by *simulating* every instruction rather than sampling a hardware counter, so
# the same binary on the same inputs yields the same number every time, on any machine, in any VM. That
# makes it the only one of the two that can gate a merge without becoming a flake people re-trigger.
#
# It is not a replacement. Instructions are not time: a change that halves the instruction count while
# destroying cache locality reads here as an improvement. Use this to answer "did the work change" and
# `just bench_cmp` to answer "did the time change".
#
# perf is the obvious alternative and does not work where it is most wanted: hardware PMU events are
# not exposed to guests on GitHub-hosted runners, so `perf stat -e instructions:u` reports the event as
# unsupported there. callgrind needs no PMU.
#
# Two builds' worth of notes on getting a comparable number:
#
#   * deliberately NOT `-microarch:native`, unlike every other recipe here. The count has to describe
#     the code and not the machine, and native codegen makes it machine-specific - the one property
#     this whole recipe exists to avoid.
#   * deliberately no `-linker:`. Linker choice changes startup code, which the subtraction below
#     removes anyway, so pinning it would only add a way for two runs to differ.
#
# The measurement is the difference between running N and 2N iterations. Everything that is not the
# loop body - process start, runtime init, the benchmark's `setup` and its allocations, valgrind's own
# instrumentation - is identical in both and cancels exactly. See the harness's `--fixed-iters`.
[script]
_bench_count mode iters: mktarget_dirs
	import json, os, re, shutil, subprocess, sys

	ITERS = int(r"{{iters}}")
	BASELINE = os.path.join("bench", "instructions.json")
	BINARY = os.path.join("target", "release", "bench-count.exe")
	OUT_DIR = os.path.join("target", "release")

	if shutil.which("valgrind") is None:
		sys.exit("valgrind not found - `apt install valgrind` (Linux) or `brew install valgrind` (macOS)")

	# flush=True throughout: python fully buffers stdout when it is a pipe, and these lines are the only
	# indication of progress during a run that simulates every instruction it executes.
	print("building " + BINARY, flush=True)
	build = subprocess.run(["odin", "build", "bench", "-o:speed", "-out:" + BINARY])
	if build.returncode != 0:
		sys.exit(build.returncode)

	names = subprocess.run([BINARY, "--list"], capture_output=True, text=True, check=True).stdout.split()
	if not names:
		sys.exit("no benchmarks registered")

	def instructions(name, n):
		out_file = os.path.join(OUT_DIR, "callgrind.out")
		if os.path.exists(out_file):
			os.remove(out_file)
		subprocess.run(
			[
				"valgrind", "--tool=callgrind", "--callgrind-out-file=" + out_file,
				# `--exact`: the filter is otherwise a substring, so counting `bench.parse` would also
				# run `bench.parse_json` and record the sum of the two as one benchmark's cost.
				BINARY, name, "--exact", "--fixed-iters=" + str(n),
			],
			check=True,
			stdout=subprocess.DEVNULL,
			stderr=subprocess.DEVNULL,
		)
		with open(out_file, encoding="utf-8", errors="replace") as f:
			text = f.read()
		# callgrind writes one `summary:` line holding the whole-run event totals, first column Ir
		# (instructions read). `totals:` is the same shape and is what some versions emit instead.
		match = re.search(r"^(?:summary|totals):\s+(\d+)", text, re.MULTILINE)
		if match is None:
			sys.exit("no summary line in " + out_file + " - callgrind output format changed?")
		return int(match.group(1))

	odin_version = subprocess.run(["odin", "version"], capture_output=True, text=True).stdout.strip()

	results = {}
	for name in names:
		low = instructions(name, ITERS)
		high = instructions(name, 2 * ITERS)
		per_iter = (high - low) / ITERS
		results[name] = per_iter
		print("%-24s %10.1f instructions/iter" % (name, per_iter), flush=True)

	report = {"version": 1, "iters": ITERS, "odin": odin_version, "instructions_per_iter": results}

	mode = r"{{mode}}"
	if mode == "write":
		os.makedirs("bench", exist_ok=True)
		with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
			json.dump(report, f, indent=2, sort_keys=True)
			f.write("\n")
		print("wrote " + BASELINE, flush=True)
		print("Commit it. Unlike a timing baseline this one is reproducible - but only on the same", flush=True)
		print("Odin version and the same libc, so regenerate it when either moves.", flush=True)
		sys.exit(0)

	if mode != "check":
		sys.exit("unknown mode: " + mode)

	try:
		with open(BASELINE, encoding="utf-8") as f:
			base = json.load(f)
	except FileNotFoundError:
		sys.exit("missing " + BASELINE + " - run `just bench_count` first")

	if base.get("odin") != odin_version:
		print("", flush=True)
		print("warning: baseline recorded on Odin %r, this is %r." % (base.get("odin"), odin_version), flush=True)
		print("Codegen changes between compiler versions move these counts; a difference below may be", flush=True)
		print("the compiler rather than your code.", flush=True)

	# One percent. The counts themselves are exact, so the tolerance is not for measurement noise -
	# there is none. It is for the inlining decisions that shift when unrelated code changes size.
	THRESHOLD = 1.0
	old = base.get("instructions_per_iter", {})
	problems = []
	print("", flush=True)
	print("%-24s %14s %14s %9s" % ("name", "baseline", "current", "delta"), flush=True)
	for name in sorted(set(results) | set(old)):
		if name not in old:
			print("%-24s %14s %14.1f  new" % (name, "-", results[name]), flush=True)
			continue
		if name not in results:
			print("%-24s %14.1f %14s  gone" % (name, old[name], "-"), flush=True)
			continue
		before, after = old[name], results[name]
		pct = (after - before) / before * 100 if before else 0.0
		verdict = ""
		if abs(pct) >= THRESHOLD:
			verdict = "REGRESS" if after > before else "improve"
			if after > before:
				problems.append(name)
		print("%-24s %14.1f %14.1f %+8.2f%%  %s" % (name, before, after, pct, verdict), flush=True)

	if problems:
		sys.exit("instruction counts regressed: " + ", ".join(problems))
	print("", flush=True)
	print("instruction counts unchanged within " + str(THRESHOLD) + "%", flush=True)
