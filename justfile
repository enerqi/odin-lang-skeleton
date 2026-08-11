# `cmd.exe` starts in ~9ms and always available. just launches a shell per recipe line.
#  - alternatives: `nu -c` ~41ms, `powershell -NoLogo -NoProfile -Command` ~143ms
#  - cost: it is a poor language for a multi-line recipe, hence uv -> python preferred for more complex tasks
set windows-shell := ["cmd.exe", "/c"]
set shell := ["bash", "-c"]
set unstable  # [script] feature - https://github.com/casey/just/issues/1479
set lazy

# `python` alone is not a reliable cross-platform lookup (cf. python/python3/python3.x)
# uv resolves/downloads on every platform and --no-project means no looking for pyproject.toml / local .venv
# just recipes opt in with the bare `[script]` attribute (no interpreter argument)
set script-interpreter := ["uv", "run", "--no-project", "-p", "3.14", "python"]

# Newest just feature used below is user-defined functions (1.49). Keep the README and `odin-skel doctor` in step.
set minimum-version := "1.49.0"

# >>> exe-only
main_name := "main.exe"
# <<< exe-only
test_main_name := "test-main.exe"

# `join`, not the `/` operator: `/` always emits a forward slash, and cmd.exe rejects a forward-slash
# path in *command* position ("'target' is not recognized") even quoted.
target_path(dir, name) := join("target", dir, name)

# Which linker Odin hands the object files to. `-linker:` takes exactly four values: `default` (Odin
# picks - MSVC `link.exe` on Windows), `lld`, `radlink` (Windows only, bundled with Odin, hence the
# Windows default here) and `mold` (Linux only, not bundled). Odin has no build cache and relinks on
# every build, so this is a per-iteration cost. `odin-skel new --linker=VALUE` rewrites the default below.
#
# Override for one command without editing this file - for `-lto`, which on Windows *requires* lld, or
# for a machine that has mold when the project default does not assume it:
#
# >>> exe-only
#     ODIN_LINKER=lld just run_release -lto:thin
# <<< exe-only
# >>> lib-only
#     ODIN_LINKER=lld just test -lto:thin
# <<< lib-only
#
# An env var rather than a recipe argument because `odin` errors on a repeated flag ("Previous flag set:
# 'linker'"), so a `-linker:` passed through a recipe's `*args` would collide with the one added below.
# Which value to pick, and the lld-on-macOS and incremental-linking caveats: README, "Choosing a linker".
linker := env_var_or_default("ODIN_LINKER", if os() == "windows" { "radlink" } else { "default" })

# Optional features add their recipes by shipping a `.just` file, not by editing this one.
# Lets `odin-skel add bench` be a plain and `rm -rf bench/` be the uninstall.
# An imported file shares one namespace with this one, so `linker`, `target_path` and `mktarget_dirs`
# below are all visible to it. Recipe names must not collide; the feature prefixes all of its own.
import? 'bench/bench.just'

# odinfmt every odin file under this directory or subdirectories
format:
	odinfmt -w .


# `-vet-tabs` is the only compiler-side enforcement of .editorconfig's `indent_style = tab`; it is not
# implied by `-strict-style`, so without it a space-indented file lints clean. Nothing in the Odin
# toolchain checks line endings - those are held in place by .gitattributes and odinfmt.json instead.
# Accepts extra args like `-show-timings` as needed.
# ---
# lint checks for style and potential bugs. No code generation
lint *args:
	odin check . -vet -vet-cast -strict-style -vet-tabs -no-entry-point {{args}}


# Every recipe that produces a binary depends on this. Odin does not create the output directory
# One line/call keeps the cost to one shell command
# ---
# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
	mkdir -p target/debug target/fast_debug target/release_debug target/release target/release_nochecks

# `if not exist` rather than swallowing md's "already exists" with `2>nul`, so a genuine failure still
# sets a non-zero exit. The loop var is a single `%d`, NOT the `%%d` that a .bat file would use for escaping
# ---
# ensure the build artifacts top level directory exists
[windows]
@mktarget_dirs:
	for %d in (debug fast_debug release_debug release release_nochecks) do @if not exist target\%d md target\%d || exit /b 1

# >>> exe-only
# `-debug` implies `-o:none`, so this is the fastest to compile and the friendliest to step through.
# (-keep-executable so `rerun_debug` can skip recompiling)
# ---
# run with debug build
run_debug *args: mktarget_dirs
	odin run . -debug -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("debug", main_name) }} {{args}}

alias run := run_debug

# `-o:minimal` is one rung above the `-debug` default of `-o:none`: still quick to compile and mostly
# faithful to step through, but noticeably faster at runtime.
# (-keep-executable so `rerun_fast_debug` can skip recompiling)
# ---
# run with debug info and light optimizations
run_fast_debug *args: mktarget_dirs
	odin run . -debug -o:minimal -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("fast_debug", main_name) }} {{args}}

# Release codegen with debug info retained: for profiling and for chasing bugs that only appear under optimization
# Slowest to compile, and the debugger will jump around inlined/reordered code.
# (-keep-executable so `rerun_release_debug` can skip recompiling)
# ---
# run with full optimizations AND debug info
run_release_debug *args: mktarget_dirs
	odin run . -debug -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("release_debug", main_name) }} {{args}}

# run with optimizations (-keep-executable so `rerun_release` can skip recompiling)
run_release *args: mktarget_dirs
	odin run . -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("release", main_name) }} {{args}}

# `run_release` plus every runtime safety check compiled out: `-no-bounds-check` (slice/array indexing),
# `-disable-assert` (the built-in `assert`) and `-no-type-assert` (union/any type assertions). Those
# checks are what turn a memory-corrupting bug into a clean panic, so a fault here is undefined
# behaviour rather than a readable message - benchmark against `run_release` before adopting it, and
# keep a checked build in your test matrix. `-o:aggressive` exists too but Odin flags it as risky.
# (-keep-executable so `rerun_release_nochecks` can skip recompiling)
# ---
# run with optimizations and ALL runtime safety checks removed
run_release_nochecks *args: mktarget_dirs
	odin run . -o:speed -no-bounds-check -disable-assert -no-type-assert -microarch:native -keep-executable -linker:{{linker}} -out:{{ target_path("release_nochecks", main_name) }} {{args}}
