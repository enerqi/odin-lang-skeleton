# `odin-skel` — design decisions

Design notes for a binary front-end to this skeleton, so that starting a new Odin project does not
require cloning this repository by hand.

Nothing here is built yet. This file records the decisions that were settled up front because they
constrain everything downstream; the open items are listed at the end.

Status: **accepted.** Phases 1–3 are implemented — `version`, `doctor`, `new` with embedded templates,
and CI plus tagged releases for four targets. Phase 4 (update check, `--from-git`, self-update) is
not.


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

The templates are roughly fifteen small text files. Embedding them deletes the cache directory, the
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


## Decision 3 — repository layout (a): the repo root stays the template

The tool's source lives under `tools/`. The repository root remains a working Odin project.

```
.                      <- the template; also a project you can clone and run as-is
├── main.odin
├── justfile
├── odinfmt.json
├── .sublime/
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

```python
EXCLUDED_PREFIXES = ("tools/",)
```

`just new` reports the skipped count so an accidental exclusion is visible rather than silent. **Any
new skeleton-tooling directory must be added to that tuple and to the tree above.**

Note that `.gitignore`-style exclusion does not work here: `just new` copies from `git ls-files`, so
`tools/` has to be tracked (it is source code) while still being skipped at copy time. The exclusion is
therefore explicit in the recipe rather than inherited from git.


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
* `odin-skel update` (self-update). Windows cannot overwrite a running `.exe`, so the binary must
  rename itself before writing the replacement and clean up on next launch. This constrains where the
  binary may install itself, so it is worth designing before it is built
* update *check* cadence and opt-out (`ODIN_SKEL_NO_UPDATE_CHECK=1`); must never block or fail a
  command
* minimum `just` version to enforce. The README states 1.32; `just --version` prints `just 1.46.0`, so
  parsing is trivial

* a starter CI workflow *for scaffolded projects*. The skeleton's own `.github/` is excluded from the
  template because it checks skeleton-only things, so a generated project currently gets no CI at all.
  A small `lint` + `test` workflow would be a separate template file

* **the copied README documents recipes the copied justfile does not have.** `just new`,
  `just snippets` and `just snippets-check` are inside the `# >>> skeleton-only` markers and are
  stripped from a generated justfile, but README.md is copied verbatim and still lists them under
  "Scaffolding & skeleton upkeep". This predates the tool and is a template bug, not a tool bug:
  either README.md needs the same marker treatment the justfile gets, or that section needs to move
  somewhere that is not copied

* pinning the Odin toolchain. CI uses `release: nightly` because the skeleton needs the `core:os`
  process API that arrived when os2 was merged in, which may be newer than the latest tagged Odin
  release. Nightly means CI can break from upstream changes with no commit here; worth revisiting once
  a release is known to carry that rewrite
