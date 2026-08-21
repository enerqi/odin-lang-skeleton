# `odin-skel` — design decisions

Design notes for a binary front-end to this skeleton, so that starting a new Odin project does not
require cloning this repository by hand.

Nothing here is built yet. This file records the decisions that were settled up front because they
constrain everything downstream; the open items are listed at the end.

Status: **accepted.** Phases 1–3 are implemented — `version`, `doctor`, `new` with embedded templates,
and CI plus tagged releases for four targets. Phase 4 (update check, `--from-git`, self-update) is
not.

Decision 4 (`--lib`) is **implemented**: `mylib/` is a live template in this repository, `odin-skel new
--lib` scaffolds from it, and CI scaffolds and builds a library on all three platforms.


## Decision 1 — templates are embedded in the binary

The template files are baked into the executable at compile time with Odin's `#load`, rather than kept
as a git clone in a cache directory that the binary refreshes periodically.

```odin
JUSTFILE :: #load("../justfile", string)
```

### Why

The alternative considered was a managed clone under the platform cache directory, pulled on first use
and refreshed daily. It was rejected because the machinery it needs is large relative to what it buys:

| | embedded | cached clone |
| --- | --- | --- |
| network at scaffold time | none | required on first run |
| `git` required to scaffold | no | yes |
| stale or half-written cache | cannot happen | a real failure mode to detect and recover from |
| version coherence | atomic — the binary *is* the templates | binary and templates drift apart |
| offline / air-gapped / CI | works | needs a warm cache |
| template update ships via | a binary release | `git pull` |

The templates are two dozen small text files. Embedding them deletes the cache directory, the
refresh timer, the partial-clone recovery path, and the "which template revision did this project come
from" ambiguity outright, rather than solving each one.

Atomic versioning is the decisive part. With a cache, `odin-skel version` has to report two versions
that can disagree, and a bug report becomes hard to reproduce because the tool's behaviour depends on
when the machine last refreshed. Embedded, the binary version identifies the output exactly.

### What it costs

Changing a template requires cutting a binary release. That is the real price, and it is accepted:
templates change rarely, and releases are automated (see the CI phase).

The escape hatch for anyone who wants the tip of the repo without waiting for a release is an opt-in
flag, not the default path:

```
odin-skel new ../proj              # embedded templates: offline, deterministic
odin-skel new ../proj --from-git   # clone/pull the skeleton, scaffold from HEAD
```

`--from-git` is the only code path that gets a cache directory, and it is chosen per invocation:

| OS | cache path |
| --- | --- |
| Linux | `$XDG_CACHE_HOME/odin-skel`, defaulting to `~/.cache/odin-skel` |
| macOS | `~/Library/Caches/odin-skel` |
| Windows | `%LOCALAPPDATA%\odin-skel\cache` |

Cache, not config. The directory is reconstructible from the network and is never hand-edited, so it
does not belong in `~/.config` (or its per-OS equivalents).

### Consequence: the embed step needs a drift guard

Embedded templates are a second copy of files that also live in the repo root. This repo already has
exactly this problem with the `.sublime-snippet` files and already solves it: a generator recipe plus a
`--check` mode wired into CI. Extend that idiom instead of inventing a second one.

* `just embed` regenerates the Odin source file holding the `#load` declarations
* `just embed-check` exits non-zero with a diff when it is stale, mirroring `just snippets-check`


## Decision 2 — the binary owns scaffolding; `just new` becomes a shim

`just new` currently implements the non-trivial parts of scaffolding in Python: stripping
`# >>> skeleton-only` blocks from the justfile, renaming `.sublime-project` to the project name,
replacing the skeleton's Unlicense `LICENSE` with a fresh Zlib one, and skipping `tools/`. Once
`odin-skel new` exists, that logic lives in the binary and nowhere else — `just new` shells out to it.

**This direction applies to `new` alone.** Every other command flows the other way: `odin-skel <cmd>`
defers to `just <cmd>` (see Open items). The rule behind both is the same — delegate towards wherever
the single definition already lives, never reimplement it at the other end:

| command | direction | the one definition lives in |
| --- | --- | --- |
| `new` | `just new` → `odin-skel new` | the binary — users who never clone this repo must still scaffold |
| `run`, `test`, `lint`, ... | `odin-skel run` → `just run` | the *scaffolded project's own* justfile, which is per-project and user-edited |

The binary cannot own `run`/`test`/`lint`: it does not know a given project's recipes, and those
recipes are expected to be edited. A binary-side reimplementation of `odin run . -debug ...` would be
duplication that silently diverges the first time somebody edits their justfile.

### Why

Two implementations of the same transformation will drift, and the drift is invisible: both produce a
plausible project, and the difference only surfaces later in whichever one was not exercised. There is
no test that can cheaply pin two implementations to each other without effectively being a third.

The binary is the right owner rather than the recipe because it is the artifact users who never clone
this repo will actually run. A recipe-owned implementation would make `just new` the reference and the
binary the copy, which inverts the dependency: the binary would then need its own port anyway.

### Migration — done

The cutover happened in phase 2. `just new` is now a shim that execs `target/debug/odin-skel new` and
propagates its exit code; the Python body was deleted rather than left dormant beside it, so there is
no second implementation to drift.