# <<< exe-only

# Outside the kind markers on purpose: `test_sanitize` below ships in every project, so these notes must
# not be stripped along with the exe-only `sanitize`.
#
# KIND is `address` (default, ASan), `memory` or `thread`; only `address` is widely supported. ON WINDOWS
# `address` CATCHES STACK ERRORS BUT NOT HEAP ERRORS - Odin allocates through `HeapAlloc`, which ASan does
# not intercept, so a clean run there says nothing about your heap. (Probed a 16-byte allocation at +16,
# +24, +32, +64, +256: Linux reports `heap-buffer-overflow` from +24 on, Windows at none. +16 is in bounds
# either way - the allocator hands back more than asked for.) The rest, and the Linux
# `libclang_rt.asan.a` install: README, "Tasks".
#
# Both recipes deliberately omit `-linker:{{linker}}` - do not "fix" the inconsistency. A sanitizer has to
# interpose on the runtime and not every linker cooperates: `radlink` (this file's Windows default, and
# bundled with Odin, so it is what you get by accident) links an ASan binary that dies on startup with a
# bare `0xc000001d` illegal-instruction exception and no usable stack, while `-linker:default` runs it.
# Link speed is worth nothing on a diagnostic run anyway.

# >>> exe-only
# Usage:  just sanitize   or   just sanitize thread -- --my-arg
# ---
# run a debug build under a sanitizer (address | memory | thread)
sanitize kind="address" *args: mktarget_dirs
	odin run . -debug -sanitize:{{kind}} -out:{{ target_path("debug", f"sanitize-{{kind}}-{{main_name}}") }} {{args}}
# <<< exe-only
# >>> lib-only
# There is no binary of this project to run, so the inner loop is a type check plus the tests, and the
# examples are what prove the package is usable from outside it.

# What `just run` is to a program: the fast "does it still compile" loop. Deliberately without the vet and
# style flags `lint` carries - those are worth a separate, slower pass rather than noise between an edit
# and knowing whether it type checks. `odin check .` covers the root package, which for a single-package
# library is all of it; once there are subpackages, an aggregator example sweeps them (see the README).
# ---
# type check the library
check *args:
	odin check . -no-entry-point {{args}}

# `-file` is not optional here: without it odin reads examples/ as one package and the several `main`
# procedures in it collide. It is also what makes the examples' `".."` import resolve to this directory.
# Usage:  just example basic
# ---
# build and run one example from examples/
example name *args: mktarget_dirs
	odin run examples/{{name}}.odin -file -debug -microarch:native -linker:{{linker}} -out:{{ target_path("debug", f"example-{{name}}.exe") }} {{args}}

# An example is documentation, and documentation stops being true the moment the API moves under it. This
# is the cheap guard against that. A `[script]` because just has no loop and cmd.exe is a poor place for one.
# ---
# type check every example in examples/
[script]
examples:
	import glob, subprocess, sys

	files = sorted(glob.glob("examples/*.odin"))
	if not files:
		sys.exit("no examples found in examples/")

	for path in files:
		# flush=True because python fully buffers stdout when it is a pipe (CI logs, `just examples > f`),
		# which would land these lines after the compiler's stderr and lose which example broke.
		print("checking " + path, flush=True)
		# `-no-entry-point` so an aggregator example works: a `package all` file of `@(require) import ".."`
		# lines has no `main`, and is how a library with subpackages type checks its whole tree (README).
		# Harmless for the ordinary `package main` examples, not being asked for a binary here either.
		result = subprocess.run(
			["odin", "check", path, "-file", "-no-entry-point", "-vet", "-vet-cast", "-strict-style", "-vet-tabs"]
		)
		if result.returncode != 0:
			sys.exit(result.returncode)
	print("checked " + str(len(files)) + " example(s)")

# Writes to stdout; redirect it to keep a copy. Deliberately NOT `-all-packages`, which documents every
# package the project *uses* - all of `core:` included - rather than this one.
# ---
# print the library's documentation
doc *args:
	odin doc . {{args}}

# <<< lib-only

# See the notes above for platform support, the Windows heap caveat and why no linker is pinned.
# Usage:  just test_sanitize   or   just test_sanitize thread
# ---
# run the tests under a sanitizer (address | memory | thread)
test_sanitize kind="address" *args: mktarget_dirs
	odin test . -debug -file -sanitize:{{kind}} -out:{{ target_path("debug", f"sanitize-{{kind}}-{{test_main_name}}") }} {{args}}

# >>> exe-only
# Odin has no build cache, so a plain `run` always rebuilds. Requires a prior `run_debug`/`run` build.
# ---
# re-run the last debug binary WITHOUT recompiling
rerun_debug *args:
	{{ target_path("debug", main_name) }} {{args}}

alias rerun := rerun_debug

# re-run the last fast_debug binary without recompiling. Requires a prior `run_fast_debug` build.
rerun_fast_debug *args:
	{{ target_path("fast_debug", main_name) }} {{args}}

# re-run the last release_debug binary without recompiling. Requires a prior `run_release_debug` build.
rerun_release_debug *args:
	{{ target_path("release_debug", main_name) }} {{args}}

# re-run the last release binary without recompiling. Requires a prior `run_release` build.
rerun_release *args:
	{{ target_path("release", main_name) }} {{args}}

# re-run the last nochecks binary without recompiling. Requires a prior `run_release_nochecks` build.
rerun_release_nochecks *args:
	{{ target_path("release_nochecks", main_name) }} {{args}}

