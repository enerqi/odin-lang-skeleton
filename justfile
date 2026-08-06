set windows-shell := ["nu", "-c"]
set shell := ["bash", "-c"]
set unstable  # [script("python")] feature - https://github.com/casey/just/issues/1479

main_name := "main.exe"
test_main_name := "test-main.exe"

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


# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
	-mkdir -p target
	-mkdir -p target/debug
	-mkdir -p target/fast_debug
	-mkdir -p target/release_debug
	-mkdir -p target/release
	-mkdir -p target/release_nochecks

# ensure the build artifacts top level directory exists
[windows]
@mktarget_dirs:
	-mkdir target
	-mkdir target/debug
	-mkdir target/fast_debug
	-mkdir target/release_debug
	-mkdir target/release
	-mkdir target/release_nochecks

# `-debug` implies `-o:none`, so this is the fastest to compile and the friendliest to step through.
# (-keep-executable so `rerun_debug` can skip recompiling)
# ---
# run with debug build
run_debug *args: mktarget_dirs
	odin run . -debug -microarch:native -keep-executable -out:target/debug/{{main_name}} {{args}}

alias run := run_debug

# `-o:minimal` is one rung above the `-debug` default of `-o:none`: still quick to compile and mostly
# faithful to step through, but noticeably faster at runtime.
# (-keep-executable so `rerun_fast_debug` can skip recompiling)
# ---
# run with debug info and light optimizations
run_fast_debug *args: mktarget_dirs
	odin run . -debug -o:minimal -microarch:native -keep-executable -out:target/fast_debug/{{main_name}} {{args}}

# Release codegen with debug info retained: for profiling and for chasing bugs that only appear under
# optimization. Slowest to compile, and the debugger will jump around inlined/reordered code.
# (-keep-executable so `rerun_release_debug` can skip recompiling)
# ---
# run with full optimizations AND debug info
run_release_debug *args: mktarget_dirs
	odin run . -debug -o:speed -microarch:native -keep-executable -out:target/release_debug/{{main_name}} {{args}}

# run with optimizations (-keep-executable so `rerun_release` can skip recompiling)
run_release *args: mktarget_dirs
	odin run . -o:speed -microarch:native -keep-executable -out:target/release/{{main_name}} {{args}}

# `run_release` plus every runtime safety check compiled out: `-no-bounds-check` (slice/array indexing),
# `-disable-assert` (the built-in `assert`) and `-no-type-assert` (union/any type assertions). Those
# checks are what turn a memory-corrupting bug into a clean panic, so a fault here is undefined
# behaviour rather than a readable message - benchmark against `run_release` before adopting it, and
# keep a checked build in your test matrix. `-o:aggressive` exists too but Odin flags it as risky.
# (-keep-executable so `rerun_release_nochecks` can skip recompiling)
# ---
# run with optimizations and ALL runtime safety checks removed
run_release_nochecks *args: mktarget_dirs
	odin run . -o:speed -no-bounds-check -disable-assert -no-type-assert -microarch:native -keep-executable -out:target/release_nochecks/{{main_name}} {{args}}

# `address` (ASan) catches out-of-bounds accesses and use-after-free; `memory` catches reads of
# uninitialized memory; `thread` catches data races. Only `address` is widely supported - `memory` and
# `thread` need a clang-ish toolchain and are unavailable on some platforms (notably Windows/MSVC).
# Built with `-debug` so reports carry file/line info, and to its own output name so it does not clobber
# the plain debug binary.
# Usage:  just sanitize   or   just sanitize thread -- --my-arg
# ---
# run a debug build under a sanitizer (address | memory | thread)
sanitize kind="address" *args: mktarget_dirs
	odin run . -debug -sanitize:{{kind}} -out:target/debug/sanitize-{{kind}}-{{main_name}} {{args}}

# same sanitizer options as `sanitize`; see its notes for platform support.
# ---
# run the tests under a sanitizer (address | memory | thread)
test_sanitize kind="address" *args: mktarget_dirs
	odin test . -debug -file -sanitize:{{kind}} -out:target/debug/sanitize-{{kind}}-{{test_main_name}} {{args}}

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
	odin test . -debug -file -microarch:native -out:target/debug/{{test_main_name}} {{args}}

# run one named test
test1 name *args: mktarget_dirs
	odin test . -debug -file -microarch:native -test-name:{{name}} -out:target/debug/{{test_main_name}} {{args}}

# simple delete of all debug databases and executables in the target directory
clean:
	rm -rf target
	just mktarget_dirs

# build with some verbose diagnostics
diagnose *args: mktarget_dirs
	odin build . -debug -microarch:native -show-more-timings -show-debug-messages -show-timings -out:target/debug/{{main_name}} {{args}}


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
# Recipes below operate on the skeleton repo itself (scaffold a new project, regenerate the editor
# snippets). They are stripped from the Just-Odin.sublime-snippet because they are meaningless once
# the justfile is dropped into a real project. Leave the `# >>> / # <<< skeleton-only` markers in place.