The port was validated by running both implementations into separate directories and diffing the
results: byte-identical across all thirteen files, including the stripped justfile and the generated
Zlib licence. That comparison is no longer possible now the Python is gone, which is precisely why it
was done at the moment of cutover.

`just new` now depends on the binary existing. That is acceptable — it only runs inside a clone of
this repo, where `just build_skel` produces it — and the shim checks for the file first so the failure
is `missing target/debug/odin-skel.exe - run 'just build_skel' first` rather than a bare
"command not found".


### Decision 2a — `new` calls back into the project's own recipes for the ols pin

Scaffolding ends with two calls into the project just written: `just bump-ols`, which rewrites the
`ols_tag`/`ols_sha256` pin to the latest ols release, and `just fetch-ols`, which installs it. Both
warn and continue; neither can fail the scaffold. `--offline` skips both.

This is the direction of Decision 2 reversed, and deliberately so — it is the same rule, not an
exception to it. The single definition of *which* release is current and *how* a pin is verified lives
in the justfile, because that is the copy a user edits and bumps for the rest of the project's life.
A binary-side reimplementation would be a second GitHub client and a second digest check that agree
today and diverge the first time either is touched.

**Why do it at all.** The pin the templates carry is as old as the last odin-skel release. Without
this, every new project starts several ols releases behind, and the first person to bump it takes a
reformatting diff across files nobody edited. odinfmt ships inside an ols release and has no
`--version` flag, so there is no cheaper way to discover what is current than asking the release API.

**Why warnings rather than an exit code.** The files are already written and correct by this point;
what is at stake is only whether the pin is current and the tools are on disk. A scaffold that
reported failure because GitHub was unreachable would be lying about what happened, and the recovery
is one command the warning names. The two failures are reported separately because they mean different
things: the pin not being checked leaves a working project on an older formatter, while the install
not happening is not a problem at all — `format` depends on `ensure-odinfmt` and retries at the point
of use.

**Cost.** `new` now needs `just` and `uv` for its last step, where before it needed nothing. Both are
already required to *use* the project, and a missing one is reported as that rather than as a failure.

### Amendment — the bump has to be finished, and has to be refusable

Two holes in the above, found by asking whether the bump is a good idea at all.

**It relocated the diff rather than removing it.** `new` bumped the pin and installed the tools but did
not format, so the delivered files were formatted by whichever odinfmt the *skeleton* pinned while the
project now pinned a newer one. The first `just format` therefore churned files the user never wrote —
the exact diff the bump exists to prevent, moved from "whenever somebody bumps" to "the user's first
format", by which point there may be history to review it against. `pin_and_install_ols` now runs
`just format` as well, but only when the pin actually moved, decided by reading the pin back rather than
by parsing the recipe's output. Nothing to do when it did not move: the templates already match.

**"Latest" is not "newer", so the bump has to be refusable.** `bump-ols` says so itself — these tags
have no ordering it can rely on, and the release marked latest can be older than a hand-picked pin. The
only way to keep a deliberate pin was `--offline`, which also skipped the install. `--no-bump` separates
the two.

**Accepted cost, stated plainly.** This is in tension with Decision 1's atomic versioning: two runs of
the same binary on different days do not produce the same project. Decision 1's claim is about the
*templates* being identified exactly by the binary version, and that still holds — the pin is the one
value deliberately taken from the outside world, because its whole purpose is to name something that
lives there. `--no-bump` and `--offline` are how a caller who wants the stronger property gets it.

**And it needed covering.** Every scaffold in CI passed `--offline`, so this entire path — the only one
that touches the network, and the one every real first-time user hits — was never executed by CI. A
Linux-only non-offline scaffold now runs it, asserting the invariant rather than the outcome: the pin
file is still intact, the project still builds, and `just format` on the fresh scaffold changes nothing.



## Decision 3 — repository layout (a): the repo root stays the template

The tool's source lives under `tools/`. The repository root remains a working Odin project.

```
.                      <- the exe template; also a project you can clone and run as-is
├── main.odin
├── justfile
├── odinfmt.json
├── .sublime/
├── mylib/             <- the lib template (Decision 4): a live package here, relocated to the
│                         destination root when scaffolded with --lib
├── CHANGELOG.md       <- NOT part of the template: this skeleton's own history
├── .github/           <- NOT part of the template: CI for the skeleton itself
│   └── workflows/
└── tools/             <- NOT part of the template
    ├── DESIGN.md      <- this file
    └── skel/          <- odin-skel source
```

`.github/` is excluded for the same reason as `tools/`: its workflows run `embed-check`, `lint_skel`
and `test_skel`, none of which exist in a scaffolded project, so inheriting them would hand every new
project a red CI badge on day one. Shipping projects a *useful* starter workflow is worth doing, but
it is a different file with different contents — see Open items.

### Why

The alternative was moving the template into a `template/` subdirectory, leaving the root as a plain
tool repository. That is a cleaner separation on paper, but it destroys a property worth keeping:
today you can clone this repo and immediately `just run`. The skeleton is testable *as itself* — the
same `lint`, `format`, `test` and build tiers that a scaffolded project gets are exercised on the
skeleton on every commit. Under `template/`, the template stops being a live project and starts being
inert data that only gets exercised once it is copied somewhere else.

