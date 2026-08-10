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
odin-skel doctor      # check odin / just / odinfmt / git / uv are present and new enough
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

Add `--linker=VALUE` (`default`, `lld`, `radlink` or `mold`) to pin the new project's linker for every platform
instead of inheriting the per-OS default — see [Choosing a linker](#choosing-a-linker).

Add `--lib` to scaffold a **library** rather than an executable — an Odin source package that other projects copy
into their tree and import, with the destination directory as the package itself and examples under `examples/`.
The package name is derived from `NAME` by turning `-`, `.` and spaces into underscores (`odin-toml` → `odin_toml`),
since a directory name is not always a legal `package` clause; `--pkg=NAME` overrides it. A library project gets
`just check`, `just example NAME`, `just examples` and `just doc` in place of the `run_*` / `rerun_*` build ladder,
which has nothing to build.

```
odin-skel new ../odin-toml --lib               # package odin_toml
odin-skel new ../odin-toml --lib --pkg=toml    # package toml
```

Only git-tracked files are copied, so build artifacts, `.git/` and untracked local files are left behind. A few things
are rewritten rather than copied verbatim:

* the `.sublime-project` file is renamed to `NAME.sublime-project`
* the skeleton's [Unlicense](https://unlicense.org) `LICENSE` is replaced with a fresh [Zlib](https://opensource.org/license/zlib)
  `LICENSE` (matching the Odin project's own license)
* the `justfile` is emitted without its `# >>> skeleton-only` recipes (`new`, `snippets`, `snippets-check`) — those
  only maintain this skeleton, not a real project. `README.md` and `.gitattributes` carry the same markers and get the
  same treatment: the README sections documenting those recipes, and the `linguist-generated` rules naming `tools/`,
  which a scaffolded project never receives
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


<!-- <<< skeleton-only -->

<!-- >>> lib-only -->
## Layout

This project is a library: an Odin source package, not something that builds an artifact. **The repository root is
the package.** That is the layout the surrounding Odin ecosystem uses — a consumer clones or copies this directory
into their own tree, frequently renaming it on the way, and imports it by path:

```
git clone <this repo> libs/toml     # the directory name they pick becomes the import path
```

```odin
import "libs/toml"                  # or through a collection: -collection:libs=libs, then import "libs:toml"
```

```
.
├── <pkg>.odin           <- the package; add more files beside it
├── <pkg>_test.odin
├── examples/
│   └── basic.odin       <- package main, built with -file
└── justfile  README.md  ...
```

**The package name must be a valid Odin identifier**, which a repository name often is not: `odin-toml` is a fine
directory name and an illegal `package` clause. `odin-skel new --lib` derives one by turning `-`, `.` and spaces into
underscores, or takes `--pkg=NAME` if you would rather choose.

**Examples are single-file `main` packages**, built with `-file` so several can share `examples/` without their
`main` procedures colliding. In `-file` mode a relative import resolves against the file's own directory, so an
example imports `".."` — one level, not two. Get it wrong and Odin reports
`Syntax Error: Empty directory that contains no .odin files: ../..`, which names the path but not the reason.
`just examples` type checks all of them, which is what stops an API change from quietly invalidating the docs.

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

`just examples` then type checks the whole tree through it. Two things are load-bearing here:

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
* `just examples` — type check every example, so an API change cannot quietly invalidate the documentation
* `just doc` — print the package documentation (`odin doc .`)
<!-- <<< lib-only -->

**Benchmarks** — present only once `bench/` is, which it is not by default. See
[Benchmarking](#benchmarking):

* `just bench [NAME] [--samples=N …]` — build and run the benchmarks; `NAME` filters by substring
* `just bench_build` / `just rerun_bench` — build without running / run without rebuilding
* `just bench_lint` — type check and vet `bench/`, which the root `lint` does not reach
* `just bench_save` / `just bench_cmp` — record a timing baseline / re-run and diff against it
* `just bench_count` / `just bench_count_check` — the same for *instruction counts* under callgrind,
  which do not drift between runs and can therefore gate a merge (needs valgrind)

**Quality:**

* `just lint` — type checking, vet warnings, strict style. No code generation
* `just format` — runs `odinfmt -w .` over the whole tree
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

**Editor setup** (these three run on Python via [uv](https://docs.astral.sh/uv/) — see
[Some recipes need uv](#some-recipes-need-uv)):

* `just ols-config NAME=PATH...` — (re)generate the `ols.json` collection list (see [Language Server Configuration](#language-server-configuration))
* `just install-sublime` — install the snippets + build systems into Sublime Text's global config (see the Sublime section)
* `just sublime-build-init` — add a project-local build-system stub to the `.sublime-project` (see the Sublime section)

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
- All `run_*`, `rerun_*`, `test*` and `diagnose` tasks accept optional extra variadic arguments; add `--` before
  passing arguments to your own program. Edit the `main_name` / `test_main_name` output executable names as needed.
<!-- <<< exe-only -->
<!-- >>> lib-only -->
- `check`, `test*`, `example` and `doc` accept optional extra variadic arguments; add `--` before passing arguments
  to an example's own `main`. Edit the `test_main_name` output executable name as needed.
<!-- <<< lib-only -->
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


## Some recipes need uv

<!-- >>> exe-only -->
`ols-config`, `install-sublime` and `sublime-build-init` are `[script]` recipes — their bodies are Python, run
<!-- <<< exe-only -->
<!-- >>> lib-only -->
`examples`, `ols-config`, `install-sublime` and `sublime-build-init` are `[script]` recipes — their bodies are Python, run
<!-- <<< lib-only -->
through [uv](https://docs.astral.sh/uv/) rather than a bare `python`/`python3` on `PATH`. The justfile pins this in
one place:

```
set script-interpreter := ["uv", "run", "--no-project", "-p", "3.14", "python"]
```

A bare `python` is not a reliable cross-platform lookup — on Windows via [Scoop](https://scoop.sh/) it is whatever
version was last `scoop install`ed with no pin, and on Linux it is whatever the distro shipped. `uv run -p 3.14
python` downloads the interpreter it needs (uv-managed, not the system one) so the same version runs everywhere, and
`--no-project` stops `uv run` from walking up the directory tree looking for an unrelated `pyproject.toml`/`uv.toml`
to treat as a project root.

<!-- >>> exe-only -->
**uv is optional**, unlike `just`: none of the `run_*`/`test*`/`lint`/`format` tasks touch Python, so a project that
never runs one of the three editor-setup recipes above never needs it installed.
<!-- <<< exe-only -->
<!-- >>> lib-only -->
**uv is needed for `just examples`**, and otherwise optional: `check`/`test*`/`lint`/`format`/`example` and `doc`
touch no Python, but `examples` — the recipe that stops an API change from quietly invalidating the documentation —
is one of these `[script]` recipes, so it is not only an editor-setup concern here.
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

<!-- >>> skeleton-only -->
Not part of a scaffolded project — add it with `odin-skel add bench`, to either project kind. See
[Optional features](#optional-features).
<!-- <<< skeleton-only -->

`bench/` holds the harness, your benchmarks, and a `bench.just` carrying the recipes. The justfile's
`import? 'bench/bench.just'` is an *optional* import: it does nothing while the directory is absent, so
the `just bench*` recipes appear the moment it arrives and `rm -rf bench/` takes them away again. The
harness is `package bench` rather than `package main` on purpose — an executable project's root is
already `package main`, and Odin permits only one package of a given name per build.

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

### The part that actually matters: `keep` and `opaque`

Odin has no `black_box`. At `-o:speed` a loop whose result nothing reads is dead code, and LLVM deletes
it — the benchmark then reports the cost of an empty loop and nothing warns you. Two helpers stand in:

* `keep(value)` — volatile-stores the value, so everything that computed it has to run
* `opaque(value)` — round-trips the value through a volatile store and load, so the compiler cannot
  constant-fold through it or hoist it out of the loop

Use both, and read `bench/bench.odin` before writing your first case: it documents the four rules and
the two failure modes that survive them. Both bit this harness during development. A sum over a fixed
1024-element slice reported **13 TB/s** because the slice never changed, so the whole inner loop was
loop-invariant and got hoisted; an `acc = add(acc, i)` chain was replaced outright by the closed form
`n * (n - 1) / 2`. Neither shows up as an error — only as an implausible number.

The harness flags the extreme case: when calibration runs to billions of iterations without a
measurable reading, the row is marked `OPTIMIZED AWAY` rather than printed as a result. The subtler
cases it cannot detect. `bench.empty_loop` is the sanity check to compare against — nothing real is
faster than the loop itself — and `odin build bench -o:speed -build-mode:asm` is the way to settle it,
which is how both of the above were found.

### Reading R² and the outlier counts

`R^2` is how well the samples fit the line, and it is the stand-in for the plots this harness does not
draw. Above ~0.999 on an idle machine. When it drops, the outlier counts say why:

* **a few severe outliers, R² poor** — something else woke up on your core. Re-run. The reported ns/iter
  is a robust fit and survives this; the spread column does not
* **many mild, no severe** — the benchmark itself has two modes: two code paths, a branch predictor
  flipping state, an allocator crossing a size class. One number cannot describe it, and no amount of
  re-running will fix that. Split the benchmark
* **outliers spread evenly through the run** — drift, usually thermal

### Baselines, and where this stops being trustworthy

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

#### Instruction counts: the gate that does not flake

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

## What to use instead, and when

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
| `odinlib` | `source.just` | a justfile for an Odin **library** — `check`, `example`, `examples`, `doc`, `test` |

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

<!-- >>> skeleton-only -->
## Skeleton maintenance

These last two sections maintain this skeleton repository itself, not a project built from it, so
`just new` strips them along with the recipes they document.

### Generated editor snippets

`just new` copies the `.sublime-snippet` files into a new project so you stay aware of them, but strips the
snippet-generator recipes from the copied justfile (they only maintain this skeleton) — once detached, treat the copied
snippets as a one-off starting point rather than something kept in sync.

All three snippets are **generated** from `main.odin` and the `justfile` (their single source of truth) so they cannot
silently drift out of date:

* `just snippets` regenerates `.sublime/Odin-skeleton.sublime-snippet`, `.sublime/Just-Odin.sublime-snippet` and
  `.sublime/Just-Odin-lib.sublime-snippet`. Run it after editing `main.odin` or the `justfile`.
* `just snippets-check` exits non-zero (with a diff) if the committed snippets no longer match what generation would
  produce — wire it into a pre-commit hook or CI to catch drift.

The generator only adds the snippet XML wrapper plus a few `${n:default}` interactive fields (package name, the
`main_program` body, the `#config` defaults, the executable names). Recipes fenced by `# >>> name` / `# <<< name`
markers in the `justfile` are stripped from the Justfile snippets. Four marker names are used:

* `skeleton-only` — e.g. `new`, `snippets`. Meaningless outside this repo, so `just new` drops them too
* `snippet-exclude` — e.g. `sublime-build-init`. Kept by `just new`, but left out of the snippets because it contains
  literal `$` that Sublime would otherwise parse as snippet fields
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