# hyperfine (https://github.com/sharkdp/hyperfine) times whole *processes*, and is installed separately -
# `just doctor` reports whether it is there. Over `rerun_release`'s binary rather than `just run_release`:
# Odin has no build cache, so timing the recipe would mostly time the compiler - build first. `-N` skips
# the shell hyperfine would otherwise spawn per run, at the cost that the command is split on whitespace
# rather than parsed: no pipes, redirects or quoted arguments containing spaces. Process startup (~31ms
# here) swamps anything smaller - for per-procedure numbers add the harness, `odin-skel add bench`.
# See the README, "Timing a recipe" and "Benchmarking".
#
# Usage:  just time_release            time the release binary
#         just time_release --flag=x   ... passing arguments to the program
# ---
# time the release binary end to end with hyperfine (needs a prior run_release/build)
time_release *args:
	hyperfine -N --warmup 3 "{{ target_path("release", main_name) }} {{args}}"

# A/B two build profiles in one run - hyperfine prints the ratio between them, which is the number worth
# knowing about `-no-bounds-check`. Times both binaries, so needs a prior `run_release` AND `run_release_nochecks`.
# ---
# compare the release and nochecks binaries with hyperfine
time_profiles *args:
	hyperfine -N --warmup 3 "{{ target_path("release", main_name) }} {{args}}" "{{ target_path("release_nochecks", main_name) }} {{args}}"
# <<< exe-only

# run all tests
test *args: mktarget_dirs
	odin test . -debug -file -microarch:native -linker:{{linker}} -out:{{ target_path("debug", test_main_name) }} {{args}}

# Filtering is a `core:testing` define, not a compiler flag - there is no `-test-name:`, and a stale
# spelling of one fails with `Unknown flag: 'test-name'` before anything builds. NAME takes a comma-separated
# list and the package prefix is optional, so `pkg.my_test`, `my_test` and `one,two` all work:
#     just test1 my_test
# ---
# run one named test (comma-separated for several)
test1 name *args: mktarget_dirs
	odin test . -debug -file -microarch:native -define:ODIN_TEST_NAMES={{name}} -linker:{{linker}} -out:{{ target_path("debug", test_main_name) }} {{args}}

# simple delete of all debug databases and executables in the target directory
[unix]
clean:
	rm -rf target
	just mktarget_dirs

# simple delete of all debug databases and executables in the target directory
[windows]
clean:
	if exist target rmdir /s /q target
	just mktarget_dirs

# >>> exe-only
# build with some verbose diagnostics
diagnose *args: mktarget_dirs
	odin build . -debug -microarch:native -show-more-timings -show-debug-messages -show-timings -linker:{{linker}} -out:{{ target_path("debug", main_name) }} {{args}}
# <<< exe-only


# Cross platform: Sublime then offers them in every window. The `.sublime-project` file is
# project-local and intentionally NOT installed. Override the destination with the SUBLIME_USER_DIR
# env var if your setup is non-standard.
# ---
# install the editor snippets + build systems into Sublime Text's global `Packages/User` directory
[script]
install-sublime:
	import os, sys, shutil
	home = os.path.expanduser("~")
	override = os.environ.get("SUBLIME_USER_DIR")
	if override:
		candidates = [override]
	elif sys.platform == "win32":
		appdata = os.environ.get("APPDATA", os.path.join(home, "AppData", "Roaming"))
		candidates = [os.path.join(appdata, p, "Packages", "User") for p in ("Sublime Text", "Sublime Text 3")]
	elif sys.platform == "darwin":
		base = os.path.join(home, "Library", "Application Support")
		candidates = [os.path.join(base, p, "Packages", "User") for p in ("Sublime Text", "Sublime Text 3")]
	else:
		base = os.path.join(home, ".config")
		candidates = [os.path.join(base, p, "Packages", "User") for p in ("sublime-text", "sublime-text-3")]

	# prefer a candidate whose Sublime data dir (the `Packages` parent) already exists
	target = next((c for c in candidates if os.path.isdir(os.path.dirname(c))), None)
	if target is None:
		sys.exit(
			"could not find a Sublime Text Packages directory. Set SUBLIME_USER_DIR to your "
			"Packages/User folder and retry. Tried: " + ", ".join(candidates)
		)
	os.makedirs(target, exist_ok=True)
	for name in (
		"Odin-skeleton.sublime-snippet",
		"Just-Odin.sublime-snippet",
		"Just-Odin-lib.sublime-snippet",
		"Odin.sublime-build",
		"OdinJustTarget.sublime-build",
	):
		shutil.copy2(os.path.join(".sublime", name), os.path.join(target, name))
		print("installed " + name)
	print("-> " + target)


