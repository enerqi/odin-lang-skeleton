# Odin Programming Language Project Skeleton

A minimal project skeleton for the [Odin programming language](http://odin-lang.org/)

<!-- >>> skeleton-only -->
> **Reading this on GitHub?** This file is the template that both executable projects and library projects are
> scaffolded from, so it shows **both views at once**: wherever the executable and library shapes differ, you will see
> the two paragraphs one after the other. A scaffolded project's README keeps only the one that applies to it. Each
> says which kind it is describing, so a pair that looks contradictory here is two answers to the same question, not
> one wrong one.
<!-- <<< skeleton-only -->

<!-- >>> exe-only -->
**An executable project** outputs its build artifacts under the `target` directory (similar to
[Rust](https://www.rust-lang.org/) projects built using `cargo`).
<!-- <<< exe-only -->
<!-- >>> lib-only -->
**A library project** is an Odin source package with nothing to build, so nothing is output under `target`. See
[Library layout](#library-layout).
<!-- <<< lib-only -->

<!-- >>> skeleton-only -->
- [Quick start](#quick-start) — the two ways in: clone this repository, or stamp out a project without cloning
- [Installing odin-skel](#installing-odin-skel) — get the binary that does the stamping
- [Creating a new project](#creating-a-new-project) — `new` and its flags, and what it rewrites rather than copies
<!-- <<< skeleton-only -->
<!-- >>> lib-only -->
- [Library layout](#library-layout) — why the repository root is the package, and the constraints that follow from it
<!-- <<< lib-only -->
- [Tasks](#tasks) — every `just` recipe, grouped by what you are trying to do
- [Pinned tooling](#pinned-tooling) — why `odinfmt` and `ols` are fetched by version rather than taken from `PATH`
- [Some recipes need uv](#some-recipes-need-uv) — why a few recipe bodies are Python, and the one tool that needs installing
- [Choosing a linker](#choosing-a-linker) — four values, what each costs, and when the default is the wrong one
<!-- >>> exe-only -->
- [Build-time options](#build-time-options) — the `-define` switches: tracking allocator, spall tracing, log level
<!-- <<< exe-only -->
- [Timing a recipe](#timing-a-recipe) — `just --time`, and hyperfine when it is the program you want timed
- [Benchmarking](#benchmarking) — the opt-in `bench/` harness, and where its documentation lives
- [Sublime Text editor specific files](#sublime-text-editor-specific-files) — build systems and snippets, installed once for every project
- [Language Server Configuration](#language-server-configuration) — `ols.json`, resolving imports from outside the project, and what OLS treats as the project root
<!-- >>> skeleton-only -->
- [Skeleton maintenance](#skeleton-maintenance) — regenerating the snippets and templates, and cutting a release
<!-- <<< skeleton-only -->

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

<!-- >>> skeleton-only -->
## Installing odin-skel

`odin-skel` is a single binary that scaffolds a new project. The whole template is compiled into it, so it needs
no network access, no git clone, and no copy of this repository.

### Linux and macOS

```
curl -fsSL https://raw.githubusercontent.com/enerqi/odin-lang-skeleton/master/packaging/install.sh | sh
```

Installs into `~/.local/bin`, which is already on `PATH` on most systems; the script tells you what to add if it
is not, and does not edit your shell profile. It verifies the download against the published `SHA256SUMS`.
Override with `ODIN_SKEL_INSTALL_DIR=/usr/local/bin` or `ODIN_SKEL_VERSION=0.1.2`. Read it first if you would
rather not pipe a script into a shell — it is short, and the manual route below does the same thing.

### Windows

```
scoop install https://github.com/enerqi/odin-lang-skeleton/releases/latest/download/odin-skel.json
```

[Scoop](https://scoop.sh/) puts it on `PATH` and handles `scoop update odin-skel` and `scoop uninstall odin-skel`.
Installing a manifest by URL like this does not need a custom bucket. The manifest is published as a release asset
with the version and hash already filled in, and `releases/latest/download/…` always resolves to the newest
release, so the command above never goes stale.

### Manually, any platform

Download the archive for your platform from the
[latest release](https://github.com/enerqi/odin-lang-skeleton/releases/latest) and extract it. Each one contains
the binary already named `odin-skel` (`odin-skel.exe` on Windows) plus the licence — put the binary somewhere on
your `PATH`.

| platform | asset |
| --- | --- |
| Linux x86-64 | `odin-skel-linux-x86_64.tar.gz` |
| Windows x86-64 | `odin-skel-windows-x86_64.zip` |
| macOS Apple silicon | `odin-skel-macos-arm64.tar.gz` |
| macOS Intel | `odin-skel-macos-x86_64.tar.gz` |

```
tar xzf odin-skel-linux-x86_64.tar.gz     # the executable bit is preserved, no chmod needed
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
odin-skel doctor      # check odin / just / odinfmt / git / uv / hyperfine, and say which are optional
odin-skel new ../my-project
odin-skel help        # full usage
```

`odin-skel` only scaffolds. The generated project is driven by `just`, and `odin-skel` does not need to stay
installed afterwards.

<!-- <<< skeleton-only -->

<!-- >>> skeleton-only -->
## Creating a new project

`just new DEST [NAME]` copies this skeleton into a new or empty directory `DEST` (a `.git/` already present is fine —
usually it was just `git init`-ed; any other content makes it refuse). `NAME` defaults to the `DEST` directory name.

A scaffold finishes by running the *new project's own* `just bump-ols` and `just fetch-ols`: the ols pin the
templates carry is as old as the last `odin-skel` release, so without this a new project starts several releases
behind and the first person to bump it takes a reformatting diff across files nobody edited. **If the bump actually
moved the pin, `just format` runs too** — the files were written from templates formatted by whatever odinfmt the
*skeleton* pinned, so without it that same reformatting diff just reappears on your first `format`, against files
you never wrote and after there is history to review it against. A fresh scaffold is the cheapest possible place
to absorb it. All three steps only warn on failure — the files are written and correct by then, and each warning
names the one command that fixes it.

Two ways to opt out, because they are different wishes:

* `--no-bump` keeps the pin the templates ship with, and still installs it. For a pin you chose on purpose:
  `/releases/latest` is *the release GitHub marks latest*, which these date-shaped tags do not order, so a bump can
  move a hand-picked pin backwards.
* `--offline` skips the whole step — no API call, no download, no format. Everything before it is purely local, so
  an offline scaffold is still a complete one.

See [Pinned tooling](#pinned-tooling).

Add `--linker=VALUE` (`default`, `lld`, `radlink` or `mold`) to pin the new project's linker for every platform
instead of inheriting the per-OS default — see [Choosing a linker](#choosing-a-linker).

Add `--lib` to scaffold a **library** rather than an executable — an Odin source package a consumer clones or copies
into their own tree, with the destination directory as the package itself and examples under `examples/`. They import
it by the path they put it at, or mount that directory as a collection (`-collection:libs=libs`) and import it by
name; which of the two is the consumer's choice, not something the library declares. See
[Library layout](#library-layout).
The package name is derived from `NAME` by turning `-`, `.` and spaces into underscores (`odin-toml` → `odin_toml`),
since a directory name is not always a legal `package` clause; `--pkg=NAME` overrides it. A library project gets
`just check`, `just example NAME`, `just examples-check` and `just doc` in place of the `run_*` / `rerun_*` build ladder,
which has nothing to build.

```
odin-skel new ../odin-toml --lib               # package odin_toml
odin-skel new ../odin-toml --lib --pkg=toml    # package toml
```

[Library layout](#library-layout) below describes what `--lib` produces and the constraints that come with it —
worth reading before you pick this over an executable. Without `--lib` you get the executable layout this
repository itself is in: a `main` package at the root, built to `target/`.

Only git-tracked files are copied, so build artifacts, `.git/` and untracked local files are left behind. A few things
are rewritten rather than copied verbatim:

* the `.sublime-project` file is renamed to `NAME.sublime-project`
* the skeleton's [Unlicense](https://unlicense.org) `LICENSE` is replaced with a fresh [Zlib](https://opensource.org/license/zlib)
  `LICENSE` (matching the Odin project's own license)
* the `justfile` is emitted without its `# >>> skeleton-only` recipes (`new`, `snippets`, `snippets-check`) — those
  only maintain this skeleton, not a real project. `README.md`, `.gitattributes` and the justfile's `.just/` recipe
  fragments carry the same markers and get the same treatment: the README sections documenting those recipes, the
  `linguist-generated` rules naming `tools/`, which a scaffolded project never receives, and the fragments' own
  header notes
* the justfile's `linker` default is rewritten when `--linker` is passed

The `.sublime-snippet` files are copied so you stay aware of them, but treat them as a one-off starting point (the
generator that keeps them in sync stays behind — see [Generated editor snippets](#generated-editor-snippets)).

### Optional features

Some things are deliberately left out of a scaffold and added on request, to either project kind:

```
odin-skel add bench             # in the project directory
odin-skel add bench ../my-game  # or somewhere else
```

| feature | adds |
| --- | --- |
| `bench` | `bench/` — a benchmark harness, your benchmarks, and the `just bench*` recipes. See [Benchmarking](#benchmarking) |

The reason they are opt-in is bulk, not capability: the benchmark harness is several hundred lines of statistics
that most projects never open, and a skeleton is worth what a reader can hold in their head.

Nothing needs editing to install one. The generated justfile already carries `import? 'bench/bench.just'` — an
*optional* import, so it does nothing until the directory exists, and `just --list` is clean either way. The
feature's recipes ship inside the feature. Removing it is `rm -rf bench/`.

### Keeping a project's boring files in sync

The files a project never edits fall behind the skeleton, and copying them across by hand is the kind of chore that
does not get done. `odin-skel sync` overwrites them from the binary's own templates:

```
odin-skel sync                  # in the project directory
odin-skel sync ../my-game       # or somewhere else
odin-skel sync --check          # exit 1 if anything has drifted, write nothing (for CI)
odin-skel sync --dry-run        # list what would change, write nothing, exit 0
```

Six files, and only these:

| file | |
| --- | --- |
| `.editorconfig` | tabs, LF, final newline |
| `.gitattributes` | `eol=lf` everywhere, binary and linguist rules |
| `.gitignore` | build artifacts per platform |
| `.just/editor.just` | the Sublime and OLS setup recipes |
| `.just/toolchain.just` | the pinned-tool recipes — **your `ols_tag` / `ols_sha256` pin is kept**, see below |
| `odinfmt.json` | line width and newline style |

A file the project does not have yet is *created*, so a project scaffolded before a template existed picks it up.

**Your `justfile`, `README.md`, `LICENSE`, your source and the `.sublime` files are never touched.** Those either
carry your work or carry this project's own name, and none of them can be reproduced from the destination directory:
the justfile has whatever `--linker` you scaffolded with plus every recipe you have added since, the README has your
H1 and your prose, LICENSE has a year, and `.sublime-project` is named after the project. `--only=PATHS` narrows a
sync to a comma-separated subset; naming a file that is deliberately not syncable is an error rather than a silent
no-op.

Four things stand between a sync and losing work:

* **This repository itself is refused outright**, `--force` included. Its copies of these files are the
  *unstripped* originals, marker blocks and all, so writing the rendered versions back would delete the very text
  scaffolding reads. Every other guard would wave it through — the files are committed and there is Odin source
  everywhere — so it is checked by name.
* **The destination has to look like an Odin project** — a justfile *and* `.odin` source somewhere under it, at any
  depth. A justfile alone is weak evidence, since `just` is a general-purpose runner; the check is what stops a sync
  run in the wrong terminal tab from replacing an unrelated project's `.editorconfig` and `.gitignore`.
* **The ols pin is carried over, not overwritten.** `.just/toolchain.just` holds `ols_tag` and `ols_sha256`, which
  `just bump-ols` rewrites — live project state, and newer than the binary's copy whenever anybody has run it. A sync
  reads your two lines out of your file and splices them into the new one, so it can never undo a bump or move a
  hand-picked pin backwards. `--pin=template` takes the binary's pin instead; if either file is missing a pin line
  the sync fails rather than guessing. See [Pinned tooling](#pinned-tooling).
* **git is the undo.** Every file that would be *changed* is checked with `git status`, and a modified, untracked or
  ignored one refuses the sync — commit or stash first, and the sync becomes a diff you can read and revert. A
  directory git knows nothing about gets a warning and proceeds: having no history at all is your choice and applies
  to your whole tree, where an uncommitted edit to exactly the file being replaced is a specific thing about to be
  destroyed. `--force` skips both this and the Odin-source check.

A sync only ever delivers what *that binary* has, so it reports its own version in the output — an old `odin-skel`
will happily sync a project backwards.


<!-- <<< skeleton-only -->

<!-- >>> lib-only -->
## Library layout

A library is laid out differently from the executable skeleton: there is no `main`, nothing lands in `target/`, and
**the repository root is the package.** That is the layout the surrounding Odin ecosystem uses. A consumer either
vendors the library into their own tree, or keeps the checkout outside the project and points a collection at it.

Vendored — they clone or copy the directory in, frequently renaming it on the way, and import it by path:

```
git clone <the library repo> libs/toml     # the directory name they pick becomes the import path
```

```odin
import "libs/toml"                  # or through a collection: -collection:libs=libs, then import "libs:toml"
```

Out of tree — the collection points *at the library root itself*, and the root package is imported as `.`:

```
-collection:toml=../checkouts/odin-toml
```

```odin
import toml "toml:."                // "toml:sub" for a subpackage
```

That keeps the checkout shared between projects and updatable with a `git pull`, with nothing copied into the
consumer's tree. Note the explicit `toml` name: the import name is still derived from the resolved directory, so a
checkout named `odin-toml` needs naming here for the same reason the examples in this repository do (below).

```
.
├── <pkg>.odin           <- the package; add more files beside it
├── <pkg>_test.odin
├── examples/
│   └── basic.odin       <- package main, built with -file
└── justfile  .just/  README.md  ...
```

**The package name must be a valid Odin identifier**, which a repository name often is not: `odin-toml` is a fine
directory name and an illegal `package` clause. Scaffolding a library derives one by turning `-`, `.` and spaces
into underscores, and `--pkg=NAME` overrides it.

**Examples are single-file `main` packages**, built with `-file` so several can share `examples/` without their
`main` procedures colliding. In `-file` mode a relative import resolves against the file's own directory, so an
example imports `".."` — one level, not two. Get it wrong and Odin reports
`Syntax Error: Empty directory that contains no .odin files: ../..`, which names the path but not the reason.
`just examples-check` type checks all of them, which is what stops an API change from quietly invalidating the docs.

**Tests live in the package**, as `<pkg>_test.odin` beside the source, so they can reach `@(private)` symbols. The
cost is that a consumer building the package also builds `import "core:testing"`, and optimization does not remove
it: the `@(test)` bodies are eliminated, but `core:testing`'s transitive `@(init)`/`@(fini)` procedures are entry
points and stay live. Measured on `-o:speed`, that is up to ~8.6 KB against a consumer importing nothing else from
`core`, and ~80 bytes against one already using `core:log` — nearly all of the cost is overlap with packages a real
program links anyway. If it matters (a freestanding or WASM consumer, say), move the tests into a `tests/` package
that imports this one, the way Odin's own `core` does.

**Growing past one package**: add subdirectories, each its own package, and keep the root package as the entry
point. `odin check .` only ever covers the root package and there is no whole-tree `check`, so once there are
subpackages, add an aggregator example that names them all:

```odin
package all

@(require) import lib ".."
@(require) import "../sub"
```

`just examples-check` then type checks the whole tree through it. Two things are load-bearing here:

* `@(require)` — without it an unreferenced import is dropped and the check passes vacuously
* the explicit `lib` name on the `".."` import. Odin derives an import's name from its directory, and a
  repository directory is often not a valid identifier: from a checkout named `odin-toml` a bare
  `import ".."` fails with `Import name 'odin-toml' is not a valid identifier`. The same applies to the
  examples themselves, which is why `basic.odin` imports `lib ".."`

**Tag your releases.** Odin has no package manager, so a consumer pins you by git tag or by whatever
revision they happened to copy. A tag is the only thing that lets them say which version they have, and
the only way you can change an API without breaking whoever vendored you last month. Nothing here
automates that — a `CHANGELOG.md` and a tagging habit are yours to add if you want them.

<!-- <<< lib-only -->
## Tasks

A `justfile` is part of this opinionated setup and you may need to edit the tasks as new packages are added in
sub-directories. [Just >=1.49](https://just.systems/) is a CLI task runner that you *need to install*. Run any task
with `just TASK`:

The recipes are split across three files, which changes nothing about how you run them — an imported recipe keeps its
group and lists under it, so `just --list` shows one flat set:

| file | holds |
|---|---|
| `justfile` | the build, test, lint, `format` and housekeeping recipes — what you edit as the project grows |
| `.just/toolchain.just` | the pinned `ols` / `odinfmt` machinery: `fetch-ols`, `bump-ols`, `ensure-odinfmt`, and the pin itself |
| `.just/editor.just` | one-off editor setup: `install-sublime`, `sublime-build-init`, `sublime-lsp-init`, `ols-config` |

The two `.just/` files are *mandatory* imports (`import`, not the `import?` that brings in an optional feature), so
deleting one is an error rather than recipes quietly disappearing. All three share one namespace: a fragment sees
`linker` and `target_path` from the justfile, and vice versa.

<!-- >>> exe-only -->
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
<!-- <<< exe-only -->

<!-- >>> lib-only -->
**Build & check** — a library has no binary of its own, so there is no build ladder. The inner loop is a type check,
and the examples are what prove the package is usable from outside it:

* `just check` — type check the library. The fast "does it still compile" pass, without the vet and style flags
  `just lint` carries
* `just example NAME` — build and run `examples/NAME.odin`
* `just examples-check` — type check every example, so an API change cannot quietly invalidate the documentation
* `just doc` — print the package documentation (`odin doc .`)
<!-- <<< lib-only -->

**Benchmarks** — present only once `bench/` is, which it is not by default: it is an opt-in feature, added with
`odin-skel add bench`. See [Benchmarking](#benchmarking):

* `just bench [NAME] [--samples=N …]` — build and run the benchmarks; `NAME` filters by substring
* `just bench_build` / `just rerun_bench` — build without running / run without rebuilding
* `just bench_lint` — type check and vet `bench/`, which the root `lint` does not reach
* `just bench_save` / `just bench_cmp` — record a timing baseline / re-run and diff against it
* `just bench_count` / `just bench_count_check` — the same for *instruction counts* under callgrind,
  which do not drift between runs and can therefore gate a merge (needs valgrind)

**Quality:**

* `just lint` — type checking, vet warnings, strict style. No code generation
* `just format` — runs the pinned `odinfmt -w .` over the whole tree, fetching it first if needed
* `just fetch-ols` — install the pinned `ols` + `odinfmt` into `~/.odin-tools` (`--check` / `--force`)
* `just bump-ols [TAG]` — rewrite the pin in `.just/toolchain.just` to the latest (or named) ols release (`--check`)
* `just test` / `just test1 NAME` — run all tests / one named test
<!-- >>> exe-only -->
* `just sanitize [KIND]` — the same, but running the program rather than the tests
<!-- <<< exe-only -->
* `just test_sanitize [KIND]` — run the tests under a sanitizer. `KIND` is
  `address` (default), `memory` or `thread`. Only `address` is widely supported; `memory` and `thread` need a
  clang-ish toolchain and are unavailable on some platforms (notably Windows/MSVC).

  **On Windows, `address` catches stack errors but not heap errors** — a clean run there does not mean your
  heap is clean. Odin allocates through `HeapAlloc` rather than `malloc` on Windows, and ASan's redzones come
  from intercepting the allocator, so it never sees the allocation. Verified by overflowing a 16-byte
  allocation at +24, +32, +64 and +256 bytes: Linux reports `heap-buffer-overflow` at every one, Windows at
  none. The `interception_win: unhandled instruction` line these builds print is that limitation, not a fault
  in your code. Chase a suspected heap bug on Linux, or with a tracking allocator, which does not rely on ASan.

  On Linux the sanitizer runtime is a separate install — without it the link fails on a missing
  `libclang_rt.asan.a`. On Debian/Ubuntu with clang 21 that is `libclang-rt-21-dev`.

**Housekeeping:**

* `just clean` — wipe the `target` directory
* `just mktarget_dirs` — create the `target` directory tree (auto-called by every task that builds)

**Editor setup** (these four run on Python via [uv](https://docs.astral.sh/uv/) — see
[Some recipes need uv](#some-recipes-need-uv)):

* `just ols-config NAME=PATH...` — (re)generate the `ols.json` collection list (see [Language Server Configuration](#language-server-configuration))
* `just install-sublime` — install the snippets + build systems into Sublime Text's global config (see the Sublime section)
* `just sublime-build-init` — add a project-local build-system stub to the `.sublime-project` (see the Sublime section)
* `just sublime-lsp-init` — point the project's Sublime LSP client at the pinned `ols` (see [Pinned tooling](#pinned-tooling))

<!-- >>> skeleton-only -->
**Skeleton upkeep** (these recipes maintain the skeleton repository itself and are stripped from a
scaffolded project):

* `just new DEST [NAME]` — copy this skeleton into a new project (see [Creating a new project](#creating-a-new-project))
* `just snippets` / `just snippets-check` — (re)generate / verify the editor snippets (see [Generated editor snippets](#generated-editor-snippets))
* `just embed` / `just embed-check` — (re)generate / verify the template list compiled into `odin-skel`
* `just build_skel` / `just build_skel_release` / `just lint_skel` / `just test_skel` — build, lint and test the
  `odin-skel` binary
<!-- <<< skeleton-only -->

Notes:

<!-- >>> exe-only -->
- **Executable:** all `run_*`, `rerun_*`, `test*` and `diagnose` tasks accept optional extra variadic arguments; add
  `--` before passing arguments to your own program. Edit the `main_name` / `test_main_name` output executable names
  as needed.
<!-- <<< exe-only -->
<!-- >>> lib-only -->
- **Library:** `check`, `test*`, `example` and `doc` accept optional extra variadic arguments; add `--` before
  passing arguments to an example's own `main`. Edit the `test_main_name` output executable name as needed.
<!-- <<< lib-only -->
- `format` does **not** use an `odinfmt` on your `PATH` — it fetches a pinned one and runs that. See
  [Pinned tooling](#pinned-tooling).
- Recipes run under `bash` everywhere except Windows, where they run under `cmd.exe /c`. just launches a shell per
  recipe *line*, so shell startup is a fixed tax on every build, and cmd is the cheapest thing that is on every
  Windows: ~9ms to start, against ~143ms for `powershell -NoLogo -NoProfile -Command` (which it replaced) and ~41ms
  for `nu -c`. It also has no profile to make a recipe unreproducible. The cost is that cmd is a poor language for
  anything with logic — which does not bite here, because every Windows recipe body is a single command and
  everything else uses `[script]` (see [Some recipes need uv](#some-recipes-need-uv)). See
  [configuring the just shell](https://just.systems/man/en/chapter_63.html?highlight=set%20shell#configuring-the-shell)
  to change it.
- The two recipes that cannot be written once for both shells — `mktarget_dirs` and `clean` — are split with just's
  `[unix]` / `[windows]` attributes. cmd spells `rm -rf target` as `if exist target rmdir /s /q target`, and has no
  `mkdir -p`, so the directories are created with `for %d in (...) do @if not exist target\%d md target\%d`.
  Everything else is shell-agnostic: the recipes invoke `odin`, `just` and `odinfmt` directly rather than leaning on
  shell builtins.


## Pinned tooling

`odinfmt` is not interchangeable across versions. It ships inside an [ols](https://github.com/DanielGavin/ols)
release, has **no `--version` flag**, and two releases format the same source differently. So a copy on `PATH` tells
you nothing about which one it is, and the failure mode is a developer running `just format`, getting a clean local
tree, and failing a CI diff on files they never touched.

`.just/toolchain.just` therefore pins the ols release and formats with that copy:

```
ols_tag    := "dev-2026-06"
ols_plat   := ...    # the release asset for this OS/arch
ols_sha256 := ...    # that asset's published digest, per platform
```

`just fetch-ols` downloads `ols-<platform>.zip`, checks it against `ols_sha256` **before** extracting anything, and
installs all three things the archive holds:

```
~/.odin-tools/ols/dev-2026-06/
    ols(.exe)         the language server
    odinfmt(.exe)     the formatter `just format` runs
    builtin/          the package ols resolves beside its own executable, and errors without
```

The tag is *in the path*, so the file being there is the pin being satisfied — there is no state where the right
path holds the wrong binary, which a single unversioned `~/.odin-tools/odinfmt` would reintroduce the first time the
pin moved. Several tags coexist, so switching branches switches formatter with no re-download. The root is
`$ODIN_TOOLS` if set, else `~/.odin-tools` — outside the repository, because one copy serves every checkout and
worktree, it survives `just clean`, and it needs no `.gitignore` line.

* `just format` depends on `ensure-odinfmt`, which installs on first use. You never call `fetch-ols` by hand.
* `just fetch-ols --check` exits non-zero when the install is missing or incomplete and downloads nothing — for CI.
* `just fetch-ols --force` reinstalls over an existing directory. Close any editor running `ols` first: Windows
  refuses to replace a directory holding a running executable, and the recipe says so rather than half-installing.
* Extraction goes to a `.part` directory that is renamed into place, so an interrupted run leaves either nothing or
  a finished install — necessary, because the existence test above never re-hashes anything.
* `ODINFMT=odinfmt just format` opts out of the pin and uses `PATH` — the guard skips the download when it is set.
  Pointing the editor at the pinned server is opt-in, so forcing the formatter with no way out would be the odd
  one of the pair. The pin is the default because unpinned is the failure above; it is not a cage.

A freshly scaffolded project arrives with the pin already brought up to date and the tools installed — scaffolding
runs the two recipes below for you, warning rather than failing if either cannot. So the commands here are the ones
for keeping an existing project current.

**Bumping the pin.** `just bump-ols` reads the latest release from GitHub's API and rewrites `ols_tag` and all
five digests in `.just/toolchain.just` for you — copying six values by hand is where a wrong pin comes from:

```
just bump-ols                 # rewrite the pin to the latest release
just bump-ols dev-2026-07     # ... to a named release instead
just bump-ols --check         # is there a newer one? changes nothing, exits non-zero if so
just fetch-ols --force        # install it; the digests just written are checked on the way in
just format                   # review this diff - see below
```

Run by hand it edits `.just/toolchain.just` and stops: no fetch, no format, no commit — reviewing that reformatting
diff before it lands in a commit is the point. (Scaffolding a project is the one exception: a brand new tree has no
diff worth reviewing, so a scaffold that moves the pin formats with it straight away.)
`/releases/latest` skips prereleases, which is
what keeps the continuously re-cut `nightly` tag out of it — a moving tag cannot be hash-pinned. Digests come from
the API's per-asset `digest` field; an older release without one is downloaded and hashed instead.

Expect to do this fairly often. ols vendors its own copy of the Odin parser, and Odin is pre-1.0 and moving, so a
pin left far behind your compiler will fail to parse code the compiler accepts. A digest that does not match is a
hard failure rather than an install: a re-cut tag has to be adopted deliberately, which is the whole point.

**Pointing the editor at the same ols.** `just sublime-lsp-init` writes the pinned server's path into the
`.sublime-project` file:

```json
"settings": {
    "LSP": {
        "odin": { "command": ["$home/.odin-tools/ols/dev-2026-06/ols.exe"] }
    }
}
```

Sublime's LSP client merges this over the global `clients.odin` config *per key*: `command` is replaced outright,
while `initializationOptions` is deep-merged — so whatever `enable_*` flags you have set globally still apply, and
windows without this project keep using the global server. Sublime expands `$home` in `command`, so the file stays
identical on every machine and can be committed; it does **not** expand environment variables there, so a custom
`$ODIN_TOOLS` root has to be written out in full. Re-run the recipe after bumping `ols_tag` (it refuses to
overwrite, so delete the `"LSP"` key first).

Nothing in the justfile runs `ols` — the language server is the editor's business. Pinning it costs one extra file
from an archive already downloaded, and it means the analysis you see and the formatting you commit come from the
same release.

The Odin compiler itself is deliberately *not* pinned: pre-1.0 it moves fast enough that pinning would cost more
than it saves.


## Some recipes need uv

`fetch-ols`, `bump-ols`, `ols-config`, `install-sublime`, `sublime-build-init`, `sublime-lsp-init` — and `examples-check` in a
library, and `bench_count` / `bench_count_check` once `bench/` is installed — are `[script]` recipes: their
bodies are Python, run through [uv](https://docs.astral.sh/uv/) rather than a bare `python`/`python3` on `PATH`. The
justfile pins this in one place:

```
set script-interpreter := ["uv", "run", "--no-project", "-p", "3.14", "python"]
```

A bare `python` is not a reliable cross-platform lookup — on Windows via [Scoop](https://scoop.sh/) it is whatever
version was last `scoop install`ed with no pin, and on Linux it is whatever the distro shipped. `uv run -p 3.14
python` downloads the interpreter it needs (uv-managed, not the system one) so the same version runs everywhere, and
`--no-project` stops `uv run` from walking up the directory tree looking for an unrelated `pyproject.toml`/`uv.toml`
to treat as a project root.

**`just format` reaches uv indirectly.** It depends on `ensure-odinfmt`, which runs `fetch-ols` — a `[script]`
recipe — when the pinned `odinfmt` is not installed yet. So the *first* `format` on a fresh machine needs uv even
though nothing in the list above was run by hand; every later one does not, the binary being there by then. Two ways
out if you would rather not install uv at all: `ODINFMT=odinfmt just format` uses whatever `odinfmt` is on `PATH`
and skips the download (see [Pinned tooling](#pinned-tooling)), or install the pinned pair by hand into
`$ODIN_TOOLS/ols/<tag>/`.

<!-- >>> exe-only -->
**In an executable project uv is otherwise optional**, unlike `just`: none of the `run_*`/`test*`/`lint` tasks touch
Python, so a project that never runs one of the recipes above — and has its `odinfmt` already installed — never
needs it.
<!-- <<< exe-only -->
<!-- >>> lib-only -->
**In a library uv is needed for `just examples-check`**, and otherwise optional: `check`/`test*`/`lint`/`example`
and `doc` touch no Python, but `examples-check` — the recipe that stops an API change from quietly invalidating the
documentation — is one of these `[script]` recipes, so it is not only an editor-setup concern here.
<!-- <<< lib-only -->
Install from
[docs.astral.sh/uv](https://docs.astral.sh/uv/getting-started/installation/) (or via Scoop: `scoop install uv`) if
you plan to use those recipes.


## Choosing a linker

Odin has no build cache, so it relinks on every build. Which linker does that work is a `linker` variable at the
top of the justfile, passed to every recipe that links:

| value | notes |
| --- | --- |
| `default` | Odin picks — MSVC `link.exe` on Windows. Portable, and the default everywhere except Windows |
| `lld` | LLVM's linker. Windows and Linux. **Not on a stock macOS** — Odin links through clang, and Apple's clang ships no lld, so it fails with `invalid linker name in argument '-fuse-ld=lld'` unless you installed LLVM yourself |
| `radlink` | RAD Debugger's linker. **Windows only**, and bundled with the Odin toolchain, so it needs no install — which is why it is the Windows default here |
| `mold` | **Linux only**, and *not* bundled — `apt install mold` or equivalent first |

Override for a single command without editing anything:

<!-- >>> exe-only -->
```sh
ODIN_LINKER=lld just run
```
<!-- <<< exe-only -->
<!-- >>> lib-only -->
```sh
ODIN_LINKER=lld just test
```
<!-- <<< lib-only -->

To change the default for good, edit that `linker` line in the justfile.

<!-- >>> skeleton-only -->
A new project can also have it pinned at scaffold time, which rewrites that line for every platform:

```sh
odin-skel new ../my-service --linker=mold
```
<!-- <<< skeleton-only -->

Nothing falls back silently, but the two ways a linker can be unavailable fail differently. Odin knows mold is
Linux-only, so asking for it on Windows exits 1 with `'mold' linker is not supported on this platform` before any work
happens. `lld` on macOS gets no such check — Odin accepts the value and clang rejects it further down with
`invalid linker name in argument '-fuse-ld=lld'`. Either way you get exit 1 and no binary, just with more or less
explanation. `ODIN_LINKER` is an environment variable
rather than a recipe argument because `odin` errors on a repeated flag, so a `-linker:` passed through a recipe's extra
args would collide with the one the recipe already adds.

**When the default is the better choice.** Neither radlink nor mold is an *incremental* linker; MSVC `link.exe` is.
Paired with `-use-separate-modules` — which `-lto` implies — an incremental relink of one changed module can beat a
full link that is individually faster. That is not the shape of a stock Odin build, though: single-module builds give
LTO little to work with, and statically linked external C libraries do not get LTO either way. Measure on your own
project before assuming. `-lto` is also a hard conflict rather than a preference — on Windows it *requires*
`-linker:lld` — so reach for the override there:

<!-- >>> exe-only -->
```sh
ODIN_LINKER=lld just run_release -lto:thin
```
<!-- <<< exe-only -->
<!-- >>> lib-only -->
```sh
ODIN_LINKER=lld just test -lto:thin
```
<!-- <<< lib-only -->

<!-- >>> exe-only -->
## Build-time options

`main.odin` carries a few `#config` switches, documented in full where they are declared. Two are
worth knowing before you need them, because they change what a build costs.

**`-define:TRACKING_ALLOCATOR=off|basic|backtrace`** — how allocations are tracked. Defaults to
`basic` in a `-debug` build and `off` otherwise, so leaks are reported in the builds you debug and
nothing is paid in the builds you measure. Measured over 200k allocations:

| value | allocator | per allocation | per live allocation |
| --- | --- | --- | --- |
| `off` | the raw allocator | ~44 ns | — |
| `basic` | `mem.Tracking_Allocator` | ~599 ns | +72 bytes |
| `backtrace` | `trace.Tracking_Allocator` | ~1385 ns | +208 bytes |

`basic` reports leaks and bad frees at the line that called `make`. `backtrace` records a stack per
allocation as well, which is what tells you *which* caller of a shared helper leaked rather than just
naming the helper — worth it during a leak hunt, not before one. Both tracked modes take a mutex on
every alloc and free, so the cost lands on allocation-heavy and multi-threaded code and is close to
invisible for a program that allocates at startup and then works out of arenas. Override in either
direction; `-define:TRACKING_ALLOCATOR=backtrace` on a release build suits a leak that only
reproduces optimized.

**`-define:SPALL_ENABLE=true`** — emit a [spall](https://github.com/colrdavidson/spall-web) profiling
trace to `trace.spall`, viewable in the browser. Off by default and adds a couple of seconds to the
run, so it is a switch you flip for one profiling session rather than leave on.

**`-define:CONSOLE_UTF8=false`** — leave the Windows console codepage alone. On by default on
Windows and a no-op everywhere else. `fmt` writes UTF-8 bytes and `core:os` hands them to `WriteFile`
unconverted, so a console still on the OEM codepage decodes them a byte at a time and `Finished 19
tests in 859.7µs` prints as `859.7┬Ás`. It is an `@(init)` proc rather than a step in `main`, so
`odin test` builds get it too — they take their entry point from `core:testing` and never call `main`,
and the runner's timing summary is where the mojibake usually shows up. The codepage belongs to the
console rather than the process, so `main` restores the previous one on the way out; a test run cannot,
because `core:testing` ends through `os.exit` and reaches no defer, and so leaves the console on UTF-8.

Backtraces on asserts and segfaults need no define — they are on by default and cost nothing until
something actually fails. Set `ODIN_BACKTRACE=0` to silence them for a run. Symbol names and line
numbers come from the debug info, so a `-debug` build gives a readable trace where a release build
prints bare `0x...` addresses.
<!-- <<< exe-only -->

## Timing a recipe

`just --time <recipe>` prints how long the recipe took (`JUST_TIME=true` as an env var; note it wants
`true`, not `1`):

<!-- >>> exe-only -->
```
just --time rerun          ---> rerun_debug completed in 0.159s
```

Time a `rerun_*` rather than a `run_*`. Odin has no build cache, so a `run_*` recipe recompiles every
time and its timing is mostly the compiler — roughly 0.5s of compile against 0.16s of run for a
hello-world here.
<!-- <<< exe-only -->
<!-- >>> lib-only -->
```
just --time test           ---> test completed in 0.412s
```

Odin has no build cache, so every recipe here recompiles and its timing is mostly the compiler. That
makes `just --time` useful for tracking what the *build* costs as the library grows, rather than what
the code costs at runtime.
<!-- <<< lib-only -->

Note that any external measurement includes process startup, which was ~31ms on this machine, so for
sub-second work put `time.now()` / `time.since` around the specific phase you care about instead.

<!-- >>> exe-only -->
For the program itself rather than the recipe, [hyperfine](https://github.com/sharkdp/hyperfine) does
the job properly — warmup runs, mean/σ/min/max, outlier warnings and `--export-json`:

```
just run_release            # build first: Odin has no build cache, so timing a run_* recipe
just time_release           # would mostly be timing the compiler
just time_release --flag=x  # arguments are passed through to the program

just run_release_nochecks   # and to see what the bounds checks actually cost:
just time_profiles          # hyperfine prints the ratio between the two binaries
```

Both use `-N`, which runs the binary directly rather than through a shell — hyperfine warns it cannot
calibrate shell startup accurately below ~5ms, and a small Odin program is well below that. The cost is
that the command line is split on whitespace rather than parsed, so no pipes or quoted arguments
containing spaces.

This still measures whole processes. For per-procedure numbers, see [Benchmarking](#benchmarking).
<!-- <<< exe-only -->

## Benchmarking

**It is not there by default.** The harness is an opt-in feature, installed by `odin-skel` — the binary that
scaffolds these projects — into either project kind, at any point in a project's life:

```
odin-skel add bench             # in the project directory
odin-skel add bench ../my-game  # or somewhere else
```

`odin-skel` is a single binary, published on the
[skeleton's releases page](https://github.com/enerqi/odin-lang-skeleton/releases/latest); the whole feature is
compiled into it, so this needs no network access, and it does not need to stay installed afterwards.
<!-- >>> skeleton-only -->
See [Optional features](#optional-features) for the rest of the `add` story.
<!-- <<< skeleton-only -->

`bench/` holds the harness, your benchmarks, and a `bench.just` carrying the recipes. The justfile's
`import? 'bench/bench.just'` is an *optional* import: it does nothing while the directory is absent, so
the `just bench*` recipes appear the moment it arrives and `rm -rf bench/` takes them away again.

Odin has no `cargo bench`, and `core:time`'s `benchmark()` is a stopwatch — it calls your procedure
once and divides, with no warmup, repeat samples, spread or baseline, so it cannot answer "did this
change make it slower". The harness borrows what makes
[criterion](https://github.com/bheisler/criterion.rs) worth using: a warmup, samples across a ramp of
iteration counts fitted with a robust line, R² and outlier counts to say whether the samples describe
one thing at all, and a Mann–Whitney U test against a saved baseline so a change is called out on a
p-value plus a magnitude threshold rather than a percentage.

**The documentation is [`bench/README.md`](bench/README.md)**, which arrives with the directory — the
statistics and how to read them, the `keep` / `opaque` rules without which `-o:speed` deletes your
benchmark and reports the empty loop, timing baselines and where they stop being trustworthy, and
instruction counting under callgrind for a gate that does not flake. It lives with the feature rather
than here so that a project which never adds the harness never carries its manual either.

### What to use instead, and when

* **hyperfine** for anything at process level — CLI startup, a whole run, comparing build flags. It has
  warmup, statistics and `--export-json`, and its process floor is irrelevant at that scale and fatal
  below it. The executable skeleton wires it up as `just time_release` and `just time_profiles`
* **spall** (`-define:SPALL_ENABLE=true` in the executable skeleton) for *why* something is slow, not
  whether it got slower. It produces a trace to read, not numbers to compare

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

Three `.sublime-snippet` files ship here. Each carries a `tabTrigger` (type it, press Tab) and a `description`, which is
what shows beside the trigger in the completion popup and is how they are listed under Tools → Snippets… — worth knowing,
because a `tabTrigger` only helps somebody who already knows to type it:

| trigger | scope | fills in |
| --- | --- | --- |
| `main` | `source.odin` | the `main.odin` program skeleton — logging, tracking allocator, backtraces. Useful for a quick script file without a `justfile` |
| `odin` | `source.just` | a justfile for an Odin **program** — the build tiers, `test`, `lint` |
| `odinlib` | `source.just` | a justfile for an Odin **library** — `check`, `example`, `examples-check`, `doc`, `test` |

The two justfile snippets exist separately because a justfile is one project kind's justfile; unlike the build systems
below, one copy cannot serve both.

Sublime snippets and build systems are installed **globally**, not per project: Sublime loads everything under its
`Packages/User` folder and offers it (snippets by `tabTrigger` within the matching `scope`; build systems in the
Tools → Build System menu) in all windows. So you install them once and they apply everywhere.

`just install-sublime` does this for you, cross platform — it copies the three `.sublime-snippet` files and the two
`.sublime-build` files into Sublime's `Packages/User` directory (resolved per-OS; override with the `SUBLIME_USER_DIR`
env var if your install is non-standard). The per-project `.sublime-project` file is intentionally not installed.

Because that install is global, the `.sublime-build` files list **both** project kinds' recipes and are copied verbatim
into every scaffolded project — a copy specialised to the project it came from would take the other kind's build
variants away everywhere. A variant naming a recipe your project does not define simply fails if you pick it.

If instead you want a **project-local** build system — one that only shows up when this project is open and needs no
global install — Sublime reads it from the `"build_systems"` key inside the `.sublime-project` file (loaded
automatically when you open the project). `just sublime-build-init` seeds that key with one working `just test` build plus
commented-out variant examples (release / test / lint / current-file) for you to extend; it refuses if the project
file already has a `build_systems` entry. (`.sublime-project` is loose JSON — `//` comments and trailing commas are
allowed.)

`just sublime-lsp-init` writes into the same file, pointing this project's language server at the pinned `ols` —
see [Pinned tooling](#pinned-tooling).


## Language Server Configuration

This is also optional, delete if not needed. As the [Odin language server](https://github.com/DanielGavin/ols) docs
show you can configure OLS settings in ways specific to your editor, often in a global manner - once per all projects.

However, you can also use the `ols.json` file, perhaps to add odin "collections" specific to your project.
This is initially an empty collection list.

If you do need extra collections (so OLS resolves `import "xyz:pkg"` from a directory outside this project), the
`ols-config` just task writes the collection list for you. Each argument is `name=path`:

```sh
just ols-config xyz=../xyz-lib abc=/opt/odin/abc
just ols-config                                   # print what is currently configured
```

The arguments are the *whole* collection list — rerunning replaces it, so there is no add/remove pair of commands
to keep straight. Every other key in `ols.json` (`enable_document_symbols`, `checker_path`, `odin_command` …) is
read back and preserved, so the recipe and hand-editing can coexist.

**Prefer a relative path.** OLS resolves a relative collection path against the project root, so a collection kept
as a sibling checkout (`../xyz-lib`) produces an `ols.json` that is identical on every machine — delete the
`ols.json` line from `.gitignore` and commit it. An absolute path is machine-specific, which is why the skeleton
ignores the file by default and each developer regenerates it after cloning. A leading `~` is expanded, but on
Linux and macOS only; on Windows write the path out in full.

`ols.json` itself is plain JSON with no variable substitution — OLS does not expand environment variables in
collection paths — which is why a recipe generates the file rather than the file reading `XYZ_HOME` itself.

### What "the project root" means to OLS

Everything above depends on one directory: `ols.json` is read from it, relative collection paths resolve against
it, and a profile's `checker_path` is joined to it. That directory is **not** discovered by searching upwards from
the file being edited. The editor tells the server what it is, once, and OLS keeps it for the life of the process
(`workspace_folders[0]` at `initialize`). Worth knowing before grouping several checkouts into one window.

For Sublime Text with the [LSP](https://github.com/sublimelsp/LSP) package, the rules are:

* **One server process per window**, not per folder, and it handles every `.odin` file in that window — including
  files in a folder it is not rooted at, and files belonging to no folder at all.
* **The root is the folder containing whichever `.odin` file started the server.** LSP sorts the window's folders
  so the ones containing that file come first (deepest match first) and hands the first one over as `rootUri`.
* **Adding or removing folders later does not re-root it.** OLS does not advertise the workspace-folders
  capability, so LSP never sends the notification. `LSP: Restart Server` re-runs `initialize` and re-roots to
  whatever file is active then — an escape hatch, not a fix.
* **A `.sublime-project` file inside one of the folders is never read.** A window has exactly one project; a
  project file sitting in a subfolder is just a file on disk.

If you are coming from Visual Studio the analogy is close enough to mislead:

| Visual Studio | Sublime + LSP |
| --- | --- |
| `.sln` | `.sublime-project` — one per window, groups roots, carries the settings |
| solution folder (organisational only) | an entry in `"folders"` — this is what a folder actually is |
| `.csproj`: own settings, own references, own build | **no equivalent** |
| language service re-evaluates per project as you navigate | one server, one root, chosen at startup |

There is no per-project layer: a folder carries no settings, no references and no identity. So a Sublime project
is closer to a `.sln` containing exactly *one* `.csproj` than to a solution of several. Group five repositories
into one window and you do not get five projects — you get one, whose root is decided by the first file you open.

**So: one window per Odin project.** If you do want them together, make the containing directory the window's
single folder and register each sub-repository as a collection with `just ols-config`. That is the shape OLS
models — one project with several collections, like one `.csproj` referencing several libraries — and it is
deterministic where a folder-per-repository window is not.

Opening a bare directory (`subl -n thedir`, no project file) is a milder version of the same thing. The window
still has a folder, so `rootUri` is that directory and `thedir/ols.json` is read normally; what is missing is the
`.sublime-project` file, and with it any per-project override of the global LSP client settings. Opening a lone
file with no folder at all leaves the root empty, and then no project `ols.json` is read at all — only the global
editor configuration applies.

<!-- >>> skeleton-only -->
## Skeleton maintenance

These last two sections maintain this skeleton repository itself, not a project built from it, so
`just new` strips them along with the recipes they document.

### Generated editor snippets

`just new` copies the `.sublime-snippet` files into a new project so you stay aware of them, but strips the
snippet-generator recipes from the copied justfile (they only maintain this skeleton) — once detached, treat the copied
snippets as a one-off starting point rather than something kept in sync.

All three snippets are **generated** from `main.odin` and the justfile (their single source of truth) so they cannot
silently drift out of date:

* `just snippets` regenerates `.sublime/Odin-skeleton.sublime-snippet`, `.sublime/Just-Odin.sublime-snippet` and
  `.sublime/Just-Odin-lib.sublime-snippet`. Run it after editing `main.odin`, the `justfile` or either `.just/`
  fragment.
* `just snippets-check` exits non-zero (with a diff) if the committed snippets no longer match what generation would
  produce — wire it into a pre-commit hook or CI to catch drift.

A snippet is pasted into **one** buffer, so the two Justfile snippets are the `justfile` and both `.just/` fragments
concatenated — a snippet holding only the root file would produce a justfile importing two files the buffer does not
have, and `import` (unlike `import?`) is not optional. The `import` lines themselves are dropped, which is what makes
the concatenation a valid single file rather than a duplicated one.

The generator only adds the snippet XML wrapper plus a few `${n:default}` interactive fields (package name, the
`main_program` body, the `#config` defaults, the executable names). Recipes fenced by `# >>> name` / `# <<< name`
markers are stripped from the Justfile snippets. Four marker names are used:

* `skeleton-only` — e.g. `new`, `snippets`. Meaningless outside this repo, so `just new` drops them too
* `snippet-exclude` — `sublime-build-init` and `sublime-lsp-init`, the `.just/` `import` lines, and the fragments'
  header notes. Kept by `just new`, but left out of the snippets: the first two contain literal `$` that Sublime would
  otherwise parse as snippet fields, and the rest describes a file layout a single-buffer snippet does not have
* `exe-only` / `lib-only` — the recipes belonging to one project kind. Each justfile snippet keeps its own kind's block
  and drops the other's, which is the same split `odin-skel new --lib` applies

### Cutting a release

Releases are built by `.github/workflows/release.yml` on any version tag, for all four targets. Both `v0.1.0` and
a bare `0.1.0` work — `v` is the more common git convention, but [SemVer](https://semver.org/) is explicit that the
`v` belongs to the tag rather than the version, so it is stripped before stamping and the binary reports `0.1.0`
either way:

```
git checkout master && git merge <branch>   # the tag must include the workflow
just release 0.1.1                          # CHANGELOG.md: Unreleased -> 0.1.1, dated today
git commit -am "release 0.1.1"              # review the diff first
git push origin master
git tag -a 0.1.1 -m 0.1.1
git push origin 0.1.1
```

`just release` only edits `CHANGELOG.md` — it does not stage, commit or tag, so the release stays a decision you
make after reading the diff. It refuses to run twice for the same version, and refuses when the Unreleased section
is empty.

There is no follow-up step after tagging. The scoop manifest is generated during the release from
`packaging/scoop/odin-skel.json` — the workflow fills in the version, URL and hash from that release's
`SHA256SUMS` and uploads it as an asset — and the install script resolves the latest release at run time. Edit the
template only when a field other than those three changes.

Each target runs `embed-check` and the tool's tests, builds with `-define:SKEL_VERSION=0.1.0` (the tag without
its leading `v`), and asserts the binary reports that exact version before it is published. The workflow can also
be run from the Actions tab via *workflow_dispatch* to exercise the matrix without tagging: those builds are
stamped `dev-<sha>` and are not published.

**Add a `CHANGELOG.md` section before tagging.** The release notes are that section followed by GitHub's
auto-generated pull-request list. Since most work here lands by pushing to `master` rather than through pull
requests, the generated half is close to empty, so the changelog is where the actual summary lives. A tag with no
matching section fails the release rather than publishing empty notes, and that check runs first in every build
job so it fails in seconds rather than after four platforms have compiled. Preview what will be published with:

```
just changelog_section 0.1.1
```

Write entries under `## [Unreleased]` as you make each change; `just release` promotes them to a version heading
when you are ready.

<!-- <<< skeleton-only -->
