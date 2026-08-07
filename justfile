# Windows PowerShell 5.1 ships with Windows, so this needs no install - unlike nushell, which was the
# previous default and is absent from stock machines and from GitHub's windows runners. `pwsh` (7.x)
# would also work but has to be installed separately.
# -NoProfile keeps recipes reproducible: a developer's profile cannot redefine an alias a recipe uses.
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]
set shell := ["bash", "-c"]
set unstable  # [script("python")] feature - https://github.com/casey/just/issues/1479
set lazy

main_name := "main.exe"
test_main_name := "test-main.exe"

# Which linker Odin hands the object files to. `odin build -linker:` accepts exactly four values:
#
#   default   let Odin choose - MSVC `link.exe` on Windows. The portable answer, and what every
#             platform used before this line existed.
#   lld       LLVM's linker. Windows and Linux. NOT available on a stock macOS: Odin drives the
#             link through clang, and Apple's clang ships no lld, so it fails with
#             "clang: error: invalid linker name in argument '-fuse-ld=lld'" unless you have
#             installed LLVM yourself. Note this is clang rejecting it, not Odin - `-linker:` takes
#             the value on every platform, so unlike mold there is no "not supported on this
#             platform" message to tell you up front.
#   radlink   RAD Debugger's linker. Windows only, and it ships *with* the Odin toolchain, so it
#             needs no install - which is why it is the default here. Odin has no build cache and
#             relinks on every `just run`, so the link step is a cost you pay on each iteration.
#   mold      Linux only, and NOT bundled - `apt install mold` (or equivalent) first.
#
# When the default is the better pick: neither radlink nor mold is an *incremental* linker, while
# MSVC `link.exe` is. Combined with `-use-separate-modules` (and `-lto`, which implies it), an
# incremental relink of one changed module can beat a full link that is individually faster. That
# combination is not the default shape of an Odin build - single-module builds have little for LTO
# to chew on, and statically linked external C libraries do not get LTO regardless - so it is worth
# measuring on your own project rather than assuming either way.
#
# `-lto` is also a hard conflict rather than a preference: on Windows it *requires* `-linker:lld`
# and exits 1 with "-lto:thin on Windows requires -linker:lld" if anything else is pinned. Use the
# env var below to get out of the way of it:
#
#     ODIN_LINKER=lld just run_release -lto:thin
#
# Odin rejects a linker its platform does not support rather than quietly falling back: asking for
# mold on Windows exits 1 with "'mold' linker is not supported on this platform" and produces no
# binary. That is the behaviour you want from a per-machine setting, so nothing here second-guesses
# it.
#
# The default below is what `odin-skel new --linker=<value>` rewrites. The env var overrides it for
# a single command, without editing this file - for the LTO case above, or for a machine that has
# mold when the project default does not assume it:
#
#     ODIN_LINKER=lld just run
#
# It is an env var rather than a recipe argument because `odin` errors on a repeated flag
# ("Previous flag set: 'linker'"), so passing `-linker:` through a recipe's `*args` would collide
# with the one added below.
linker := env_var_or_default("ODIN_LINKER", if os() == "windows" { "radlink" } else { "default" })

# SKELETON: name your extra collection (the `xyz:` prefix in `import "xyz:pkg"`) and where it lives.
# collection_path is read from an env var so the absolute path stays out of git; rename both to suit.
collection_name := "xyz"
collection_path := env_var_or_default("XYZ_HOME", "")

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


# Every `run_*`, `test*` and `diagnose` recipe depends on this, so it runs before every build - which
# makes its cost a tax on every iteration, and worth keeping small. odin does not create the output
# directory (the linker fails with LNK1104), so this cannot just be dropped.
#
# The directories are created all at once rather than one per line because just starts a new shell
# per recipe line, and on Windows the shell launch dwarfs the work: hyperfine puts `powershell.exe
# -NoProfile -Command exit` at ~149ms against ~40ms for the actual directory creation. Note the
# corollary - scoping this to only the one directory a given recipe needs saves ~5ms of that 40 and
# is not worth the complexity; the shell launch is the whole cost.
# ---
# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
	mkdir -p target/debug target/fast_debug target/release_debug target/release target/release_nochecks