# >>> snippet-exclude
# Opening the project in Sublime then exposes project-local build variants (Tools -> Build System) with
# no global install. Seeds one working `just test` build plus commented-out examples to extend. Refuses
# if a build_systems entry already exists. (Excluded from the Just-Odin snippet because it contains
# literal `$file` / `$project_path` which would be parsed as snippet fields; still copied into new
# projects by `just new`.)
# ---
# add a `build_systems` stub to the project's .sublime-project
[script]
sublime-build-init:
	import glob, os, sys
	matches = glob.glob(os.path.join(".sublime", "*.sublime-project"))
	if not matches:
		sys.exit("no .sublime/*.sublime-project file found")
	if len(matches) > 1:
		sys.exit("multiple .sublime-project files found: " + ", ".join(matches))
	path = matches[0]
	with open(path, encoding="utf-8") as f:
		text = f.read()
	if "build_systems" in text:
		sys.exit(path + " already has a build_systems entry - edit it by hand")
	name = os.path.splitext(os.path.basename(path))[0]
	block = (
		'    "build_systems":\n'
		'    [\n'
		'        {\n'
		'            "name": "' + name + ' (just)",\n'
		'            "selector": "source.odin",\n'
		'            "working_dir": "$project_path/..",\n'
		'\n'
		'            // file_regex turns lines of build output into clickable error links. Odin reports\n'
		'            // diagnostics as `path(line:column) message`, so the four regex capture groups below\n'
		'            // map, in order, to (1) file path (2) line (3) column (4) message -- the order Sublime\n'
		'            // expects. A matched line becomes a link that jumps to that file/line/column; F4 and\n'
		'            // Shift+F4 step forward/back through the matches. The doubled backslashes are JSON\n'
		'            // string escaping: `\\\\(` in this file is the regex `\\(` (a literal open paren).\n'
		'            "file_regex": "^(.+)\\\\(([0-9]+):([0-9]+)\\\\) (.+)$",\n'
		'\n'
		'            // `just test` rather than `just run`: it is the one recipe both an executable and a\n'
		'            // library project have, and this is a stub to edit rather than a finished setup.\n'
		'            "shell_cmd": "just test",\n'
		'\n'
		'            // uncomment / extend; each variant appears under Tools -> Build With... Sublime expands\n'
		'            // these build variables in shell_cmd / working_dir (full list:\n'
		'            // https://www.sublimetext.com/docs/build_systems.html#variables):\n'
		'            //   $file            full path of the current file,  e.g. /home/me/proj/src/main.odin\n'
		'            //   $file_path       directory of the current file (its package dir for Odin)\n'
		'            //   $file_base_name  current file name without extension,  e.g. main\n'
		'            //   $folder          first folder open in the side bar (the project root; no project file needed)\n'
		'            //   $project_path    directory containing this .sublime-project file\n'
		'            // "variants":\n'
		'            // [\n'
		'            // (a program has run/run_release; a library has check/example/doc - keep the ones\n'
		'            //  your project actually defines)\n'
		'            //     { "name": "run",                    "shell_cmd": "just run" },\n'
		'            //     { "name": "release",                "shell_cmd": "just run_release" },\n'
		'            //     { "name": "check",                  "shell_cmd": "just check" },\n'
		'            //     { "name": "example basic",          "shell_cmd": "just example basic" },\n'
		'            //     { "name": "doc",                    "shell_cmd": "just doc" },\n'
		'            //     { "name": "lint",                   "shell_cmd": "just lint" },\n'
		'            //     { "name": "current file (run)",     "shell_cmd": "odin run \\"$file\\" -file -debug" },\n'
		'            //     { "name": "current package",        "shell_cmd": "odin build \\"$file_path\\" -debug" },\n'
		'            //     { "name": "current file -> target", "working_dir": "$folder", "shell_cmd": "odin build \\"$file\\" -file -out:target/debug/$file_base_name.exe -debug" },\n'
		'            // ],\n'
		'        },\n'
		'    ],\n'
	)
	idx = text.index("{") + 1
	text = text[:idx] + "\n" + block.rstrip("\n") + text[idx:]
	with open(path, "w", encoding="utf-8", newline="\n") as f:
		f.write(text)
	print("added build_systems stub to " + path)
# <<< snippet-exclude


# Resolves extra collection imports (`import "xyz:pkg"`), needed only for packages outside this project.
# Each argument is `name=path` and the arguments are the whole collection list - a rerun replaces it, and
# every other setting already in ols.json is left alone. No arguments prints what is configured.
#     just ols-config xyz=../xyz-lib abc=/opt/odin/abc
#
# ols resolves a relative path against this project's root, so a collection kept as a sibling checkout
# gives an ols.json identical on every machine - drop the `ols.json` line from .gitignore and commit it.
# An absolute path is machine-specific, which is why the file is ignored by default. A leading `~` expands
# on Linux and macOS only; on Windows write the path out in full.
#
# A path containing a space cannot be passed here: just joins a variadic parameter's arguments with spaces
# before the body sees them, so no quoting survives. Edit ols.json by hand for that - the recipe reads the
# file back, so it is not an either/or.
# ---
# SKELETON: (re)generate ols.json so the Odin language server resolves extra collections
[script]
ols-config *pairs:
	import json, os, re, sys

	USAGE = "usage: just ols-config name=path [name=path ...]   e.g. just ols-config xyz=../xyz-lib"

	# str.split, not shlex.split: shlex's default POSIX mode treats a backslash as an escape and would eat
	# every separator in a Windows path (C:\odin\libs -> C:odinlibs). The space before the closing quote is
	# load-bearing - a path ending in a backslash would otherwise escape the quote and leave the string
	# unterminated. str.split() discards it again as trailing space.
	args = r'''{{pairs}} '''.split()

	# Read before write. ols.json also holds editor settings (enable_document_symbols, checker_path,
	# odin_command, ...), and only the collection list is ours to rewrite.
	config = {}
	if os.path.exists("ols.json"):
		with open("ols.json", encoding="utf-8") as f:
			try:
				config = json.load(f)
			except ValueError as err:
				sys.exit("ols.json is not valid JSON - fix or delete it first: " + str(err))
		if not isinstance(config, dict):
			sys.exit("ols.json does not hold a JSON object - fix or delete it first")

	if not args:
		configured = config.get("collections") or []
		for entry in configured:
			print(entry.get("name", "?") + " -> " + entry.get("path", "?"))
		if not configured:
			print("no collections configured")
		print(USAGE)
		sys.exit(0)

	collections = []
	seen = set()
	for arg in args:
		# partition, not split: only the first `=` separates, so a path may contain one.
		name, sep, path = arg.partition("=")
		if not sep or not name or not path:
			sys.exit("expected name=path, got " + repr(arg) + "\n" + USAGE)
		# The name is what precedes the colon in `import "xyz:pkg"`, so odin's own rule applies: it has
		# to be an identifier. Without this a typo like `b/c=d` writes a collection nothing can import.
		if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
			sys.exit("collection name " + repr(name) + " is not an identifier")
		if name in seen:
			sys.exit("collection " + repr(name) + " given twice")
		seen.add(name)
		collections.append({"name": name, "path": path})

	# Second pass so a later bad argument fails before any warning about an earlier good one.
	for entry in collections:
		if not os.path.isdir(entry["path"]):
			# Not fatal - the collection may be cloned later, and ols reads this file on startup.
			print("warning: " + entry["path"] + " is not a directory (yet)", file=sys.stderr)

	config.setdefault(
		"$schema", "https://raw.githubusercontent.com/DanielGavin/ols/master/misc/ols.schema.json"
	)
	config["collections"] = collections
	with open("ols.json", "w", encoding="utf-8", newline="\n") as f:
		f.write(json.dumps(config, indent=4) + "\n")
	for entry in collections:
		print("wrote ols.json -> " + entry["name"] + " collection at " + entry["path"])


