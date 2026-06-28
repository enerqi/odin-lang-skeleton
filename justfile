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


# lint checks for style and potential bugs. Accepts extra args like `--show-timings`as needed
lint *args:
	odin check . -vet -vet-cast -strict-style -no-entry-point {{args}}


# ensure the build artifacts top level directory exists
[unix]
@mktarget_dirs:
	-mkdir -p target
	-mkdir -p target/debug
	-mkdir -p target/fastdebug
	-mkdir -p target/release

# ensure the build artifacts top level directory exists
[windows]
@mktarget_dirs:
	-mkdir target
	-mkdir target/debug
	-mkdir target/fastdebug
	-mkdir target/release

# run with debug build (-keep-executable so `rerun_debug` can skip recompiling)
run_debug *args: mktarget_dirs
	odin run . -debug -microarch:native -show-timings -keep-executable -out:target/debug/{{main_name}} {{args}}

alias run := run_debug

# run with debug and optimizations (-keep-executable so `rerun_fastdebug` can skip recompiling)
run_fastdebug *args: mktarget_dirs
	odin run . -debug -o:speed -microarch:native -show-timings -keep-executable -out:target/fastdebug/{{main_name}} {{args}}

# run with optimizations (-keep-executable so `rerun_release` can skip recompiling)
run_release *args: mktarget_dirs
	odin run . -o:speed -microarch:native -show-timings -keep-executable -out:target/release/{{main_name}} {{args}}

# re-run the last debug binary WITHOUT recompiling (Odin has no build cache, so a plain `run` always
# rebuilds). Requires a prior `run_debug`/`run` build.
rerun_debug *args:
	./target/debug/{{main_name}} {{args}}

alias rerun := rerun_debug

# re-run the last fastdebug binary without recompiling. Requires a prior `run_fastdebug` build.
rerun_fastdebug *args:
	./target/fastdebug/{{main_name}} {{args}}

# re-run the last release binary without recompiling. Requires a prior `run_release` build.
rerun_release *args:
	./target/release/{{main_name}} {{args}}

# run all tests
test *args: mktarget_dirs
	odin test . -debug -file -microarch:native -show-timings -out:target/debug/{{test_main_name}} {{args}}

# run one named test
test1 name *args: mktarget_dirs
	odin test . -debug -file -microarch:native -show-timings -test-name:{{name}} -out:target/debug/{{test_main_name}} {{args}}

# simple delete of all debug databases and executables in the target directory
clean:
	rm -rf target
	just mktarget_dirs

# build with some verbose diagnostics
diagnose *args: mktarget_dirs
	odin build . -debug -microarch:native -show-more-timings -show-debug-messages -show-timings -out:target/debug/{{main_name}} {{args}}


# install the editor snippets + sublime build systems into Sublime Text's global `Packages/User`
# directory (cross platform). Sublime then offers them in every window. The `.sublime-project` file
# is project-local and intentionally NOT installed. Override the destination with the
# SUBLIME_USER_DIR env var if your setup is non-standard.
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


# SKELETON: (re)generate ols.json so the editor's Odin language server resolves an extra collection
# import (`import "{{collection_name}}:pkg"`). Only needed when you pull packages from a directory
# outside this project. ols.json holds a machine-specific absolute path, so gitignore it and regenerate
# after cloning or when the path changes:  XYZ_HOME=/path/to/collection just ols-config
# FILL IN: rename collection_name / collection_path (and the XYZ_HOME env var) above to match your collection.
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

# copy this skeleton into a new or empty directory, dotfiles included (.gitignore, .editorconfig,
# .sublime/*, etc). Only git-tracked files are copied, so build artifacts, .git and untracked local
# files (e.g. .claude) are left behind. The `.sublime-project` file is renamed to the project name
# (defaults to the dest directory name). The justfile is emitted without its `# >>> skeleton-only`
# recipes (new / snippets) since they only maintain this skeleton; the *.sublime-snippet files ARE
# copied so the snippets are discoverable (install them once, globally — see the README). The skeleton's
# own Unlicense LICENSE is replaced with a fresh Zlib LICENSE (matching the Odin project's license).
# Usage:  just new ../my-new-project   or   just new ../dir projname
[script("python")]
new dest name="":
    import os, sys, shutil, subprocess, datetime
    dest = r"{{dest}}"
    if os.path.isdir(dest) and [e for e in os.listdir(dest) if e != ".git"]:
        sys.exit("refusing: '" + dest + "' exists and is not empty (ignoring .git)")
    if os.path.isfile(dest):
        sys.exit("refusing: '" + dest + "' is a file")

    def strip_skeleton_only(text):
        out, skip = [], False
        for line in text.splitlines(keepends=True):
            s = line.strip()
            if s == "# >>> skeleton-only":
                skip = True
                continue
            if s == "# <<< skeleton-only":
                skip = False
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

    proj = r"{{name}}" or os.path.basename(os.path.normpath(dest))
    files = subprocess.run(
        ["git", "ls-files"], capture_output=True, text=True, check=True
    ).stdout.splitlines()
    copied = 0
    for rel in files:
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


# (re)generate the .sublime-snippet files from main.odin + justfile (their source of truth) so the
# snippets cannot silently drift. Run after editing main.odin or the justfile.
snippets:
	just _snippets write

# verify the committed snippets match what `just snippets` would generate; non-zero exit + diff if
# stale. Wire into pre-commit / CI to catch snippet drift.
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

    def strip_skeleton_only(text):
        out, skip = [], False
        for line in text.splitlines(keepends=True):
            s = line.strip()
            if s == "# >>> skeleton-only":
                skip = True
                continue
            if s == "# <<< skeleton-only":
                skip = False
                continue
            if not skip:
                out.append(line)
        if skip:
            sys.exit("unterminated '# >>> skeleton-only' block in justfile")
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
        just = field_sub(strip_skeleton_only(f.read()), [
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