Keeping the root as the template also means the tool has no privileged view of it: `odin-skel` embeds
the same files a human would get from `git clone`, so the two paths cannot diverge.

### What it costs

`tools/` must be excluded from scaffolding, or every generated project inherits the tool's source.
This is implemented in the `new` recipe:

```
EXCLUDED_PREFIXES = ("tools/",)
```

plus `EXCLUDED_FILES` for individual paths such as `CHANGELOG.md`, which is a single tracked file at
the root rather than a directory.

`just new` reports the skipped count so an accidental exclusion is visible rather than silent. **Any
new skeleton-tooling path must be added to one of those tuples and to the tree above.**

Note that `.gitignore`-style exclusion does not work here: `just new` copies from `git ls-files`, so
`tools/` has to be tracked (it is source code) while still being skipped at copy time. The exclusion is
therefore explicit in the recipe rather than inherited from git.

### Amendment — a second project kind cannot also be the root

Decision 4 adds `--lib`, and a library template cannot be the repository root as well: the root is
`package main`, and a directory holds exactly one package. Taken literally, the decision above would
force the lib template into a `template/` directory — the inert data this decision exists to reject.

The rule is therefore restated one level up. **What matters is not that the template lives at the root,
but that every template is a live participant in this repository's own build.** For the exe template
that means being the root package, as before. For the lib template it means being a real package this
repository lints, tests and imports, which `just lint` and `just test` already sweep — see Decision 4,
"keeping the lib template live", for the directory and the path rewriting that follows from it.

Both templates stay exercised on every commit. Neither becomes a directory of text files that is only
compiled once somebody else has been handed a copy.


## Decision 4 — `--lib` scaffolds a source package, not a build target

`odin-skel new --lib <dest>` scaffolds a library: an Odin **source package** that consumers clone or
vendor into their own tree and import. It is the counterpart to cargo's `--lib`, and the default
(executable) shape is unchanged.

**Producing a native artifact is out of scope.** Odin can build `-build-mode:shared|dll` and
`-build-mode:lib|static`, but a project doing that is a different shape — exported entry points, a
hand-written C header, per-platform artifact names, and a `context` to establish at every boundary. It
deserves its own kind if it is ever wanted; it is not what `--lib` means here.

Status: implemented. The two load-bearing sub-decisions are **4a** (the repository root is the package)
and **4d** (tests live in the package); the rest follows from them.

### What the ecosystem actually does

