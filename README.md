# Odin Programming Language Project Skeleton

A minimal project skeleton for writing programs in the [Odin programming language](http://odin-lang.org/)

The build artifacts are output under the `target` directory (similar to [Rust](https://www.rust-lang.org/) projects
built using `cargo`).

<!-- >>> skeleton-only -->
## Quick start

Either clone this repository and work in it directly, or use the `odin-skel` binary to stamp out a new project
without cloning anything — see [Installing odin-skel](#installing-odin-skel).

```
odin-skel new ../my-project     # or: git clone this repo and `just new ../my-project`
cd ../my-project
just run
```

<!-- <<< skeleton-only -->

A `justfile` is part of this opinionated setup and you may need to edit the tasks as new packages are added in
sub-directories. [Just >=1.32](https://just.systems/) is a CLI task runner that you *need to install*. Run any task
with `just TASK`:

**Build & run** — `odin run` always recompiles the whole package (Odin has no build cache / incremental compilation).
Each profile writes to its own `target/` sub-directory, so switching between them never clobbers another build:

| task | optimization | debug info | output |
| --- | --- | --- | --- |
| `just run` / `just run_debug` | `-o:none` (the `-debug` default) | yes | `target/debug/` |
| `just run_fast_debug` | `-o:minimal` | yes | `target/fast_debug/` |
| `just run_release_debug` | `-o:speed` | yes | `target/release_debug/` |
| `just run_release` | `-o:speed` | no | `target/release/` |
| `just run_release_nochecks` | `-o:speed`, no runtime checks | no | `target/release_nochecks/` |

* `run_fast_debug` trades a little step-through fidelity for a much faster binary; still quick to compile
* `run_release_debug` is release codegen with symbols kept — for profiling and for bugs that only appear optimized
* `run_release_nochecks` additionally compiles out `-no-bounds-check`, `-disable-assert` and `-no-type-assert`. Those
  checks are what turn a memory-corrupting bug into a clean panic, so measure the gain before adopting it and keep a
  checked build in your test matrix
* `just diagnose` — debug build with verbose compiler timing / diagnostics

**Re-run without recompiling** — runs the `-keep-executable` binary left by the matching `run_*` task, skipping the
compile entirely (needs a prior `run_*` of the same profile):

* `just rerun` or `just rerun_debug`
* `just rerun_fast_debug`
* `just rerun_release_debug`
* `just rerun_release`
* `just rerun_release_nochecks`

**Quality:**

* `just lint` — type checking, vet warnings, strict style. No code generation
* `just format` — runs `odinfmt -w .` over the whole tree
* `just test` / `just test1 NAME` — run all tests / one named test
* `just sanitize [KIND]` / `just test_sanitize [KIND]` — run the program / the tests under a sanitizer. `KIND` is
  `address` (default), `memory` or `thread`. Only `address` is widely supported; `memory` and `thread` need a
  clang-ish toolchain and are unavailable on some platforms (notably Windows/MSVC)

**Housekeeping:**

* `just clean` — wipe the `target` directory
* `just mktarget_dirs` — create the `target` directory tree (auto-called by the `run_*` tasks)

**Editor setup:**

* `just ols-config` — (re)generate `ols.json` (see [Language Server Configuration](#language-server-configuration))
* `just install-sublime` — install the snippets + build systems into Sublime Text's global config (see the Sublime section)
* `just sublime-build-init` — add a project-local build-system stub to the `.sublime-project` (see the Sublime section)

<!-- >>> skeleton-only -->
**Skeleton upkeep** (these recipes maintain the skeleton repository itself and are stripped from a
scaffolded project):

* `just new DEST [NAME]` — copy this skeleton into a new project (see [Creating a new project](#creating-a-new-project))
* `just snippets` / `just snippets-check` — (re)generate / verify the editor snippets (see the Sublime section)
* `just embed` / `just embed-check` — (re)generate / verify the template list compiled into `odin-skel`
* `just build_skel` / `just build_skel_release` / `just lint_skel` / `just test_skel` — build, lint and test the
  `odin-skel` binary
<!-- <<< skeleton-only -->

Notes:

- All `run_*`, `rerun_*`, `test*` and `diagnose` tasks accept optional extra variadic arguments; add `--` before
  passing arguments to your own program. Edit the `main_name` / `test_main_name` output executable names as needed.
- `format` assumes `odinfmt` is on your `PATH`. It can be built from source within the
  [Odin language server](https://github.com/DanielGavin/ols) code (see `odinfmt.bat` / `odinfmt.sh`). OLS is
  recommended when editing Odin code.
- Recipes run under `bash` everywhere except Windows, where they run under Windows PowerShell
  (`powershell.exe -NoLogo -NoProfile -Command`). PowerShell 5.1 ships with Windows, so there is nothing to install;
  `-NoProfile` keeps recipes reproducible by stopping a developer's profile from redefining an alias a recipe uses.
  See [configuring the just shell](https://just.systems/man/en/chapter_63.html?highlight=set%20shell#configuring-the-shell)
  to change it.
- The two recipes that cannot be written once for both shells — `mktarget_dirs` and `clean` — are split with just's
  `[unix]` / `[windows]` attributes. PowerShell has no `rm -rf` (`rm` is an alias for `Remove-Item`, which rejects
  `-rf`), and uses `New-Item -ItemType Directory -Force` as its idempotent `mkdir -p`. Everything else is
  shell-agnostic: the recipes invoke `odin`, `just` and `odinfmt` directly rather than leaning on shell builtins.


<!-- >>> skeleton-only -->
## Installing odin-skel

`odin-skel` is a single binary that scaffolds a new project. The whole template is compiled into it, so it needs
no network access, no git clone, and no copy of this repository.

Download the binary for your platform from the
[latest release](https://github.com/enerqi/odin-lang-skeleton/releases/latest), rename it to `odin-skel`
(`odin-skel.exe` on Windows) and put it somewhere on your `PATH`.

| platform | asset |
| --- | --- |
| Linux x86-64 | `odin-skel-linux-x86_64` |
| Windows x86-64 | `odin-skel-windows-x86_64.exe` |
| macOS Apple silicon | `odin-skel-macos-arm64` |
| macOS Intel | `odin-skel-macos-x86_64` |

On Linux and macOS the downloaded file needs the executable bit:

```
chmod +x odin-skel
```

The binaries are **not code-signed**, so the first run needs an extra step on macOS — Gatekeeper quarantines
anything downloaded from a browser:

```
xattr -d com.apple.quarantine odin-skel
```

Windows SmartScreen may show a "Windows protected your PC" prompt for the same reason; *More info → Run anyway*.
Verify what you downloaded against `SHA256SUMS` on the release page if you would rather not take that on trust.

Then:

```
odin-skel doctor      # check odin / just / odinfmt / git are present and new enough
odin-skel new ../my-project
odin-skel help        # full usage
```

`odin-skel` only scaffolds. The generated project is driven by `just`, and `odin-skel` does not need to stay
installed afterwards.

### Cutting a release

Releases are built by `.github/workflows/release.yml` on any version tag, for all four targets. Both `v0.1.0` and
a bare `0.1.0` work — `v` is the more common git convention, but [SemVer](https://semver.org/) is explicit that the
`v` belongs to the tag rather than the version, so it is stripped before stamping and the binary reports `0.1.0`
either way:

```
git checkout master && git merge <branch>   # the tag must include the workflow
git push origin master
git tag v0.1.0
git push origin v0.1.0
```

Each target runs `embed-check` and the tool's tests, builds with `-define:SKEL_VERSION=0.1.0` (the tag without
its leading `v`), and asserts the binary reports that exact version before it is published. The workflow can also
be run from the Actions tab via *workflow_dispatch* to exercise the matrix without tagging: those builds are
stamped `dev-<sha>` and are not published.

**Add a `CHANGELOG.md` section before tagging.** The release notes are that section followed by GitHub's
auto-generated pull-request list. Since most work here lands by pushing to `master` rather than through pull
requests, the generated half is close to empty, so the changelog is where the actual summary lives. A tag with no
matching section fails the release rather than publishing empty notes — check what will be used with:

```
just changelog_section 0.1.0
```

Move the `## [Unreleased]` entries into a new `## [x.y.z] - YYYY-MM-DD` heading as part of the release commit.

<!-- <<< skeleton-only -->

<!-- >>> skeleton-only -->
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


<!-- <<< skeleton-only -->
## [Sublime Text](https://www.sublimetext.com/) editor specific files

The `OdinJustTarget.sublime-build` file is an example [sublime build file](https://www.sublimetext.com/docs/build_systems.html). Delete it if no developer is using sublime text.
The `Odin.sublime-build` file is similar but doesn't assume you have `just` installed.
Same for the very basic `.sublime-project` file.

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

If instead you want a **project-local** build system — one that only shows up when this project is open and needs no
global install — Sublime reads it from the `"build_systems"` key inside the `.sublime-project` file (loaded
automatically when you open the project). `just sublime-build-init` seeds that key with one working `just run` build plus
commented-out variant examples (release / test / lint / current-file) for you to extend; it refuses if the project
file already has a `build_systems` entry. (`.sublime-project` is loose JSON — `//` comments and trailing commas are
allowed.)

<!-- >>> skeleton-only -->
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
`main_program` body, the `#config` defaults, the executable names). Recipes fenced by `# >>> name` / `# <<< name`
markers in the `justfile` are stripped from the Justfile snippet. Two marker names are used: `skeleton-only` (e.g.
`new`, `snippets` — meaningless outside this repo, so `just new` also drops them) and `snippet-exclude` (e.g.
`sublime-build-init` — kept by `just new` but left out of the snippet because it contains literal `$` that Sublime would
otherwise parse as snippet fields).
<!-- <<< skeleton-only -->


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