# Windows deliberately does NOT use this file's `windows-shell` (PowerShell): at ~149ms of startup it
# made this recipe ~190ms, versus ~10ms for cmd.exe. `[script]` + `[extension]` override the shell for
# this recipe alone - just writes the body to a temp `.cmd` and hands it to `cmd /c` - which measures
# ~27ms end to end, a ~7x saving on every build. (`.cmd` is required: cmd will not execute a script
# file without a recognised extension.)
#
# `if not exist` rather than swallowing md's "already exists" with `2>nul`, so a genuine failure still
# sets a non-zero exit. `%%d` is doubled because the body is a batch *file*, not a command line.
# ---
# ensure the build artifacts top level directory exists
[windows]
[script("cmd.exe", "/c")]
[extension(".cmd")]
mktarget_dirs:
	@for %%d in (debug fast_debug release_debug release release_nochecks) do @if not exist target\%%d md target\%%d || exit /b 1

# `-debug` implies `-o:none`, so this is the fastest to compile and the friendliest to step through.
# (-keep-executable so `rerun_debug` can skip recompiling)
# ---
# run with debug build
run_debug *args: mktarget_dirs
	odin run . -debug -microarch:native -keep-executable -linker:{{linker}} -out:target/debug/{{main_name}} {{args}}

alias run := run_debug

# `-o:minimal` is one rung above the `-debug` default of `-o:none`: still quick to compile and mostly
# faithful to step through, but noticeably faster at runtime.
# (-keep-executable so `rerun_fast_debug` can skip recompiling)
# ---
# run with debug info and light optimizations
run_fast_debug *args: mktarget_dirs
	odin run . -debug -o:minimal -microarch:native -keep-executable -linker:{{linker}} -out:target/fast_debug/{{main_name}} {{args}}

# Release codegen with debug info retained: for profiling and for chasing bugs that only appear under
# optimization. Slowest to compile, and the debugger will jump around inlined/reordered code.
# (-keep-executable so `rerun_release_debug` can skip recompiling)
# ---
# run with full optimizations AND debug info
run_release_debug *args: mktarget_dirs
	odin run . -debug -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:target/release_debug/{{main_name}} {{args}}

# run with optimizations (-keep-executable so `rerun_release` can skip recompiling)
run_release *args: mktarget_dirs
	odin run . -o:speed -microarch:native -keep-executable -linker:{{linker}} -out:target/release/{{main_name}} {{args}}

# `run_release` plus every runtime safety check compiled out: `-no-bounds-check` (slice/array indexing),
# `-disable-assert` (the built-in `assert`) and `-no-type-assert` (union/any type assertions). Those
# checks are what turn a memory-corrupting bug into a clean panic, so a fault here is undefined
# behaviour rather than a readable message - benchmark against `run_release` before adopting it, and
# keep a checked build in your test matrix. `-o:aggressive` exists too but Odin flags it as risky.
# (-keep-executable so `rerun_release_nochecks` can skip recompiling)
# ---
# run with optimizations and ALL runtime safety checks removed
run_release_nochecks *args: mktarget_dirs
	odin run . -o:speed -no-bounds-check -disable-assert -no-type-assert -microarch:native -keep-executable -linker:{{linker}} -out:target/release_nochecks/{{main_name}} {{args}}

# `address` (ASan) catches out-of-bounds accesses and use-after-free; `memory` catches reads of
# uninitialized memory; `thread` catches data races. Only `address` is widely supported - `memory` and
# `thread` need a clang-ish toolchain and are unavailable on some platforms (notably Windows/MSVC).
# Built with `-debug` so reports carry file/line info, and to its own output name so it does not clobber
# the plain debug binary.
# Usage:  just sanitize   or   just sanitize thread -- --my-arg
# ---
# run a debug build under a sanitizer (address | memory | thread)
sanitize kind="address" *args: mktarget_dirs
	odin run . -debug -sanitize:{{kind}} -linker:{{linker}} -out:target/debug/sanitize-{{kind}}-{{main_name}} {{args}}

# same sanitizer options as `sanitize`; see its notes for platform support.
# ---
# run the tests under a sanitizer (address | memory | thread)
test_sanitize kind="address" *args: mktarget_dirs
	odin test . -debug -file -sanitize:{{kind}} -linker:{{linker}} -out:target/debug/sanitize-{{kind}}-{{test_main_name}} {{args}}

# Odin has no build cache, so a plain `run` always rebuilds. Requires a prior `run_debug`/`run` build.
# ---
# re-run the last debug binary WITHOUT recompiling
rerun_debug *args:
	./target/debug/{{main_name}} {{args}}