Surveyed from the libraries listed in [awesome-odin](https://github.com/jakubtomsu/awesome-odin), plus
the Odin toolchain's own `core`:

| repository | shape | how a consumer uses it |
| --- | --- | --- |
| laytan/odin-http | root **is** the package, plus `client/`, `openssl/` subpackages | examples `import http "../.."` |
| jakubtomsu/odin-ldtk | root is the package, plus `example/` | "place `ldtk.odin` in an `ldtk` folder", `import "../ldtk"` |
| Up05/toml_parser | root is the package, plus `dates/`, `tests/` | `git clone …/toml_parser toml`, then `import "toml"` |
| laytan/back | root is the package, plus `examples/` | examples `import back "../.."` |
| GoNZooo/odin-cli | root is the package | not stated |
| enerqi/odin-rure | root is the package, plus `example/` | not stated |
| jakubtomsu/odin-mimalloc | package in a `mimalloc/` subdirectory | "copy the `mimalloc` folder into your project", `import mi "mimalloc"` |
| Odin `core/`, `vendor/` | collection root: no `.odin` at the top, packages in subdirectories | `-collection:` (built into the compiler) |

Six of the seven community libraries make the repository root the package itself. The consumer clones
or copies that directory into their own tree — frequently renaming it on the way, as toml_parser's
instructions do — and imports it by relative path. A `-collection:` flag is the *consumer's* choice
about their own vendor directory, not something the library repository declares.

So "the project root is the collection root" is close but off by one level: the root is the **package**.
The collection, when there is one, is the directory the consumer dropped it into.

`core/` and `vendor/` are the exception that proves the rule — they are genuine collection roots, but
they are also the compiler's built-in collections, mounted by the toolchain rather than vendored by
anyone. Their layout is what a library *grows into*, not what one starts as.

### Decision 4a — layout

```
<repo>/                    <- consumers clone/copy THIS directory into their tree
├── <pkg>.odin             <- package <pkg>; the root directory is the package
├── <pkg>_test.odin
├── examples/
│   ├── basic.odin         <- package main, built with -file, `import ".."`
│   └── all.odin           <- aggregator; only once subpackages exist (Decision 4c)
├── justfile  README.md  LICENSE  .gitignore  .editorconfig  odinfmt.json  .sublime/
```

Subpackages are added later as subdirectories, exactly as odin-http grew a `client/`. The root package
stays the entry point, so a library that gains a second package restructures nothing.

The chief practical benefit is that the recipes barely move: with `.odin` files at the root,
`odin check .` and `odin test .` work unchanged. A collection-root layout (no `.odin` at the top) does
not — verified:

```
$ odin check .
Syntax Error: Empty directory that contains no .odin files: <root>
```

There is no `-all-packages` for `check` or `build` (only `odin doc` has one, and it means "packages
*used by* this project", which sweeps in all of `core:`), so a collection-root layout would force every
lint/test recipe into a directory loop. Root-as-package avoids that until the project earns it.

### Decision 4b — examples are single-file `main` packages

`examples/` holds flat, single-file executables, each built with `-file`, which makes the file a
self-contained package. Several `main` procedures therefore coexist in one directory with no
subdirectory apiece:

```
odin run examples/basic.odin -file -out:target/debug/example-basic.exe
```

**The relative import depth differs from the ecosystem's, and the error is unhelpful.** A `-file`
example sits one level shallower than the `examples/<name>/main.odin` layout that odin-http and back
use, so it imports `".."`, not `"../.."`. Verified:

| example | import | result |
| --- | --- | --- |
| `examples/basic.odin` with `-file` | `import ".."` | works |
| `examples/basic.odin` with `-file` | `import "../.."` | `Syntax Error: Empty directory that contains no .odin files: ../..` |
| `examples/basic/main.odin` | `import "../.."` | works |

Relative imports in `-file` mode resolve against the file's own directory. The generated README must
say so, because the error names the path and not the reason.

Examples import by relative path rather than through a collection, which keeps them honest: they
exercise the same directory a consumer would vendor, with no build-time flag propping them up.

### Decision 4c — the aggregator package for whole-tree checks

Once the library has subpackages, nothing type-checks them all at once — `odin check .` only sees the
root package. Odin's own answer is `examples/all`, a package whose entire content is
`@(require) import` of every other package, checked by `check_all.sh` and used to drive `odin doc`.

The same idea collapses to one file here, so it stays inside Decision 4b's "single-file examples" rule:

```odin
package all

@(require) import ".."
@(require) import "../sub"
```

`odin check examples/all.odin -file -no-entry-point` then type-checks the whole tree. Verified that it
fails on a broken subpackage:

```
$ odin check examples/all.odin -file -no-entry-point
<root>/sub/sub.odin(4:13) Error: Undeclared name: undefined_thing
```

`@(require)` is load-bearing — without it an unreferenced import is dropped and the check passes
vacuously.

The scaffolded project ships without this file, since a one-package library does not need it. The
README documents it as the thing to add on the day a second package appears.

Note that `odin doc <target> -all-packages` is *not* a documentation recipe for a library: it documents
every package used, `core:` included. Per-package `odin doc <pkg>` is the usable form.

### Decision 4d — tests stay in the package

`<pkg>_test.odin` lives beside the source, and `odin test .` needs no configuration. Verified: a
`_test.odin` in a package compiles fine in a non-test build, where `@(test)` procedures are simply
ignored.

The alternative is Odin core's: a mirrored external tree (`tests/core/<pkg>/`) importing through the
collection, so the shipped package contains no test code at all.

In-package wins for a single-package library because tests can reach `@(private)` symbols, and because
it is what the surveyed libraries do.

### The cost of in-package tests, measured

The test file is part of the package, so a consumer building the package also builds
`import "core:testing"`. **Optimization does not remove it** — the same example binary, built with and
without the `_test.odin` file beside the source (Linux x86-64):

| build | with `_test.odin` | without | delta |
| --- | --- | --- | --- |
| `-o:none -debug` | 832,912 | 808,976 | +23,936 |
| `-o:minimal` | 377,648 | 372,056 | +5,592 |
| `-o:speed` | 230,712 | 222,056 | +8,656 |
| `-o:size` | 230,712 | 222,056 | +8,656 |
| `-o:speed` + `-no-bounds-check -disable-assert -no-type-assert` | 208,664 | 200,008 | +8,656 |

The `@(test)` procedure itself *is* eliminated — no `test_add` symbol survives in the optimized binary.
What survives is `core:testing`'s transitive `@(init)`/`@(fini)` roots, which are entry points and
therefore unconditionally live no matter how dead the code reaching them is. At `-o:speed` the residue
is twelve symbols: `terminal::init_terminal` / `fini_terminal`, `log::init_standard_stream_status`,
`os::stderr`, and the rune-decode tables they pull along. Sections move by text +6,860, data +16,
bss +16. `-o:speed` costs *more* than `-o:minimal` because the retained code is then inlined and
specialised.

The number that decides this, though, is the overlap. Almost the whole cost is packages the consumer
very likely imports anyway. The same measurement against an example that already uses `core:log`:

| build | with `_test.odin` | without | delta |
| --- | --- | --- | --- |
| `-o:minimal` | 411,384 | 411,304 | **+80** |
| `-o:speed` | 253,696 | 253,624 | **+72** |

So the honest figure is "up to ~8.6 KB against a consumer who imports nothing but `core:fmt`, and
~80 bytes against one that already logs". That is not worth an external test tree. The generated README
records it and points at the mirrored-tree layout for anyone whose target says otherwise — a freestanding
or WASM consumer, where both the size and the `@(init)` roots may actually matter.

If the library later becomes a genuine collection, adopt core's layout wholesale — at that size the
package boundary matters more than reaching private symbols.

### Decision 4e — three names where the exe kind has one

| name | example | constraint |
| --- | --- | --- |
| destination directory / repository | `odin-mylib` | anything |
| package name, declared in every file | `mylib` | **must be a valid Odin identifier** — a hyphen is illegal |
| the directory the consumer clones into | `mylib` | theirs to choose; it becomes the import path segment |

`--lib` therefore needs a sanitiser the exe path never did: `-`, `.` and space to `_`, reject a leading
digit, reject Odin keywords, reject empty. `--pkg=<name>` overrides it; without one it derives from the
project name. `odin-skel new --lib ../odin-mylib` yields `package mylib` in a directory named
`odin-mylib`, and the README tells the consumer to clone it as `mylib`, which is what toml_parser's
instructions already do by hand.

### Decision 4f — justfile delta

Root-as-package keeps this small.

**Unchanged:** `format`, `clean`, `mktarget_dirs`, `lint` (it already passes `-no-entry-point`), the
whole `linker` block, and `test`/`test1`, which work against the root package as they stand.

**Removed** — the five-tier build ladder has nothing to build:

* `run_debug`, `run_fast_debug`, `run_release_debug`, `run_release`, `run_release_nochecks`, `alias run`
* the five `rerun_*` recipes and `alias rerun`
* `sanitize` — it is `odin run`-based, so it folds into the existing `test_sanitize`
* `diagnose`
* `main_name` (`test_main_name` stays)

**Added:**

* `example <name>` — `odin run examples/{{name}}.odin -file`, output to `target/debug/example-<name>.exe`
* `examples-check` — check every file in `examples/`, so the library cannot drift from its own documentation
* `doc` — per-package `odin doc`
* `check` — the inner-loop recipe, replacing `just run` as the thing you hit constantly

`-microarch:native` can stay in the test and example recipes: nothing here ships as a binary, so it
never reaches a consumer's machine.

**Settled: `release` and `changelog_section` stay skeleton-only.** The case for shipping them was that a
library is tagged and pinned far more than an application is, because its consumers depend on tags. The
case against is mechanical and wins: both recipes need files a scaffolded project does not receive.
`CHANGELOG.md` is in the embed generator's `EXCLUDED_FILES` and `.github/` is excluded wholesale, so
`just release 1.0.0` would fail on `open("CHANGELOG.md")` with a Python traceback, and
`changelog_section` exists to feed a release workflow that is not there either. A recipe that only
errors is worse than an absent one, and Keep a Changelog is a workflow choice rather than a build
concern — not something a scaffold should presume.

The tagging point survives as a line in the generated library README instead, which costs nothing and
imposes nothing.

### Keeping the lib template live

Per the Decision 3 amendment, the lib template has to be a real package in this repository. It cannot be
the root, so it lives in its own directory named for its placeholder package:

```
<skeleton>/
├── main.odin              <- exe template; still the root package
├── mylib/                 <- lib template: package mylib, with its tests
│   ├── mylib.odin
│   ├── mylib_test.odin
│   └── examples/basic.odin
└── tools/
```

Scaffolding relocates `mylib/*` to the destination root and rewrites `package mylib` to `package <pkg>`.

The relative import strings survive the move untouched, which is what makes this cheap: in the skeleton,
`mylib/examples/basic.odin` built with `-file` resolves `".."` to `mylib/`; in a scaffolded project,
`examples/basic.odin` resolves the same `".."` to the root. Same string, both positions. Only file paths
are rewritten, never file contents beyond the package clause.

What keeps it compiled is a pair of skeleton-only recipes, `lint_lib_template` and `test_lib_template`,
wired into CI beside `lint_skel` and `test_skel`. The root `main.odin` deliberately does **not** import
`mylib/`: `main.odin` is itself a template, and an import of a directory that no exe project receives
would break every project scaffolded without `--lib`.

`test_lib_template` runs the example as well as the tests, because `odin check` never links and the
example's entire job is to prove that the import path a consumer will use resolves at runtime.

### Two things the implementation had to settle that the design did not anticipate

**A constant slice does not survive being returned.** `DROP_FOR_EXE :: []string{...}` passed straight to
a procedure works; the same constant returned from `drop_names` does not — the literal is materialised
into the callee's frame and is gone by the time the caller iterates it. It failed in the worst possible
way: every name compared unequal, so nothing was dropped, and scaffolding produced a justfile with the
skeleton's own recipes still in it and no error anywhere. Both drop sets are now `@(rodata)` arrays,
which have a lifetime that outlives the call.

**A marker block cannot live inside a recipe that generates a file.** `sublime-build-init` is a
`[script]` recipe that writes a `build_systems` entry, and its `shell_cmd` has to name a recipe that
exists. Marking the two branches would work in a scaffolded project but not here: this repository's own
justfile is the unstripped one, so *both* would execute and the stub would carry two `shell_cmd` keys.
It therefore seeds `just test`, the one recipe both kinds have, and lists the rest as commented
variants — comments are harmless in every context, stripped or not.

**The Sublime build systems are global, so they are never stripped.** `OdinJustTarget.sublime-build`
names recipes in its `project - just ...` variants, half of which exist in only one kind, which looks
like a case for kind markers. It is not: `just install-sublime` copies these files into Sublime's
global `Packages/User`, where they match on `source.odin` and drive *every* Odin project on the
machine. A copy specialised to the project it was scaffolded from would take the other kind's build
variants away everywhere — scaffold a library, install, and your executable projects lose `just run`.

So the file lists both kinds and is copied verbatim. A variant naming a recipe the current project does
not define simply fails if you pick it; a variant missing from the global copy is gone for good. The
same reasoning applies to `Odin.sublime-build`, which is already kind-agnostic because it invokes
`odin` directly rather than going through `just`.

A consequence worth stating: `marker_text` deliberately has no `//` spelling, so kind markers added to
a `.sublime-build` file would be inert rather than wrong-looking. A test asserts none are present.

### Tool changes

* `main.odin` — `--lib` and `--pkg=<name>`, parsed in the same anywhere-after-`new` loop as `--linker`;
  usage text and examples. `--linker` still applies, since test and example binaries are linked.
* `new.odin` — `new(dest, name, linker, kind, pkg)`; the per-file switch gains the `mylib/` prefix strip
  and the package-clause rewrite.
* `templates.odin` / `_embed` — `Template` gains a `kind`, and the generator learns that lib template
  files are written to a different path than they are read from.
* `strip_skeleton_only` — generalised to named blocks (`exe-only`, `lib-only`) for the justfile and
  README. `marker_text` already handles both comment spellings, and the "unknown marker: drop the marker
  line, keep the body" branch already exists, so this is a small change to a tested shape.
* Unchanged: `doctor`, `OWNED_COMMANDS` and the loop guard, `set_linker_default`, `project_readme`,
  `zlib_license`, `dir_is_empty_enough`, and every path helper.
* `just new` needs **no change** — its `*flags` passthrough already carries `--lib`.
* New tests: the package-name sanitiser as a table, per-kind stripping, and an end-to-end lib scaffold.

### Splitting the templates

* justfile and README — marker blocks. They are ~37 KB and mostly shared; a second copy is a permanent
  drift problem, which is Decision 2's argument applied to text files.
* Odin sources and examples — separate files carrying a `kind`. `main.odin` and a library package share
  nothing, and markers would make both unreadable.

### Amendment — the justfile is three files

The justfile reached 1376 lines, of which ~450 were the pinned-ols machinery and the editor setup:
recipes run once per machine, in the file read every day to find `just run`. They moved to
`.just/toolchain.just` and `.just/editor.just`, imported by the justfile.

This is `import?` from Decision 4f used for a different purpose, so the differences are deliberate. The
imports are **mandatory** — both files always ship, and `import?` would turn a deleted one into recipes
silently missing from `just --list` rather than an error. The fragments join the marker-stripped set in
`new`, matched on the `.just/` prefix rather than by name, so a third fragment needs no code change. And
`_snippets` concatenates all three files before stripping: a snippet is one buffer, and a snippet of the
root file alone would emit a justfile whose mandatory imports resolve to nothing. The `import` lines are
in a `snippet-exclude` block, which is what makes the concatenation a single valid file.

What did not change: `_embed` (its input is `git ls-files`, so the fragments arrived by being tracked),
every recipe name, and every `[group]` — `just --list` output is identical, which is the regression test.

### What it costs

Two project kinds means two templates to keep working, and the `just embed` drift guard now has two
trees to cover. The Decision 3 amendment holds the line that matters — both are live code in this
repository — but `just lint` and `just test` do more work per commit, and a change to the shared
justfile has to be considered against both kinds rather than one.

### Order of work

1. Confirm 4a and 4d — everything else hangs off the layout and the test placement.
2. Add the live `mylib/` package and its examples to this repository; wire it into the root project and
   get CI green. This is the Decision 3 amendment, and it comes before any tool work.
3. Generalise block stripping to named kinds; mark the justfile and README.
4. `Template.kind`, path rewriting, and the two-tree `_embed`.
5. `--lib` / `--pkg` parsing, the name sanitiser, and tests.
6. Usage text, README "Creating a new project", this file, CHANGELOG.

Steps 1 and 2 are load-bearing; 3 to 5 are mechanical once the template is a real package.


## Decision 5 — optional features are added later, not scaffolded

`odin-skel add <feature> [dir]` writes an optional feature into a project that **already exists**.
`new` never writes one. The first is `bench`, the benchmark harness.

The problem it solves is bulk, not capability. The harness is ~700 lines of statistics and commentary
that most projects will never open, and a skeleton earns its keep by what a reader has to understand
before touching anything. A third project kind would be the wrong shape — benchmarks are orthogonal to
executable-vs-library, and a `--bench` flag on `new` would still make the decision at the one moment
nobody has enough information to make it.

Status: implemented.

### 5a — a feature is a directory, copied verbatim

No marker stripping, no package clause rewriting, no relocation. `Template.feature` is a second axis
alongside `kind`, and `_embed` tags every file under a feature's directory. `new` skips any template
with a non-empty `feature`; `add` writes only those, at the same relative path they occupy here.

That verbatim rule is what keeps `add` small. Everything `new` does beyond copying exists because the
skeleton's root is simultaneously a template and a live project. A feature directory has no such
conflict: `bench/` here *is* `bench/` there.

### 5b — recipes arrive by optional import, not by editing the justfile

The load-bearing constraint is that a feature must be addable to a project that already exists, whose
justfile the author has since edited. Anything that has to modify that file needs a splice point, an
idempotency rule, and a merge story for the case where somebody changed the block by hand.

just's `import?` removes the problem. The project justfile carries one permanent line:

```just
import? 'bench/bench.just'
```

The `?` means "if it is there". With the directory absent the line is inert — `just --list` shows no
benchmark recipes and nothing errors. So `add` is a file copy, the uninstall is `rm -rf bench/`, and
neither has state to get wrong. Verified: an imported file shares one namespace with its importer, so
`linker`, the `target_path` function and the `mktarget_dirs` recipe are all visible to `bench.just`,
while `bench_name` stays local to the feature.

The import line sits outside every kind marker: a feature applies to either project shape, and putting
it inside `exe-only` or `lib-only` would silently break the other. `test_feature_import_survives_both_kinds`
asserts that after stripping.

### 5c — the harness is `package bench`, and that is not cosmetic

An executable project's root is `package main`. Odin permits exactly one package of a given name in a
build, so a `bench/` that also declared `package main` fails before running anything:

```
Error: Duplicate declaration of 'package main'
A package name must be unique
```

Odin does **not** require the entry package to be named `main` — only that it contains a `main`
procedure. Naming the harness `bench` therefore makes one directory work for both kinds, and removes
what would otherwise have been a second copy of the template. `test_bench_feature_is_not_package_main`
holds it there.

### 5d — the feature stays live, like the templates

Decision 3's amendment applies unchanged: `bench/` is a real package in this repository, and the
skeleton's own justfile imports its recipes, so `just bench_lint` and `just bench` run here. The
scaffolded projects it produces have their own end-to-end coverage — both kinds scaffold, `add bench`,
lint and run in CI — which is stronger than a static check, because it exercises the path a user takes.

One thing this costs: `bench/bench.odin` cannot import `".."` in the shipped template, because the
executable skeleton's root exposes nothing benchable. So the import pattern is documented in the file
rather than compiled. Weaker than `examples/basic.odin`, which exists specifically to prove import
depth — but `bench/` is a package build, not `-file` mode, so `".."` resolves by the ordinary rule and
the `-file` subtlety that motivated that guard does not apply.


## Settled context for these decisions

Verified against the toolchain rather than assumed:

* `#load("path", string)` embeds a file at compile time — confirmed working
* this Odin build's `core:os` is the os2 rewrite and has a full process API (`process_start`,
  `process_exec`, `process_wait`), so shelling out to `just`/`git` needs no vendor dependency
* `core:flags` covers CLI parsing; `core:encoding/json` covers config
* **`core` has no TLS.** `core:net` is TCP-only, so anything over HTTPS must shell out to `git` or
  `curl`. This is why the update check is specified as `git ls-remote` rather than a GitHub API call
* GitHub Actions is free on public repositories for all standard runners, including macOS and Windows,
  with no minute multiplier — so a three-OS release matrix costs nothing and macOS is included from the
  start rather than deferred

For Decision 4, run against the installed toolchain rather than reasoned about:

* `odin check` on a directory with no `.odin` files in it fails with
  `Syntax Error: Empty directory that contains no .odin files` — a collection root is not checkable as
  a unit
* `-all-packages` exists only on `odin doc`, and documents packages *used by* the project, `core:`
  included. There is no whole-tree `check` or `build`
* in `-file` mode a relative import resolves against the file's own directory, so a flat
  `examples/x.odin` imports `".."` where an `examples/x/main.odin` imports `"../.."`
* a `_test.odin` file inside a package compiles in a non-test build; `@(test)` procedures are ignored
  there, and the procedure bodies are eliminated. What is *not* eliminated at any optimization level is
  `core:testing`'s transitive `@(init)`/`@(fini)` roots — see Decision 4d for the measurements
* a single-file `package all` of `@(require) import`s type-checks every package it names, and reports
  errors from inside them. Without `@(require)` the unreferenced imports are dropped and the check
  passes vacuously


## Open items

Not decided; deliberately deferred.

* command surface beyond `new` / `doctor` / `version`. Current leaning is that hand-written per-recipe
  wrappers should be skipped in favour of a single passthrough rule: unknown subcommand plus a justfile
  present → exec `just <args...>`. One rule stays correct as recipes are added, renamed or edited,
  where a wrapper list would need updating and would rot silently.

  **Loop guard.** Decision 2 makes `just new` call `odin-skel new`, and this rule makes `odin-skel
  <unknown>` call `just <unknown>`. If `new` ever drops out of the binary's command table the two form
  an infinite ping-pong. The passthrough must therefore refuse to forward any name the binary itself
  defines — a positive check, not a reliance on the table happening to stay correct. A recursion-depth
  environment guard set by the binary before it execs `just` is the cheap belt-and-braces version.
* ~~a maintenance command for the mechanical files~~ — **decided: built, as `sync`.** Named `sync` rather
  than `update` because `update` is taken by self-update below, and because it says what happens. Six
  files: `.editorconfig`, `.gitattributes`, `.gitignore`, `.just/editor.just`, `.just/toolchain.just`
  and `odinfmt.json`, tagged `sync = true` by `SYNCABLE_FILES` in the `_embed` recipe so the set cannot
  become a second hand-maintained file list that rots against the embed list.

  Three properties decide membership, and all three are load-bearing: no project-specific substitution
  (which rules out the justfile's `--linker`, README.md's H1, LICENSE's year and the renamed
  `.sublime-project`), the same rendered output for both project kinds (so `sync` never has to work out
  which kind it is looking at — `test_syncable_templates_are_kind_independent` enforces it), and
  configuration rather than code, so nobody is expected to have edited it. The `.sublime` files satisfy
  the first two and fail the third: the copies are starting points, which is why they are excluded even
  though they would copy cleanly.

  **The pin.** `.just/toolchain.just` carries `ols_tag` / `ols_sha256`, which `just bump-ols` rewrites.
  Overwriting it would undo a bump and can move a hand-picked pin *backwards*, for the same reason
  `new --no-bump` exists. So `sync` reads the destination's two lines and splices them into the
  rendered template, and fails rather than guessing when either file has no pin line. `--pin=template`
  opts out. This is the whole reason the command needed designing rather than being a file copy.

  **git is the undo**, not a backup directory: any file that would change is checked with
  `git status --porcelain --untracked-files=all --ignored=matching`, and modified, untracked or ignored
  refuses unless `--force`. `--ignored=matching` is not decoration — git searches *upwards* for a
  repository, so a project under no repository of its own is answered by some ancestor (a home-directory
  dotfiles repo answers for everything below it), and if that ancestor ignores the path, plain
  `--porcelain` reports clean about files git has never heard of.

  **The skeleton repository is refused by name**, `--force` included, on the presence of
  `tools/skel/templates.odin` — a path `_embed` excludes, so no project ever has one. It is the single
  destination where a sync is pure damage: the repository's copies are the *unstripped* originals, so
  writing the rendered versions back deletes .gitattributes' `skeleton-only` block and the fragments'
  `snippet-exclude` markers, which is the text scaffolding reads. Every other guard waves it through,
  since the files are committed and there is Odin source everywhere.

  **The destination must look like an Odin project**: a justfile *and* `.odin` source at any depth below
  it. The justfile guard alone is what `add` uses, and it is weak evidence on its own — `just` is a
  general-purpose runner, so it would let a sync in the wrong terminal tab replace an unrelated
  project's `.editorconfig`. Any depth, because the layouts differ: a library keeps source at the root,
  an executable may not, and a grown project may keep none at the top. `target/` and `.git` are skipped
  and the walk is depth-bounded against symlink loops.

  `--check` writes nothing and exits 1 on drift, the same contract `embed-check` has, so a project can
  gate on "my mechanical files match odin-skel N". `--dry-run` is the preview that exits 0; the two are
  refused together, since a CI job passing both would be green whatever it found.
* `odin-skel update` (self-update). Windows cannot overwrite a running `.exe`, so the binary must
  rename itself before writing the replacement and clean up on next launch. This constrains where the
  binary may install itself, so it is worth designing before it is built
* update *check* cadence and opt-out (`ODIN_SKEL_NO_UPDATE_CHECK=1`); must never block or fail a
  command
* minimum `just` version to enforce — now done, in `doctor.odin`'s `min_version`. The floor is set by
  the newest just feature the justfile actually uses (currently user-defined functions, 1.49), so it
  moves when a recipe adopts something newer; the README's stated floor has to move with it

* a starter CI workflow *for scaffolded projects*. The skeleton's own `.github/` is excluded from the
  template because it checks skeleton-only things, so a generated project currently gets no CI at all.
  A small `lint` + `test` workflow would be a separate template file

* **the copied README documents recipes the copied justfile does not have.** `just new`,
  `just snippets` and `just snippets-check` are inside the `# >>> skeleton-only` markers and are
  stripped from a generated justfile, but README.md is copied verbatim and still lists them under
  "Scaffolding & skeleton upkeep". This predates the tool and is a template bug, not a tool bug:
  either README.md needs the same marker treatment the justfile gets, or that section needs to move
  somewhere that is not copied

* ~~`mod.pkg`~~ — **decided: not generated.** Three of the seven surveyed libraries carry one, which
  looked at first like a convention settling into place. It is not. Odin has no package manager and no
  official one is planned, and the file itself declares nothing a consumer needs — odin-http's is
  `version`, `description`, `url`, `readme`, `license`, `keywords` and nothing else. No dependencies, no
  registry, no tool named anywhere in it. It is optional metadata for a third-party index, so a
  scaffolded library that carried one would be advertising itself to a service its author never chose.
  Anyone who wants one can add six lines

* ~~`release` and `changelog_section` leaving the `# >>> skeleton-only` block~~ — **decided: they stay.**
  Both need files a scaffolded project never receives, so they would only ever error. See Decision 4f

* a native-artifact kind (`-build-mode:shared|static`) for C consumers, deliberately excluded from
  Decision 4. It needs exported entry points, a `context` established at every boundary, a hand-written
  header and per-platform artifact names — a third kind, not a flag on this one

* pinning the Odin toolchain. CI uses `release: nightly` because the skeleton needs the `core:os`
  process API that arrived when os2 was merged in, which may be newer than the latest tagged Odin
  release. Nightly means CI can break from upstream changes with no commit here; worth revisiting once
  a release is known to carry that rewrite