# >>> skeleton-only
# Recipes below operate on the skeleton repo itself (scaffold a new project, build the odin-skel
# tool, regenerate the editor snippets). They are stripped from the Just-Odin.sublime-snippet because
# they are meaningless once the justfile is dropped into a real project. Leave the
# `# >>> / # <<< skeleton-only` markers in place.

# Declared here rather than beside main_name / test_main_name at the top of the file so they are
# stripped along with the rest of this block - a scaffolded project has no tools/skel to build.
skel_name := "odin-skel.exe"
skel_test_name := "test-odin-skel.exe"

# `odin check .` only covers the root package, so tools/skel needs its own lint pass or it drifts
# unchecked. Same flags as the root `lint` recipe.
# ---
# lint the odin-skel tool source
lint_skel *args:
	odin check tools/skel -vet -vet-cast -strict-style -vet-tabs {{args}}

# run the odin-skel tool's tests
test_skel *args: mktarget_dirs
	odin test tools/skel -debug -linker:{{linker}} -out:{{ target_path("debug", skel_test_name) }} {{args}}

# `mylib/` is the template `odin-skel new --lib` scaffolds from, and it is a live package here rather
# than inert text - see tools/DESIGN.md, Decision 3's amendment. `odin check .` covers only the root
# package, so it needs its own pass or it drifts unchecked exactly like tools/skel would.
#
# The example is checked with `-file`, which is how a scaffolded project builds it: that is what proves
# its `".."` import depth is right, and the depth is the one thing about this layout that is easy to
# get wrong.
# ---
# lint the lib template package and its example
lint_lib_template *args:
	odin check mylib -vet -vet-cast -strict-style -vet-tabs -no-entry-point {{args}}
	odin check mylib/examples/basic.odin -file -vet -vet-cast -strict-style -vet-tabs {{args}}

# Runs the example as well as the tests. `odin check` never links, and the example's whole job is to
# prove that the import path a consumer will use resolves, links and runs.
# ---
# test the lib template package and run its example
test_lib_template *args: mktarget_dirs
	odin test mylib -debug -linker:{{linker}} -out:{{ target_path("debug", "test-mylib.exe") }} {{args}}
	odin run mylib/examples/basic.odin -file -linker:{{linker}} -out:{{ target_path("debug", "example-basic.exe") }} {{args}}

# The version is stamped in at build time; an unstamped build reports "dev". Release builds pass
# `-define:SKEL_VERSION=x.y.z` (see tools/DESIGN.md).
# ---
# build the odin-skel tool into target/debug/
build_skel *args: mktarget_dirs
	odin build tools/skel -debug -linker:{{linker}} -out:{{ target_path("debug", skel_name) }} {{args}}

# What CI publishes: optimized, no debug info, and stamped with the tag it was built from.
# Deliberately NOT -microarch:native - a published binary has to run on any machine of that
# architecture, not just the builder. Also deliberately NOT `-linker:{{linker}}`: link speed is
# worth nothing on a once-per-tag build, and the one artifact that cannot be quietly rebuilt if a
# linker turns out to have a quirk is the one users download.
#   just build_skel_release -define:SKEL_VERSION=1.2.3
# ---
# build an optimized odin-skel into target/release/
build_skel_release *args: mktarget_dirs
	odin build tools/skel -o:speed -out:{{ target_path("release", skel_name) }} {{args}}

# Thin wrapper: the scaffolding logic lives in the odin-skel binary and nowhere else, so the two
# cannot drift (see tools/DESIGN.md, Decision 2). Build the binary first with `just build_skel`.
# Usage:  just new ../my-new-project   or   just new ../dir projname
#         just new ../dir projname --linker=mold
# `flags` is a passthrough, so every odin-skel option works here without this recipe growing a
# parameter per option.
# ---
# copy this skeleton into a new or empty directory
[script]
new dest name="" *flags:
	import os, subprocess, sys

	binary = os.path.join("target", "debug", "{{skel_name}}")
	if not os.path.isfile(binary):
		sys.exit("missing " + binary + " - run `just build_skel` first")

	argv = [binary, "new", r"{{dest}}"]
	name = r"{{name}}"
	if name:
		argv.append(name)
	argv.extend(r"""{{flags}}""".split())
	raise SystemExit(subprocess.run(argv).returncode)

# The same thin wrapper for the other half of the tool. `dest` defaults to "." so that
# `just add bench` works on the project you are standing in, which is the usual case; the skeleton
# repo itself already carries bench/, so here it is mostly for testing the path a user takes.
# Usage:  just add bench   or   just add bench ../my-game
# ---
# add an optional feature (bench) to a project
[script]
add feature dest=".":
	import os, subprocess, sys

	binary = os.path.join("target", "debug", "{{skel_name}}")
	if not os.path.isfile(binary):
		sys.exit("missing " + binary + " - run `just build_skel` first")

	raise SystemExit(subprocess.run([binary, "add", r"{{feature}}", r"{{dest}}"]).returncode)