alias rerun := rerun_debug

# re-run the last fast_debug binary without recompiling. Requires a prior `run_fast_debug` build.
rerun_fast_debug *args:
	./target/fast_debug/{{main_name}} {{args}}

# re-run the last release_debug binary without recompiling. Requires a prior `run_release_debug` build.
rerun_release_debug *args:
	./target/release_debug/{{main_name}} {{args}}

# re-run the last release binary without recompiling. Requires a prior `run_release` build.
rerun_release *args:
	./target/release/{{main_name}} {{args}}

# re-run the last nochecks binary without recompiling. Requires a prior `run_release_nochecks` build.
rerun_release_nochecks *args:
	./target/release_nochecks/{{main_name}} {{args}}

# run all tests
test *args: mktarget_dirs
	odin test . -debug -file -microarch:native -linker:{{linker}} -out:target/debug/{{test_main_name}} {{args}}

# run one named test
test1 name *args: mktarget_dirs
	odin test . -debug -file -microarch:native -test-name:{{name}} -linker:{{linker}} -out:target/debug/{{test_main_name}} {{args}}

# simple delete of all debug databases and executables in the target directory
[unix]
clean:
	rm -rf target
	just mktarget_dirs

# PowerShell has no `rm -rf`: `rm` is an alias for Remove-Item, which rejects `-rf` outright
# (NamedParameterNotFound), so the flags have to be spelled out. Guarded by Test-Path because
# Remove-Item errors on a missing path.
# ---
# simple delete of all debug databases and executables in the target directory
[windows]
clean:
	if (Test-Path target) { Remove-Item -Recurse -Force target }
	just mktarget_dirs

# build with some verbose diagnostics
diagnose *args: mktarget_dirs
	odin build . -debug -microarch:native -show-more-timings -show-debug-messages -show-timings -linker:{{linker}} -out:target/debug/{{main_name}} {{args}}


# Cross platform: Sublime then offers them in every window. The `.sublime-project` file is
# project-local and intentionally NOT installed. Override the destination with the SUBLIME_USER_DIR
# env var if your setup is non-standard.
# ---
# install the editor snippets + build systems into Sublime Text's global `Packages/User` directory
[script("python")]
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
		"Odin.sublime-build",
		"OdinJustTarget.sublime-build",
	):
		shutil.copy2(os.path.join(".sublime", name), os.path.join(target, name))
		print("installed " + name)
	print("-> " + target)


# >>> snippet-exclude
# Opening the project in Sublime then exposes project-local build variants (Tools -> Build System) with
# no global install. Seeds one working `just run` build plus commented-out examples to extend. Refuses
# if a build_systems entry already exists. (Excluded from the Just-Odin snippet because it contains
# literal `$file` / `$project_path` which would be parsed as snippet fields; still copied into new
# projects by `just new`.)
# ---
# add a `build_systems` stub to the project's .sublime-project
[script("python")]
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
		'            "shell_cmd": "just run",\n'
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
		'            //     { "name": "release",                "shell_cmd": "just run_release" },\n'
		'            //     { "name": "test",                   "shell_cmd": "just test" },\n'
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


# Resolves an extra collection import (`import "{{collection_name}}:pkg"`). Only needed when you pull
# packages from a directory outside this project. ols.json holds a machine-specific absolute path, so
# gitignore it and regenerate after cloning or when the path changes:
#     XYZ_HOME=/path/to/collection just ols-config
# FILL IN: rename collection_name / collection_path (and the XYZ_HOME env var) above to match your collection.
# ---
# SKELETON: (re)generate ols.json so the Odin language server resolves an extra collection
[script("python")]
ols-config:
	import json, sys
	path = r"{{collection_path}}"
	if not path:
		sys.exit("set the collection path env var first, e.g. XYZ_HOME=/path/to/collection just ols-config")
	config = {
		"$schema": "https://raw.githubusercontent.com/DanielGavin/ols/master/misc/ols.schema.json",
		"collections": [{"name": "{{collection_name}}", "path": path}],
	}
	with open("ols.json", "w") as f:
		f.write(json.dumps(config, indent=4) + "\n")
	print("wrote ols.json -> {{collection_name}} collection at " + path)


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
	odin test tools/skel -debug -linker:{{linker}} -out:target/debug/{{skel_test_name}} {{args}}

