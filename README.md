# Odin Programming Language Project Skeleton

A minimal project skeleton for writing programs in the [Odin programming language](http://odin-lang.org/)

The build artifacts are output under the `target` directory (similar to [Rust](https://www.rust-lang.org/) projects
built using `cargo`).

A `justfile` is part of this opinionated setup and you may need to edit the tasks as new packages are added in
sub-directories. [Just >=1.32](https://just.systems/) is a CLI task runner that you *need to install*. Run any task
with `just TASK`:

**Build & run** — `odin run` always recompiles the whole package (Odin has no build cache / incremental compilation):

* `just run` or `just run_debug` — debug build, then run
* `just run_fastdebug` — debug build with optimizations
* `just run_release` — optimized build
* `just diagnose` — debug build with verbose compiler timing / diagnostics

**Re-run without recompiling** — runs the `-keep-executable` binary left by the matching `run_*` task, skipping the
compile entirely (needs a prior `run_*` of the same profile):

* `just rerun` or `just rerun_debug`
* `just rerun_fastdebug`
* `just rerun_release`

**Quality:**

* `just lint` — type checking, vet warnings, strict style. No code generation
* `just format` — runs `odinfmt -w .` over the whole tree
* `just test` / `just test1 NAME` — run all tests / one named test

**Housekeeping:**

* `just clean` — wipe the `target` directory
* `just mktarget_dirs` — create the `target` directory tree (auto-called by the `run_*` tasks)

**Scaffolding & skeleton upkeep:**

* `just new DEST [NAME]` — copy this skeleton into a new project (see [Creating a new project](#creating-a-new-project))
* `just ols-config` — (re)generate `ols.json` (see [Language Server Configuration](#language-server-configuration))
* `just snippets` / `just snippets-check` — (re)generate / verify the editor snippets (see the Sublime section)
* `just install-sublime` — install the snippets + build systems into Sublime Text's global config (see the Sublime section)

Notes:

- All `run_*`, `rerun_*`, `test*` and `diagnose` tasks accept optional extra variadic arguments; add `--` before
  passing arguments to your own program. Edit the `main_name` / `test_main_name` output executable names as needed.
- `format` assumes `odinfmt` is on your `PATH`. It can be built from source within the
  [Odin language server](https://github.com/DanielGavin/ols) code (see `odinfmt.bat` / `odinfmt.sh`). OLS is
  recommended when editing Odin code.
- `clean` assumes your shell can do `rm -rf`. The opinionated default shell on Windows is `nushell` (`nu -c`), which
  supports it — see [configuring the just shell](https://just.systems/man/en/chapter_63.html?highlight=set%20shell#configuring-the-shell).


## Creating a new project

`just new DEST [NAME]` copies this skeleton into a new or empty directory `DEST` (a `.git/` already present is fine —
usually it was just `git init`-ed; any other content makes it refuse). `NAME` defaults to the `DEST` directory name.

Only git-tracked files are copied, so build artifacts, `.git/` and untracked local files are left behind. A few things
are rewritten rather than copied verbatim:

* the `.sublime-project` file is renamed to `NAME.sublime-project`
* the skeleton's [Unlicense](https://unlicense.org) `LICENSE` is replaced with a fresh [Zlib](https://opensource.org/license/zlib)
  `LICENSE` (matching the Odin project's own license)
* the `justfile` is emitted without its `# >>> skeleton-only` recipes (`new`, `snippets`, `snippets-check`) — those
  only maintain this skeleton, not a real project

The `.sublime-snippet` files are copied so you stay aware of them, but treat them as a one-off starting point (the
generator that keeps them in sync stays behind — see the Sublime section).


## [Sublime Text](https://www.sublimetext.com/) editor specific files

The `OdinJustTarget.sublime-build` file is an example [sublime build file](https://www.sublimetext.com/docs/build_systems.html). Delete it if no developer is using sublime text.
The `Odin.sublime-build` file is similar but doesn't assume you have `just` installed.
Same for the very basic `.sublime-project` file.

Rename the `.sublime-project` file to match your project if keeping.

If you install the `.sublime-build` file(s) you get a lot of build options for *compiling* either the individual file
or the current package of the file open in the editor. The artifacts are output to the `target` directory (or
current directory if not using `just`).

The build options also include *linting* and *testing*.

This is a basic sublime build system and can be improved upon. You may want your own project specific `just` build
tasks or sublime build files. More flexibility is needed if you need things like custom `-define` compile time
parameters or multi stage conditional build steps. Rare custom steps are easy enough to run from the cli with extra
task arguments, but frequently ran things maybe more conveniently executed through a sublime build file and so require
some project specific customisation.

The sublime `.sublime-snippet` example triggers creation of this "main" skeleton, useful when you want a quick script
file without necessarily using the `justfile` for build management (triggered by `main`). Similarly, there is a snippet
for filling in a new empty Justfile (triggered by `odin`).

Sublime snippets and build systems are installed **globally**, not per project: Sublime loads everything under its
`Packages/User` folder and offers it (snippets by `tabTrigger` within the matching `scope`; build systems in the
Tools → Build System menu) in all windows. So you install them once and they apply everywhere.

`just install-sublime` does this for you, cross platform — it copies the two `.sublime-snippet` files and the two
`.sublime-build` files into Sublime's `Packages/User` directory (resolved per-OS; override with the `SUBLIME_USER_DIR`
env var if your install is non-standard). The per-project `.sublime-project` file is intentionally not installed.

`just new` copies the `.sublime-snippet` files into a new project so you stay aware of them, but strips the
snippet-generator recipes from the copied justfile (they only maintain this skeleton) — once detached, treat the copied
snippets as a one-off starting point rather than something kept in sync.

These two snippets are **generated** from `main.odin` and the `justfile` (their single source of truth) so they cannot
silently drift out of date:

* `just snippets` regenerates `.sublime/Odin-skeleton.sublime-snippet` and `.sublime/Just-Odin.sublime-snippet`. Run it
  after editing `main.odin` or the `justfile`.
* `just snippets-check` exits non-zero (with a diff) if the committed snippets no longer match what generation would
  produce — wire it into a pre-commit hook or CI to catch drift.

The generator only adds the snippet XML wrapper plus a few `${n:default}` interactive fields (package name, the
`main_program` body, the `#config` defaults, the executable names). Recipes wrapped between the `# >>> skeleton-only`
and `# <<< skeleton-only` markers in the `justfile` (e.g. `new`, `snippets`) are stripped from the Justfile snippet,
since they only make sense inside this skeleton repo, not in a project the snippet is dropped into.


## Language Server Configuration

This is also optional, delete if not needed. As the [Odin language server](https://github.com/DanielGavin/ols) docs
show you can configure OLS settings in ways specific to your editor, often in a global manner - once per all projects.

However, you can also use the `ols.json` file, perhaps to add odin "collections" specific to your project.
This is initially an empty collection list.

If you do need an extra collection (so OLS resolves `import "xyz:pkg"` from a directory outside this project),
the `ols-config` just task regenerates `ols.json` for you:

* edit the `collection_name` / `collection_path` variables (and the `XYZ_HOME` env var name) near the top of the
	`justfile` to match your collection
* run e.g. `XYZ_HOME=/path/to/collection just ols-config`

Because the path is an absolute, machine-specific location, prefer to gitignore `ols.json` and have each developer
regenerate it after cloning or whenever the path changes.