# Moves everything under `## [Unreleased]` into a new `## [VERSION] - <today>` heading, leaves a
# fresh empty Unreleased above it, and fixes the link definitions at the bottom of the file.
#
# Edits CHANGELOG.md and stops. It does not commit, stage or tag: an automated tag is fine until the
# day it fires on the wrong branch, and reviewing the diff before releasing is the point.
#
#   just release 0.1.1      # then: review, commit, tag, push
# ---
# promote CHANGELOG.md's Unreleased section to a version heading
[script]
release version:
	import datetime, re, sys

	version = r"{{version}}".lstrip("v")
	if not re.match(r"^\d+\.\d+\.\d+", version):
		sys.exit("expected a version like 1.2.3, got: " + version)

	path = "CHANGELOG.md"
	with open(path, encoding="utf-8") as f:
		lines = f.read().splitlines()

	heading = re.compile(r"^##\s+\[?([^\]\s]+)\]?")

	unreleased = None
	for i, line in enumerate(lines):
		m = heading.match(line)
		if not m:
			continue
		if m.group(1) == "Unreleased":
			unreleased = i
		elif m.group(1).lstrip("v") == version:
			sys.exit("CHANGELOG.md already has a '## " + version + "' section")
	if unreleased is None:
		sys.exit("no '## [Unreleased]' heading in CHANGELOG.md")

	# Everything from Unreleased up to the next heading is what gets promoted.
	end = len(lines)
	for i in range(unreleased + 1, len(lines)):
		if heading.match(lines[i]):
			end = i
			break
	if not any(l.strip() for l in lines[unreleased + 1:end]):
		sys.exit("the Unreleased section is empty - nothing to release")

	today = datetime.date.today().isoformat()
	lines[unreleased + 1:unreleased + 1] = ["", "## [" + version + "] - " + today]

	# Rewrite the link definitions. The repository URL is taken from the existing Unreleased link
	# rather than hard-coded, so a repository rename does not silently produce dead links.
	for i, line in enumerate(lines):
		m = re.match(r"^\[Unreleased\]:\s*(https?://\S+?)/compare/", line)
		if not m:
			continue
		repo = m.group(1)
		lines[i] = "[Unreleased]: " + repo + "/compare/" + version + "...HEAD"
		lines.insert(i + 1, "[" + version + "]: " + repo + "/releases/tag/" + version)
		break
	else:
		print("warning: no '[Unreleased]: .../compare/...' link line found; add the links by hand")

	with open(path, "w", encoding="utf-8", newline="\n") as f:
		f.write("\n".join(lines).rstrip("\n") + "\n")

	print("CHANGELOG.md: Unreleased -> " + version + " (" + today + ")")
	print("next: review the diff, commit, then `git tag -a " + version + " -m " + version + "` and push")


# Prints the CHANGELOG.md section for VERSION, which the release workflow prepends to the release's
# auto-generated notes. Exits non-zero when there is no matching section: GitHub's generator lists
# merged pull requests only, so for a repo that pushes straight to master a missing section means a
# release with essentially no notes, which is worth failing over rather than shipping.
#   just changelog_section 0.1.0
# ---
# print the CHANGELOG.md section for a version
[script]
changelog_section version:
	import re, sys

	# The changelog contains em dashes and similar; without this the Windows console encoding
	# mangles them, and the release notes would carry the damage.
	sys.stdout.reconfigure(encoding="utf-8")

	want = r"{{version}}".lstrip("v")
	with open("CHANGELOG.md", encoding="utf-8") as f:
		lines = f.read().splitlines()

	# Headings look like `## [0.1.0] - 2026-08-06`; the brackets and date are both optional so a
	# hand-written `## 0.1.0` works too.
	heading = re.compile(r"^##\s+\[?([^\]\s]+)\]?")

	start = None
	for i, line in enumerate(lines):
		m = heading.match(line)
		if not m:
			continue
		if start is None and m.group(1).lstrip("v") == want:
			start = i + 1
		elif start is not None:
			lines = lines[start:i]
			break
	else:
		if start is None:
			sys.exit("no '## " + want + "' section in CHANGELOG.md - add one before tagging")
		lines = lines[start:]

	# The last section in the file runs to EOF, which sweeps up the trailing link definitions
	# (`[0.1.0]: https://...`). They belong to the document, not to the release notes.
	while lines and (not lines[-1].strip() or re.match(r"^\[[^\]]+\]:\s", lines[-1])):
		lines.pop()

	body = "\n".join(lines).strip("\n")
	if not body:
		sys.exit("the '## " + want + "' section in CHANGELOG.md is empty")
	print(body)


# The tool embeds the template with `#load`, so tools/skel/templates.odin is a second listing of the
# repo's own files and can go stale the moment one is added or removed. Same drift problem the
# snippets have, so it gets the same treatment: a generator plus a --check mode for CI.
# Run after adding, removing or renaming a template file.
# ---
# (re)generate tools/skel/templates.odin from the tracked template files
embed:
	just _embed write

# Non-zero exit + diff if stale. Wire into pre-commit / CI alongside `snippets-check`.
# ---
# verify tools/skel/templates.odin matches the tracked template files
embed-check:
	just _embed check