# The version is stamped in at build time; an unstamped build reports "dev". Release builds pass
# `-define:SKEL_VERSION=x.y.z` (see tools/DESIGN.md).
# ---
# build the odin-skel tool into target/debug/
build_skel *args: mktarget_dirs
	odin build tools/skel -debug -linker:{{linker}} -out:target/debug/{{skel_name}} {{args}}

# What CI publishes: optimized, no debug info, and stamped with the tag it was built from.
# Deliberately NOT -microarch:native - a published binary has to run on any machine of that
# architecture, not just the builder. Also deliberately NOT `-linker:{{linker}}`: link speed is
# worth nothing on a once-per-tag build, and the one artifact that cannot be quietly rebuilt if a
# linker turns out to have a quirk is the one users download.
#   just build_skel_release -define:SKEL_VERSION=1.2.3
# ---
# build an optimized odin-skel into target/release/
build_skel_release *args: mktarget_dirs
	odin build tools/skel -o:speed -out:target/release/{{skel_name}} {{args}}

# Thin wrapper: the scaffolding logic lives in the odin-skel binary and nowhere else, so the two
# cannot drift (see tools/DESIGN.md, Decision 2). Build the binary first with `just build_skel`.
# Usage:  just new ../my-new-project   or   just new ../dir projname
#         just new ../dir projname --linker=mold
# `flags` is a passthrough, so every odin-skel option works here without this recipe growing a
# parameter per option.
# ---
# copy this skeleton into a new or empty directory
[script("python")]
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


# Moves everything under `## [Unreleased]` into a new `## [VERSION] - <today>` heading, leaves a
# fresh empty Unreleased above it, and fixes the link definitions at the bottom of the file.
#
# Edits CHANGELOG.md and stops. It does not commit, stage or tag: an automated tag is fine until the
# day it fires on the wrong branch, and reviewing the diff before releasing is the point.
#
#   just release 0.1.1      # then: review, commit, tag, push
# ---
# promote CHANGELOG.md's Unreleased section to a version heading
[script("python")]
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
[script("python")]
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

[script("python")]
_embed mode:
	import subprocess, sys, os, re

	# Skeleton-only paths, never part of a scaffolded project:
	#   tools/        the odin-skel source and its design notes
	#   .github/      CI that runs embed-check / lint_skel / test_skel, all meaningless in a project
	#   packaging/    the scoop manifest and install script for distributing odin-skel
	#   CHANGELOG.md  this skeleton's history; a new project starts with none of its own
	# A project-level CI template would be a separate file, not this one - see tools/DESIGN.md.
	EXCLUDED_PREFIXES = ("tools/", ".github/", "packaging/")
	EXCLUDED_FILES = ("CHANGELOG.md",)
	GENERATED = os.path.join("tools", "skel", "templates.odin")

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
		lines.append('\t{path = "%s", data = #load("%s", string)},' % (rel, load_path))
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

[script("python")]
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

	def strip_marked_blocks(text):
		# drop every `# >>> name` ... `# <<< name` block (skeleton-only, snippet-exclude, ...): such
		# recipes either only maintain the skeleton or contain literal `$` that would corrupt the snippet.
		out, skip = [], False
		for line in text.splitlines(keepends=True):
			s = line.strip()
			if s.startswith("# >>> "):
				skip = True
				continue
			if s.startswith("# <<< "):
				skip = False
				continue
			if not skip:
				out.append(line)
		if skip:
			sys.exit("unterminated '# >>> ...' marker block in justfile")
		return "".join(out)

	def wrap(body, tab, scope):
		return (
			"<snippet>\n"
			"\t<content><![CDATA[\n"
			+ body.rstrip("\n") + "\n"
			+ "]]></content>\n"
			"\t<!-- Optional: Set a tabTrigger to define how to trigger the snippet -->\n"
			"\t<tabTrigger>" + tab + "</tabTrigger>\n"
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

	with open("justfile", encoding="utf-8") as f:
		just = field_sub(strip_marked_blocks(f.read()), [
			('main_name := "main.exe"', 'main_name := "${1:main.exe}"'),
			('test_main_name := "test-main.exe"', 'test_main_name := "${2:test-main.exe}"'),
		])

	targets = {
		os.path.join(".sublime", "Odin-skeleton.sublime-snippet"): wrap(odin, "main", "source.odin"),
		os.path.join(".sublime", "Just-Odin.sublime-snippet"): wrap(just, "odin", "source.just"),
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