# Dotfiles included (.gitignore, .editorconfig, .sublime/*, etc). Only git-tracked files are copied,
# so build artifacts, .git and untracked local files (e.g. .claude) are left behind. The
# `.sublime-project` file is renamed to the project name (defaults to the dest directory name). The
# justfile is emitted without its `# >>> skeleton-only` recipes (new / snippets) since they only
# maintain this skeleton; the *.sublime-snippet files ARE copied so the snippets are discoverable
# (install them once, globally — see the README). The skeleton's own Unlicense LICENSE is replaced
# with a fresh Zlib LICENSE (matching the Odin project's license).
# Usage:  just new ../my-new-project   or   just new ../dir projname
# ---
# copy this skeleton into a new or empty directory
[script("python")]
new dest name="":
	import os, sys, shutil, subprocess, datetime
	dest = r"{{dest}}"
	if os.path.isdir(dest) and [e for e in os.listdir(dest) if e != ".git"]:
		sys.exit("refusing: '" + dest + "' exists and is not empty (ignoring .git)")
	if os.path.isfile(dest):
		sys.exit("refusing: '" + dest + "' is a file")

	def strip_skeleton_only(text):
		# drop whole `# >>> skeleton-only` blocks; keep the content of other marker blocks (e.g.
		# snippet-exclude) but drop their now-irrelevant marker comment lines.
		out, skip = [], False
		for line in text.splitlines(keepends=True):
			s = line.strip()
			if s == "# >>> skeleton-only":
				skip = True
				continue
			if s == "# <<< skeleton-only":
				skip = False
				continue
			if s.startswith("# >>> ") or s.startswith("# <<< "):
				continue
			if not skip:
				out.append(line)
		return "".join(out).rstrip("\n") + "\n"

	def zlib_license():
		year = datetime.date.today().year
		return (
			"Copyright (c) {year}\n\n"
			"This software is provided 'as-is', without any express or implied\n"
			"warranty. In no event will the authors be held liable for any damages\n"
			"arising from the use of this software.\n\n"
			"Permission is granted to anyone to use this software for any purpose,\n"
			"including commercial applications, and to alter it and redistribute it\n"
			"freely, subject to the following restrictions:\n\n"
			"1. The origin of this software must not be misrepresented; you must not\n"
			"   claim that you wrote the original software. If you use this software\n"
			"   in a product, an acknowledgment in the product documentation would be\n"
			"   appreciated but is not required.\n\n"
			"2. Altered source versions must be plainly marked as such, and must not be\n"
			"   misrepresented as being the original software.\n\n"
			"3. This notice may not be removed or altered from any source distribution.\n"
		).format(year=year)

	# Paths that belong to the skeleton's own tooling rather than to the template. `tools/` holds the
	# `odin-skel` binary's source and design docs (see tools/DESIGN.md) - a scaffolded project must not
	# inherit it. Keep in sync with tools/DESIGN.md's "Repository layout" section.
	EXCLUDED_PREFIXES = ("tools/",)

	proj = r"{{name}}" or os.path.basename(os.path.normpath(dest))
	files = subprocess.run(
		["git", "ls-files"], capture_output=True, text=True, check=True
	).stdout.splitlines()
	copied = skipped = 0
	for rel in files:
		if rel.startswith(EXCLUDED_PREFIXES):
			skipped += 1
			continue
		src = os.path.join(os.getcwd(), rel)
		out_rel = rel
		if rel.endswith(".sublime-project"):
			out_rel = os.path.join(os.path.dirname(rel), proj + ".sublime-project")
		dst = os.path.join(dest, out_rel)
		os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
		if rel == "justfile":  # drop the skeleton-only recipes from the project's justfile
			with open(src, encoding="utf-8") as f:
				content = strip_skeleton_only(f.read())
			with open(dst, "w", encoding="utf-8", newline="\n") as f:
				f.write(content)
		elif rel == "LICENSE":  # skeleton is Unlicense; new project gets a fresh Zlib license
			with open(dst, "w", encoding="utf-8", newline="\n") as f:
				f.write(zlib_license())
		else:
			shutil.copy2(src, dst)
		copied += 1
	print("copied " + str(copied) + " skeleton files to " + dest + " (project '" + proj + "', Zlib license)")
	if skipped:
		print("skipped " + str(skipped) + " skeleton-tooling files (" + ", ".join(EXCLUDED_PREFIXES) + ")")


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
			("#config(TIME_PROGRAM_DURATION_ENABLE, false)", "#config(TIME_PROGRAM_DURATION_ENABLE, ${3:false})"),
			("#config(MIMALLOC_ENABLE, false)", "#config(MIMALLOC_ENABLE, ${4:false})"),
			("#config(SPALL_ENABLE, false)", "#config(SPALL_ENABLE, ${5:false})"),
			("#config(BACKTRACE_ENABLE, false)", "#config(BACKTRACE_ENABLE, ${6:false})"),
			("#config(TRACKING_ALLOCATOR_ENABLE, true)", "#config(TRACKING_ALLOCATOR_ENABLE, ${7:true})"),
			('// import mi "../odin-mimalloc/mimalloc"', '$8// import mi "../odin-mimalloc/mimalloc"'),
			('// import back "../back"', '$9// import back "../back"'),
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