[script]
_embed mode:
	import subprocess, sys, os, re

	# Skeleton-only paths, never part of a scaffolded project:
	#   tools/        the odin-skel source and its design notes
	#   .github/      CI that runs embed-check / lint_skel / test_skel, all meaningless in a project
	#   packaging/    the scoop manifest and install script for distributing odin-skel
	#   CHANGELOG.md  this skeleton's history; a new project starts with none of its own
	# A project-level CI template would be a separate file, not this one - see tools/DESIGN.md.
	# bench/instructions.json is a *recorded measurement*, not template text. `just bench_count` writes
	# it and the README says to commit it, so it can legitimately be tracked here - and if it were
	# embedded, `odin-skel add bench` would copy this repository's instruction counts into every user
	# project, where `bench_count_check` would immediately diff their numbers against this machine's
	# compiler. Excluded rather than gitignored, so a maintainer can still commit one.
	EXCLUDED_PREFIXES = ("tools/", ".github/", "packaging/")
	EXCLUDED_FILES = ("CHANGELOG.md", "bench/instructions.json")
	GENERATED = os.path.join("tools", "skel", "templates.odin")

	# Files belonging to only one project kind. Everything else is `.Both`, which is the enum's zero
	# value and so is left off the generated entry entirely.
	#   mylib/     the lib template: relocated to the destination root, package clause rewritten
	#   main.odin  the exe template's entry point; a library has no main
	# Keep these in step with tools/skel/template.odin's LIB_TEMPLATE_DIR.
	LIB_TEMPLATE_DIR = "mylib"
	EXE_ONLY_FILES = ("main.odin",)

	# Optional features: directories `new` never writes and `odin-skel add <name>` writes on request.
	# Both kinds can take them, so a feature file stays `.Both` and is filtered on `feature` instead.
	# Keep in step with FEATURES in tools/skel/template.odin.
	FEATURE_DIRS = {"bench": "bench"}

	def kind_of(rel):
		if rel.startswith(LIB_TEMPLATE_DIR + "/"):
			return "Lib"
		if rel in EXE_ONLY_FILES:
			return "Exe"
		return "Both"

	def feature_of(rel):
		for directory, name in FEATURE_DIRS.items():
			if rel == directory or rel.startswith(directory + "/"):
				return name
		return ""

	files = subprocess.run(
		["git", "ls-files"], capture_output=True, text=True, check=True
	).stdout.splitlines()
	files = sorted(
		f for f in files
		if not f.startswith(EXCLUDED_PREFIXES) and f not in EXCLUDED_FILES
	)
	if not files:
		sys.exit("no template files found - is this a git checkout?")

	lines = [
		"// Code generated by `just embed`. DO NOT EDIT.",
		"//",
		"// One entry per tracked template file, embedded at compile time so that `odin-skel new` needs",
		"// neither a network nor a clone. Regenerate with `just embed`; `just embed-check` fails if this",
		"// file no longer matches the repository.",
		"package skel",
		"",
		"TEMPLATES :: []Template{",
	]
	for rel in files:
		# #load resolves relative to this generated file, which lives two directories down.
		load_path = "../../" + rel
		entry = '\t{path = "%s", data = #load("%s", string)' % (rel, load_path)
		kind = kind_of(rel)
		if kind != "Both":
			entry += ", kind = .%s" % kind
		feature = feature_of(rel)
		if feature:
			entry += ', feature = "%s"' % feature
		lines.append(entry + "},")
	lines.append("}")
	content = "\n".join(lines) + "\n"

	mode = r"{{mode}}"
	if mode == "write":
		with open(GENERATED, "w", encoding="utf-8", newline="\n") as f:
			f.write(content)
		print("wrote " + GENERATED + " (" + str(len(files)) + " template files)")
	elif mode == "check":
		# Compare the *file list*, not the file text. `just format` runs odinfmt over the whole tree
		# including this generated file, and odinfmt rewrites `[]Template{` to `[]Template {` and
		# wraps entries past character_width. A byte-exact check would therefore fail after every
		# format for reasons that have nothing to do with drift. The risk actually worth catching is
		# a template file being added, removed or renamed without regenerating, so that is what is
		# compared - which also makes the check immune to future odinfmt style changes.
		try:
			with open(GENERATED, encoding="utf-8") as f:
				current = f.read()
		except FileNotFoundError:
			sys.exit("missing " + GENERATED + ", run `just embed`")

		embedded = re.findall(r'path\s*=\s*"([^"]*)"', current)
		loaded = re.findall(r'#load\(\s*"([^"]*)"', current)

		problems = []
		for missing in sorted(set(files) - set(embedded)):
			problems.append("  not embedded: " + missing)
		for extra in sorted(set(embedded) - set(files)):
			problems.append("  no longer tracked (or now excluded): " + extra)

		# Each entry must load the file it claims to be; a hand-edit could otherwise pair a path with
		# someone else's contents and nothing would notice.
		if len(embedded) != len(loaded):
			problems.append("  %d path entries but %d #load entries" % (len(embedded), len(loaded)))
		else:
			for path, load in zip(embedded, loaded):
				if load != "../../" + path:
					problems.append("  %s loads %s" % (path, load))

		# Kinds are counted rather than matched per entry, for the same reason the text is not compared
		# byte for byte: odinfmt wraps long entries across lines, so there is no reliable way to tell
		# which `kind = .Lib` belongs to which `path =` without parsing Odin. A count still catches the
		# drift that matters - a template file added to or removed from one of the kind groups.
		for kind in ("Lib", "Exe"):
			want = sum(1 for f in files if kind_of(f) == kind)
			got = len(re.findall(r"kind\s*=\s*\." + kind + r"\b", current))
			if want != got:
				problems.append(
					"  %d files are kind .%s but %d entries say so" % (want, kind, got)
				)

		# Features are counted the same way and for the same reason. This is the check that matters most
		# of the three: a feature file that loses its tag is silently promoted into every scaffold, which
		# is exactly the bulk the feature mechanism exists to keep out.
		for feature in sorted(set(FEATURE_DIRS.values())):
			want = sum(1 for f in files if feature_of(f) == feature)
			got = len(re.findall(r'feature\s*=\s*"' + feature + r'"', current))
			if want != got:
				problems.append(
					'  %d files are feature "%s" but %d entries say so' % (want, feature, got)
				)

		if problems:
			print("\n".join(problems))
			sys.exit("stale embed list, run `just embed`")
		print("embedded templates up to date (" + str(len(files)) + " files)")
	else:
		sys.exit("unknown mode: " + mode)


# main.odin + the justfile are the source of truth, so the snippets cannot silently drift. Run after
# editing either of them.
# ---
# (re)generate the .sublime-snippet files from main.odin + justfile
snippets:
	just _snippets write

# Non-zero exit + diff if stale. Wire into pre-commit / CI to catch snippet drift.
# ---
# verify the committed snippets match what `just snippets` would generate
snippets-check:
	just _snippets check

[script]
_snippets mode:
	import sys, os, difflib

	def field_sub(text, subs):
		# replace each anchor literal exactly once, turning it into a Sublime ${n:default} field;
		# fail loudly if an anchor is missing so source drift is caught, not silently dropped.
		for find, repl in subs:
			if find not in text:
				sys.exit("snippet anchor not found (source changed?): " + repr(find))
			text = text.replace(find, repl, 1)
		return text

	def strip_marked_blocks(text, keep_body):
		# Drop every `# >>> name` ... `# <<< name` block body except the ones named in `keep_body`, whose
		# marker lines still go. A justfile snippet is one project kind's justfile, so it keeps that
		# kind's block and drops the other's. skeleton-only and snippet-exclude are always dropped: they
		# either only maintain this repo, or contain literal `$` that would corrupt the snippet.
		# `dropping` holds the NAME of the block being dropped, not just a flag. Both halves matter: an
		# inner marker cannot re-open while one is already open, and only the matching `# <<<` closes it.
		# A bare boolean gets this wrong in a way that is invisible - any `# <<<` would end the drop, so
		# a kept block nested inside a dropped one would spill the rest of the dropped block into the
		# output. Nothing nests today; this costs nothing and removes the trap.
		out, dropping = [], None
		for line in text.splitlines(keepends=True):
			s = line.strip()
			if s.startswith("# >>> "):
				name = s[len("# >>> "):].strip()
				if dropping is None and name not in keep_body:
					dropping = name
				continue
			if s.startswith("# <<< "):
				if dropping == s[len("# <<< "):].strip():
					dropping = None
				continue
			if dropping is None:
				out.append(line)
		if dropping is not None:
			sys.exit("unterminated '# >>> " + dropping + "' marker block in justfile")
		return "".join(out)

	def wrap(body, tab, scope, description):
		# `description` is what makes these findable. A tabTrigger only helps somebody who already knows
		# to type it; the description is shown beside the trigger in the completion popup and is the text
		# Tools -> Snippets... lists them under, which is the one place you can browse rather than guess.
		return (
			"<snippet>\n"
			"\t<content><![CDATA[\n"
			+ body.rstrip("\n") + "\n"
			+ "]]></content>\n"
			"\t<!-- type the tabTrigger and press Tab; or browse Tools -> Snippets... -->\n"
			"\t<tabTrigger>" + tab + "</tabTrigger>\n"
			"\t<!-- shown beside the trigger in the completion popup -->\n"
			"\t<description>" + description + "</description>\n"
			"\t<!-- Optional: Set a scope to limit where the snippet will trigger -->\n"
			"\t<scope>" + scope + "</scope>\n"
			"</snippet>\n"
		)

	with open("main.odin", encoding="utf-8") as f:
		odin = field_sub(f.read(), [
			("package main", "package ${1:main}"),
			('fmt.println("Hello")', '${2:fmt.println("Hello")}'),
			("#config(SPALL_ENABLE, false)", "#config(SPALL_ENABLE, ${3:false})"),
			(
				"#config(TRACKING_ALLOCATOR, TRACKING_ALLOCATOR_DEFAULT)",
				'#config(TRACKING_ALLOCATOR, ${4:TRACKING_ALLOCATOR_DEFAULT})',
			),
		])

	# One snippet per project kind: a justfile is one kind's justfile, so unlike the .sublime-build files
	# it cannot serve both from a single copy. The output-name fields differ because `main_name` lives in
	# an `exe-only` block and so is not in the library justfile at all - `field_sub` fails loudly on a
	# missing anchor, which is exactly the drift guard wanted here.
	with open("justfile", encoding="utf-8") as f:
		justfile_source = f.read()

	just_exe = field_sub(strip_marked_blocks(justfile_source, ("exe-only",)), [
		('main_name := "main.exe"', 'main_name := "${1:main.exe}"'),
		('test_main_name := "test-main.exe"', 'test_main_name := "${2:test-main.exe}"'),
	])
	just_lib = field_sub(strip_marked_blocks(justfile_source, ("lib-only",)), [
		('test_main_name := "test-main.exe"', 'test_main_name := "${1:test-main.exe}"'),
	])

	targets = {
		os.path.join(".sublime", "Odin-skeleton.sublime-snippet"): wrap(
			odin, "main", "source.odin", "Odin program skeleton (logging, tracking allocator, backtraces)"
		),
		os.path.join(".sublime", "Just-Odin.sublime-snippet"): wrap(
			just_exe, "odin", "source.just", "justfile for an Odin program (build tiers, test, lint)"
		),
		os.path.join(".sublime", "Just-Odin-lib.sublime-snippet"): wrap(
			just_lib, "odinlib", "source.just", "justfile for an Odin library (check, example, doc, test)"
		),
	}

	mode = r"{{mode}}"
	if mode == "write":
		for path, content in targets.items():
			with open(path, "w", encoding="utf-8", newline="\n") as f:
				f.write(content)
			print("wrote " + path)
	elif mode == "check":
		stale = []
		for path, content in targets.items():
			with open(path, encoding="utf-8") as f:
				current = f.read()
			if current != content:
				stale.append(path)
				sys.stdout.writelines(difflib.unified_diff(
					current.splitlines(keepends=True), content.splitlines(keepends=True),
					fromfile=path + " (committed)", tofile=path + " (generated)",
				))
		if stale:
			sys.exit("stale snippets, run `just snippets`: " + ", ".join(stale))
		print("snippets up to date")
	else:
		sys.exit("unknown mode: " + mode)
# <<< skeleton-only
