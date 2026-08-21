# Changelog

Notable changes to this skeleton and to the `odin-skel` binary.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The section matching a
release tag is prepended to that release's auto-generated notes, so anything written here shows up
above the pull-request list on the GitHub release page. A tag with no matching section here fails the
release deliberately — a release with no notes is the thing this file exists to prevent.

## [Unreleased]

## [0.11.0] - 2026-08-21

### Added

- `odin-skel sync` brings a project's mechanical files back in line with the binary's templates:
  `.editorconfig`, `.gitattributes`, `.gitignore`, `.just/editor.just`, `.just/toolchain.just` and `odinfmt.json`.
  A file the project does not have yet is created, so a project scaffolded before a template existed picks it up.
  `--check` writes nothing and exits 1 on drift (the contract `embed-check` has, so a project can gate CI on
  "my mechanical files match odin-skel N"); `--dry-run` previews and exits 0; `--only=PATHS` narrows the run.
  The set is tagged `sync = true` by `SYNCABLE_FILES` in the `_embed` recipe rather than listed a second time in
  the tool, so it cannot rot against the embed list, and `just embed` now fails if a syncable name stops being a
  tracked template.
- Membership needs three properties, all of them load-bearing: no project-specific substitution, the same rendered
  output for both project kinds, and configuration rather than code. That is why the justfile (`--linker`, plus
  every recipe a project adds), README.md (its H1 and prose), LICENSE (a year), your source and the `.sublime`
  files are never touched - the `.sublime` copies pass the first two tests and fail the third, being starting
  points rather than settings. `test_syncable_templates_are_kind_independent` enforces the kind rule, which is what
  lets `sync` skip working out whether it is looking at an executable or a library.
- **The ols pin is carried over, not overwritten.** `.just/toolchain.just` holds `ols_tag` / `ols_sha256`, which
  `just bump-ols` rewrites, so the project's copy is newer than the binary's whenever anybody has run it. A sync
  splices the destination's two lines into the rendered template and fails rather than guessing if either file has
  no pin line, so it can never undo a bump or move a hand-picked pin backwards - the hazard `new --no-bump` exists
  for. `--pin=template` opts out.
- The skeleton repository itself is refused by name, `--force` included, on the presence of
  `tools/skel/templates.odin` - a path the embed excludes, so no scaffolded project has one. It is the one
  destination where a sync is pure damage: this repository's copies are the *unstripped* originals, so writing the
  rendered versions back would delete .gitattributes' `skeleton-only` block and the fragments' `snippet-exclude`
  markers, which is the text scaffolding reads. Every other guard would wave it through, since the files are
  committed and there is Odin source everywhere.
- Two further guards against a sync landing where it was not wanted. The destination must hold a justfile **and** `.odin`
  source at any depth: a justfile alone is what `add` checks and is weak evidence, since `just` is a
  general-purpose runner, so it would let a sync in the wrong terminal tab replace an unrelated project's
  `.editorconfig`. And git is the undo - any file that would change is checked with
  `git status --porcelain --untracked-files=all --ignored=matching`, and modified, untracked or ignored refuses the
  sync. `--ignored=matching` is not decoration: git searches upwards for a repository, so a project under none of
  its own is answered by an ancestor, and if that ancestor ignores the path, plain `--porcelain` reports clean
  about files git has never heard of. A directory git knows nothing about warns and proceeds; `--force` skips both
  guards.

## [0.10.1] - 2026-08-21

- minor comment refinement

## [0.10.0] - 2026-08-21

### Changed

- The justfile's helper recipes moved into two imported fragments, `.just/toolchain.just` (`fetch-ols`,
  `bump-ols`, `ensure-odinfmt` and the `ols_tag` / `ols_sha256` pin) and `.just/editor.just` (`install-sublime`,
  `sublime-build-init`, `sublime-lsp-init`, `ols-config`). The root justfile drops from 1376 to 881 lines and holds
  what a project edits as it grows; `just --list` is unchanged, because an imported recipe keeps its `[group]`. The
  imports are mandatory (`import`, not the `import?` that carries the optional `bench/` feature) so a missing
  fragment is an error rather than recipes silently vanishing. All three files share one namespace, so a fragment
  reads `linker` and `target_path` from the justfile and `.just/editor.just` reads `ols_bin` from
  `.just/toolchain.just`. `just bump-ols` now rewrites the pin in `.just/toolchain.just`, and `odin-skel new` reads
  the shipped `ols_tag` from there.
- `format` deliberately stays in the justfile: which directories are formatted, and with what flags, is a project
  decision worth having in the file you already edit. Only the *binary* is pinned, so `odinfmt_bin` and the
  `ensure-odinfmt` install guard come from `.just/toolchain.just` - which makes `format` the recipe that proves the
  namespace is shared in the justfile-reads-fragment direction.
- `odin-skel new` now runs the new project's `just format` after a bump that actually moved the ols pin, and takes
  `--no-bump`. The bump alone only relocated the problem it exists to solve: the files are written from templates
  formatted by whichever odinfmt the *skeleton* pinned, so pointing the project at a newer one left the first
  `just format` churning files the user never wrote - the same reformatting diff, moved from "whenever somebody
  bumps" to "the user's first format", once there is history for it to be noise in. Whether the pin moved is decided
  by reading `ols_tag` back out of `.just/toolchain.just`, not by parsing `bump-ols` output, and nothing runs when it
  did not move. `--no-bump` keeps the shipped pin but still installs it, for a pin chosen on purpose: `bump-ols`
  adopts whatever GitHub marks *latest*, which these date-shaped tags do not order, so it can move a hand-picked pin
  backwards - and until now the only way to refuse was `--offline`, which skipped the install too.
- CI covers the non-offline scaffold path for the first time. Every scaffold step passed `--offline`, so
  `pin_and_install_ols` - the one path that touches the network, and the one every first-time user hits - was never
  executed by CI; the `.just/` split in this release repointed `bump-ols` and `toolchain_ols_tag` at a new file, and
  nothing in CI would have noticed if that had been wrong. A Linux-only step now scaffolds without `--offline` and
  asserts the invariant rather than the outcome (which depends on what ols has released): the pin lines are intact,
  `just --evaluate` resolves, the project builds, and `just format` on the fresh scaffold changes no bytes. The
  `--offline` scaffolds additionally grep the two anchored pin lines, so a repointed path fails on every platform.
- The library kind's `examples` recipe is now `examples-check`. `examples` named its inputs and not what it did with
  them - it type checks every file in `examples/`, builds nothing and runs nothing - and next to `example NAME`, which
  does run one, the pair read as singular-versus-plural rather than run-versus-check. The `-check` suffix is what
  `embed-check` and `snippets-check` already use for the same job: a guard that fails when two things have drifted, in
  this case the examples against the API they document. `OdinJustTarget.sublime-build`'s variant is renamed with it;
  that file is installed into Sublime's global `Packages/User`, so a project scaffolded before this reads the new name
  and the variant simply fails until its justfile is updated.
- The `.just/` fragments are marker-stripped by `odin-skel new` exactly as the justfile, README and .gitattributes
  are - a prefix test rather than a fourth name in the list, so a fragment added later is covered without touching
  that code. `just snippets` concatenates the justfile and both fragments into each Justfile snippet: a snippet is
  pasted into one buffer, and one holding only the root file would emit a justfile whose mandatory imports resolve to
  nothing. The `import` lines and the fragments' header notes sit in `snippet-exclude` blocks, which is what keeps
  the concatenation a valid single file.

## [0.9.0] - 2026-08-19

### Added

- `-define:CONSOLE_UTF8` (default: on for Windows, off elsewhere) sets the Windows console to codepage 65001 at
  startup. `fmt` writes UTF-8 and `core:os` passes it to `WriteFile` unconverted, so an OEM-codepage console decoded
  it a byte at a time - `Finished 19 tests in 859.7µs` read as `859.7┬Ás`. It runs from an `@(init)` proc, not from
  `main`, because `odin test` builds take their entry point from `core:testing` and never call `main` - and the test
  runner's timing line is where the broken output was most visible. The codepage is console state rather than process
  state, so `main` restores the previous one through a defer registered *after* `defer os.exit(exit_code)` - defers
  are LIFO, so it runs first. A test build cannot restore it: `core:testing` ends through `os.exit`, which reaches
  neither a defer nor an `@(fini)`, so `just test` leaves the console on UTF-8.

## [0.8.3] - 2026-08-19

### Changed

- `odin-skel doctor` grades a tool as `.Required` / `.Recommended` / `.Optional` rather than a `required` bool. Only
  `.Required` still affects the exit code; the other two differ in the word printed, which is the point - `uv` was
  being reported as optional, and it is not optional the way `hyperfine` is. `just format` cannot run without uv at
  all, because the pinned odinfmt is fetched by a `[script]` recipe, but the project still builds without it, so
  failing `doctor` over it would be wrong in the other direction. It reads `(recommended)` with what needs it.

## [0.8.2] - 2026-08-19

### Changed

- `odin-skel doctor` now says an optional tool is optional when it is *present*, not only when it is missing: a line
  reading `ok hyperfine 1.20.0` answers "is it installed" but not "does this toolchain need it". Every non-required
  tool carries `(optional)` in both states, and a new `note` field holds the facts that are true either way - where
  `why` only ever answered "what breaks if this is absent". odinfmt gets the one that matters most: `just format`
  fetches and runs its own pinned copy regardless, so PATH matters only for a hand-run odinfmt, and a machine reported
  as missing it still formats correctly. Its check stays, because a PATH copy is what an editor picks up and knowing a
  second formatter sits in front of the pinned one beats a silent pass.

## [0.8.1] - 2026-08-19

### Fixed

- justfile: `time_release` and `time_profiles` were broken on Windows and always had been - `hyperfine -N: program not
  found`, with the binary sitting right where the message named it. Under `-N` hyperfine splits the command itself,
  and its splitter treats `\` as an escape, so `target\release\main.exe` reached `CreateProcess` as
  `targetreleasemain.exe`. The two hyperfine recipes now `replace` the separators back to forward slashes; every other
  use of `target_path` keeps the native ones, because *command* position is the case cmd.exe rejects a forward slash
  in. Dropping `-N` would also have worked and is what the error nudges you towards, at the cost of timing a shell
  start per run - which is why `-N` is there.

## [0.8.0] - 2026-08-19

### Added

- justfile: `fetch-ols` installs a pinned ols release — the language server, `odinfmt` and the `builtin/` package the
  server resolves beside its own executable — into `$ODIN_TOOLS/ols/<tag>/`, verified against the release asset's
  published SHA-256 before anything is extracted. `format` now depends on `ensure-odinfmt` and runs `{{odinfmt_bin}}`
  rather than a bare `odinfmt`, because odinfmt ships inside an ols release, has no `--version` flag, and two
  releases format the same source differently: an unpinned formatter produces a clean local tree and a CI diff on
  files nobody touched. The tag is in the install path, so the file being there is the pin being satisfied and no
  hash is recomputed on the way into every `format`; extraction stages into a `.part` directory and renames it into
  place, so an interrupted run cannot leave a half-install that the existence test would trust forever. The root is
  outside the repository — one copy serves every checkout and worktree, it survives `just clean`, and it needs no
  gitignore line. `--check` (exit non-zero, download nothing) is for CI; `--force` reinstalls.

- justfile: `sublime-lsp-init` writes the pinned server's path into the project's `.sublime-project` as an `LSP` →
  `odin` → `command` override, so the editor's analysis and the committed formatting come from one release. Sublime's
  LSP client replaces `command` outright but deep-merges `initializationOptions`, so globally configured `enable_*`
  flags survive; the path is written with a leading `$home`, which Sublime expands in `command`, so the file is
  identical on every machine. Environment variables are *not* expanded there, so a custom `$ODIN_TOOLS` root is
  written out in full. Excluded from the generated snippets alongside `sublime-build-init` for the same reason — the
  literal `$home` would be parsed as a snippet field.

- justfile: `bump-ols` rewrites `ols_tag` and all five `ols_sha256` digests from GitHub's release API - `just bump-ols`
  for the latest release, `just bump-ols <tag>` for a named one, `just bump-ols --check` to ask whether a newer one
  exists without changing anything. Copying six values by hand is where a wrong pin comes from. It edits the justfile
  and stops - no fetch, no format, no commit - because the next `format` may reformat files nobody edited and that
  diff is worth seeing before it is buried in a bump commit. Digests come from the API's per-asset `digest` field,
  falling back to downloading and hashing an asset that has none. `/releases/latest` skips prereleases, which keeps
  the continuously re-cut `nightly` tag out of a pin that only means anything if the bytes are fixed.

- `$ODINFMT` opts out of the formatter pin: `ODINFMT=odinfmt just format` uses PATH, and `ensure-odinfmt` skips the
  download when it is set. Pointing the editor at the pinned server is opt-in (`sublime-lsp-init` is a recipe, and
  `odin-skel new` scaffolds the `.sublime-project` without it), so forcing the formatter with no way out was the odd
  one of the pair.

- `odin-skel new` finishes by running the new project's own `just bump-ols` and `just fetch-ols`, so a scaffold starts
  on the current formatter with the tools already on disk. The pin the templates carry is as old as the last release
  of this binary, so without it every new project began several ols releases behind and the first bump arrived as a
  reformatting diff across files nobody edited. Both steps warn and continue - the files are written and correct by
  that point, so a scaffold that failed because GitHub was unreachable would be misreporting what happened - and each
  warning names the command that fixes it, quoting the `ols_tag` the project kept. `--offline` skips both; everything
  before that step is local, so an offline scaffold is a complete one. Neither step is reimplemented in the binary:
  the recipes live in the justfile that was just written, which is the copy the user edits and bumps from then on
  (tools/DESIGN.md, Decision 2a). The cost is that `new`'s last step needs `just` and `uv`, and a missing one is
  reported as that rather than as a failure.

### Changed

- New `toolchain` recipe group holds `fetch-ols`, `bump-ols` and `ensure-odinfmt`. That guard exists only because
  `format` runs constantly and `fetch-ols` is a `[script]` recipe, so depending on it directly would pay a uv start
  just to be told the file is already there; `sublime-lsp-init` runs once and depends on `fetch-ols` outright.
  `fetch-ols` checks all three installed parts, which is what repairs an older odinfmt-only layout at the same path.

- justfile: the comment blocks around the new recipes are summaries with a README pointer rather than a second copy of
  "Pinned tooling" - the same treatment the linker and sanitizer blocks got in 0.7.5, and for the same reason: two
  copies of a paragraph is one copy that goes stale unnoticed. Each block keeps only what is true at the line being
  edited (why the digest and not just the tag, why `USERPROFILE` before `HOME`, why the archive members are matched by
  prefix). `ensure-ols` is gone rather than shortened: `fetch-ols` already no-ops when the install is complete, so two
  platform recipes were guarding nothing for one interactive consumer, and `sublime-lsp-init` depends on `fetch-ols`
  directly. `ensure-odinfmt` stays, because `format` runs constantly and should not pay a uv start to be told the file
  is already there.

- `probe` gained a `working_dir` (`new` runs recipes in the project it just wrote) and now returns both streams when a
  command exits non-zero. Preferring stdout is right for a version banner but loses the only useful line from a failed
  command, which typically writes progress to stdout and the reason to stderr.

- `odin-skel doctor` no longer implies `just format` needs an `odinfmt` on `PATH` — it does not, it uses the pinned
  copy. The check stays, because a PATH copy is what an editor or a hand-run `odinfmt` picks up and knowing a second
  formatter sits in front of the pinned one is worth reporting. The Odin compiler is deliberately not pinned: pre-1.0
  it moves fast enough that pinning would cost more than it saves.

- justfile: every recipe now carries a `[group('...')]` attribute, so `just --list` prints them under `build`,
  `docs`, `editor`, `housekeeping`, `perf`, `qa`, `skeleton` and `test` headings instead of one alphabetical
  run of ~50 entries where `bench_cmp` sat between `build_skel_release` and `changelog_section`. The grouping is the
  only thing that changed — no recipe body, name, dependency or doc comment moved. `bench/bench.just` files its
  recipes under `perf` next to `time_release`/`time_profiles`, which keeps the feature a pure file copy: an imported
  justfile shares the importer's namespace, and a group name needs no declaration to be used. Scaffolded projects
  inherit it — a `--lib` project's `build` group empties out entirely, and an executable project shows no `docs` group
  at all, because the kind markers strip those recipes before the groups are read.

### Fixed

- CI: the pinned-linker job asserted `--linker=` had removed the per-OS default by grepping for `if os() ==`, which the
  new `exe_ext` / `ols_plat` / `home_dir` variables also match - so the assertion would have failed on every platform.
  Both it and the no-linker job's counterpart are now anchored on `ODIN_LINKER", if os() ==`, the same anchor the unit
  test uses. The three `just new` steps pass `--offline`: scaffolding otherwise ends in a release-API call and a ~5 MB
  download per matrix job, and in the pinned-linker job `bump-ols` would rewrite the justfile the greps then read.
- justfile: `format` quotes `{{odinfmt_bin}}`. The path is built from `USERPROFILE`/`HOME`, so on a machine whose
  profile directory contains a space cmd ran the first word of it and `format` was broken for that user. The
  `ensure-odinfmt` guards already quoted the same value.
- justfile: `fetch-ols` takes `{{ols_install}}` instead of re-deriving the install root from `expanduser`. The two
  resolvers agree on an ordinary machine but not where `USERPROFILE` is unset and a git-bash parent has set an MSYS
  `HOME` - and then fetch-ols installed where `ensure-odinfmt` was not looking, so every `format` re-downloaded and
  still failed to exec. One rule, applied once, in the variables.
- justfile: the snippet generator escapes `$` in the embedded source. Comments naming `$ODIN_TOOLS`, `$GITHUB_TOKEN`
  and `$GH_TOKEN` were the first `$` ever to reach a generated snippet, where Sublime reads them as fields and expands
  unknown ones to nothing - inserting the snippet deleted the names. The `${n:...}` fields the generator adds itself go
  in after the escaping and stay live.
- justfile: `bump-ols` no longer reports a differing tag as a *newer* release. These tags carry no ordering the recipe
  can rely on and `/releases/latest` can be older than a hand-picked pin, so `--check` now says the pin does not match.
- justfile: `fetch-ols` matches `builtin/` anywhere in an archive path, as it already did for the two binaries. A
  release nesting its contents one directory deeper would have found the binaries and aborted on the missing package.

### Documentation

- README, Language Server Configuration: a new section on what OLS treats as the project root, because every setting
  in that section depends on it and nothing in the section said where it comes from. It is not found by searching
  upwards from the file being edited - the editor names it once at `initialize` and OLS keeps it for the process
  lifetime. With Sublime's LSP package that means one server per window rather than per folder, rooted at the folder
  holding whichever `.odin` file started it, unchanged by adding folders later (OLS does not advertise the
  workspace-folders capability, so the notification is never sent), and blind to a `.sublime-project` file sitting
  inside one of the folders. Includes the Visual Studio mapping, since the analogy is close enough to mislead: there
  is no per-project layer, so a Sublime project is a `.sln` with exactly one `.csproj`, not a solution of several -
  which is why grouping repositories belongs in one `ols.json` as collections rather than as sibling folders.

## [0.7.5] - 2026-08-11

### Changed

- justfile: the three comment blocks the README already documents at length are now summaries with a pointer rather
  than a second copy — `linker` 33 lines to 18, the sanitizer notes 26 to 15, `time_release` 16 to 10. They restated
  `## Choosing a linker`, the `test_sanitize` entry under `## Tasks`, and `## Timing a recipe` nearly point for point,
  and two copies of a paragraph is one copy that goes stale unnoticed. Each block keeps what is only true at the line
  being edited: the four legal `-linker:` values and why `ODIN_LINKER` is an environment variable rather than a recipe
  argument (`odin` errors on a repeated flag, so a `-linker:` through `*args` would collide); the Windows ASan heap
  blind spot, because a clean run there *misleads*; `-N`'s whitespace splitting, which bites anyone adding a pipe or a
  quoted argument to the recipe body. The sanitizer block's warning about the deliberately missing
  `-linker:{{linker}}` is kept in full and now says not to "fix" it — the README never covered it, and next to every
  other build recipe the omission reads as an oversight, but restoring it produces an ASan binary that dies on startup
  with a bare `0xc000001d`. No recipe body changed; the file is 1032 lines to 998, and the generated
  `Just-Odin*.sublime-snippet` files follow it.

## [0.7.4] - 2026-08-11

### Changed

- README: the skeleton's own README renders *both* project kinds' text at once — nothing strips its markers — so a
  GitHub visitor read adjacent paragraphs as contradictions ("artifacts are output under `target`" immediately
  followed by "nothing is output under `target`"). The kind-specific paragraphs now name the kind they describe
  ("**An executable project** …" / "**A library project** …", "**In an executable project uv is optional**" / "**In
  a library uv is needed for `just examples`**"), so each pair reads as two answers rather than one wrong one, and a
  `skeleton-only` note at the top says why both are visible. The marker convention was already documented — 690
  lines further down, in a maintenance section a consumer never reaches.
- README: the "Some recipes need uv" opening was split *across* a marker, so the skeleton rendered two near-identical
  sentence fragments in a row before the sentence continued. The only difference was whether `examples` was in the
  list, so it is now one kind-neutral sentence and the marker pair is gone.

## [0.7.1] - 2026-08-10

### Added

- `bench/README.md` — the benchmark harness's documentation now ships with the harness. `odin-skel add
  bench` writes it alongside the code, so it arrives with the feature and is absent from a project that
  never adds one.
- A table of contents at the top of the README, one line per section saying why you would go there. Its
  entries carry the same `skeleton-only` / `exe-only` / `lib-only` markers as the sections they point
  at, so a scaffolded project's contents list matches the sections it actually has.

### Changed

- README: the `## Benchmarking` section is now a summary that links to `bench/README.md` — what the
  harness is, why `core:time.benchmark` is not it, and where the detail lives. Around 130 lines of
  statistics, `keep`/`opaque` rules, baseline caveats and callgrind notes moved out. It was the largest
  section in the file and documented a directory most projects never add.

- README: `## Layout` is now `## Library layout`, and no longer opens by asserting "this project is a
  library". It sits between two `skeleton-only` sections, so in *this* repository's README — an
  executable project — it read as a non sequitur, and the `--lib` paragraph that should introduce it
  never pointed at it. That paragraph now links to it and says what the executable layout is instead.
  The section could not simply be nested under `--lib`: marker blocks do not nest
  (tools/skel/template.odin), and `Creating a new project` is `skeleton-only`, so anything inside it is
  stripped from every scaffold including the library one it was written for.
- README: the opening two lines are now split by project kind. A scaffolded library previously claimed
  it was "for writing programs" and that "build artifacts are output under the `target` directory",
  eight lines above the layout section explaining that a library builds nothing.
- README: the Tasks notes still described Windows recipes as running under PowerShell, and explained
  the `[unix]` / `[windows]` split in terms of `Remove-Item` and `New-Item`. The default has been
  `cmd.exe /c` since 0.5.0; the text now gives cmd's actual `rmdir /s /q` and `md` forms and cmd's
  reason for being there (~9ms to launch against PowerShell's ~143ms, paid once per recipe *line*).
  The `mktarget_dirs` comment in the justfile argued from the same stale numbers — batching the
  directory creation saves ~36ms under cmd, not the ~600ms it claimed.

## [0.7.0] - 2026-08-10

### Added

- `odin-skel add <feature> [dir]` — optional features, written into a project that already exists
  rather than scaffolded into every one. `new` never writes them. Recipes arrive through the
  justfile's `import? '<dir>/<dir>.just'`, an optional import that is inert until the directory is
  there, so adding a feature is a file copy and removing it is deleting the directory. See
  tools/DESIGN.md, Decision 5.
- `bench` feature — a benchmark harness for either project kind. Warmup, samples across an iteration
  ramp fitted with a robust Theil-Sen line (so the per-iteration cost is the slope and the cost of
  measuring lands in the intercept), R^2 and Tukey outlier counts, `keep`/`opaque` barriers against
  dead-code elimination, JSON reports carrying every sample, and a Mann-Whitney U comparison against
  a saved baseline. Adds `just bench`, `bench_build`, `bench_cmp`, `bench_lint`, `bench_save` and
  `rerun_bench`.
- `just bench_count` / `bench_count_check` (bench feature) — per-iteration **instruction** counts under
  valgrind's callgrind, measured as the difference between running N and 2N iterations so that startup,
  setup and instrumentation cancel exactly. Counts do not drift between runs, so unlike a timing
  baseline `bench/instructions.json` is meant to be committed and can gate a merge. Requires valgrind;
  perf cannot substitute, as GitHub-hosted runners expose no PMU.
- `just time_release` / `just time_profiles` (executable kind) — whole-process timings via hyperfine,
  the second comparing the release and `-no-bounds-check` binaries.
- `doctor` now reports hyperfine and valgrind as optional tools.
- `--exact` on the benchmark binary, matching the filter as a whole name rather than a substring.
  `bench_count` uses it: otherwise counting a benchmark named `bench.parse` would also run
  `bench.parse_json` and record the sum of the two.

### Changed

- `just ols-config` now takes its collections as arguments — `just ols-config xyz=../xyz-lib
  abc=/opt/odin/abc` — instead of reading a `collection_name` / `collection_path` pair edited into the
  justfile and fed by an `XYZ_HOME` env var. Those two variables are gone, and with them the last
  `FILL IN:` in the file. Consequences:
  - **More than one collection.** `ols.json`'s `collections` is an array and always was; the old recipe
    could only ever write one entry into it.
  - **Other `ols.json` settings survive.** The recipe now reads the file back and rewrites only
    `collections`, so `enable_document_symbols`, `checker_path` and friends are no longer destroyed on
    every regenerate. The arguments are the whole collection list, so a rerun is idempotent and there
    is no add/remove pair of commands to keep straight. With no arguments it prints the current list.
  - **Relative paths are documented as the better default.** OLS resolves a relative collection path
    against the project root, so `../xyz-lib` gives an `ols.json` that is the same on every machine and
    can be committed — the `.gitignore` entry only exists for the absolute-path case. (OLS does no
    variable substitution in `ols.json`, which is why a recipe generates it at all; a leading `~` is
    the one exception, and it is expanded on Linux and macOS only.)
  - **Fixes a Windows crash.** The old recipe interpolated the path into a Python raw string, so a
    collection path ending in a backslash (`C:\odin\libs\`) escaped the closing quote and failed with a
    syntax error.

## [0.6.0] - 2026-08-09

### Added

- **`odin-skel new --lib` scaffolds a library instead of an executable** — an Odin source package that
  other projects clone or copy into their tree and import. The destination directory *is* the package,
  which is what six of the seven surveyed community libraries do (odin-http, odin-ldtk, toml_parser,
  back, odin-cli, odin-rure; odin-mimalloc is the exception). A `-collection:` flag is the consumer's
  choice about their own vendor directory, not something a library repository declares.

  `--pkg=NAME` names the package; without it the project name is turned into a legal Odin identifier
  (`odin-toml` → `odin_toml`), since a directory name frequently is not one. A name that cannot be
  repaired that way is rejected with a reason rather than mangled: a leading digit, an Odin keyword,
  non-ASCII, `main` (the examples are `package main`, and two packages of one name in a build is an
  error), a leading underscore, or a trailing target name.

  The last two are subtle, and both follow from the package file being named after the package. Odin
  refuses to compile a source file whose name begins with `_`, and it reads a trailing `_js` / `_linux`
  / `_amd64` in a *file name* as a build tag — so `--pkg=odin_js` would write `odin_js.odin` and the
  library's contents would be invisible on every target but one. Both used to scaffold cleanly and fail
  on the first `just check`.

  A library project gets `just check`, `just example NAME`, `just examples` and `just doc` in place of
  the `run_*` / `rerun_*` build ladder, `sanitize` and `diagnose`, none of which have anything to build.
  Examples are single-file `main` packages under `examples/`, built with `-file`; note that in `-file`
  mode a relative import resolves against the file's own directory, so an example imports `".."` and
  not the `"../.."` that a deeper `examples/<name>/main.odin` layout would need.

- The justfile and README now carry `exe-only` / `lib-only` marker blocks alongside the existing
  `skeleton-only` ones, so one template serves both project kinds rather than two copies drifting
  apart. `just embed` records which kind each template file belongs to, and `just embed-check` verifies
  the counts.

- `OdinJustTarget.sublime-build` gained `check` / `example basic` / `examples` / `doc` variants beside
  the existing `run_*` ones. It is deliberately *not* split per kind: `just install-sublime` copies it
  into Sublime's global `Packages/User`, where it matches on `source.odin` and serves every Odin
  project on the machine, so it has to carry both kinds' recipes.

- A third generated snippet, `.sublime/Just-Odin-lib.sublime-snippet` (tab trigger `odinlib`), fills in
  a library justfile. Unlike the build systems, a justfile snippet *is* one project kind's justfile, so
  it cannot be shared — `Just-Odin` (trigger `odin`) stays the program one.

  All three snippets now also carry a `<description>`, which is what Sublime shows beside the trigger in
  the completion popup and what Tools → Snippets… lists them under. A `tabTrigger` alone only helps
  somebody who already knows to type it.

- `just lint_lib_template` / `just test_lib_template`, wired into CI. The library template is a real
  package in this repository (`mylib/`) rather than inert text, so it is linted, tested and its example
  actually run on every commit — the same property that keeps the executable template honest. CI also
  scaffolds a library end to end on all three platforms and builds it.

## [0.5.0] - 2026-08-09

### Changed

- **Every `[script]` recipe now runs on `uv run --no-project -p 3.14 python` instead of a bare
  `python`, pinned once via the justfile's new `set script-interpreter`.** A bare `python`/`python3`
  on `PATH` was never a reliable cross-platform lookup: on Windows via Scoop it is whatever version
  was last `scoop install`ed with no pin, and on Linux it is whatever the distro shipped. uv resolves
  (and downloads if missing) the same pinned interpreter on every platform instead, so uv becomes the
  one tool these recipes depend on rather than an unpinned system python.

  `--no-project` matters even though this repo has no `pyproject.toml`: without it, `uv run` walks up
  from the working directory looking for one to treat as the project root, and if it ever found a
  stray one two directories up it would silently start syncing/using *that* project's venv and pinned
  version instead of the one here.

  In a scaffolded project this only affects `ols-config`, `install-sublime` and `sublime-build-init` —
  none of `run_*`/`test*`/`lint`/`format` touch Python, so uv is optional there, not a new hard
  dependency alongside `just`. In this repo it also covers the skeleton-only `new`, `release`,
  `changelog_section`, `_embed` and `_snippets` recipes.

  CI needed a matching change: GitHub's runners ship a system python (which is what let the old bare
  `[script("python")]` recipes work by accident) but not uv, so `ci.yml` and `release.yml` each gained
  an `astral-sh/setup-uv` step ahead of every job that runs a `[script]` recipe.

### Added

- `odin-skel doctor` now also checks for `uv`, optional like `odinfmt` and `git` — it lets
  `install-sublime`, `sublime-build-init` and `ols-config` run without a system python (see above).

## [0.4.4] - 2026-08-07

### Changed

- **Documented that `-sanitize:address` does not detect heap errors on Windows.** The recipes shipped, the
  README sold them, and nothing said that the check most people reach for silently does not fire there. A
  clean `just sanitize` on Windows rules out stack bugs only.

  Odin's allocator calls `HeapAlloc` on Windows (`base/runtime/heap_allocator_windows.odin`) rather than the
  `malloc` it uses on Unix (`heap_allocator_unix.odin`). ASan's redzones come from intercepting the
  allocator, so on Windows it never sees the allocation and has nothing to guard. The
  `interception_win: unhandled instruction` line these builds print is that limitation announcing itself.

  Measured by writing one byte past a 16-byte `make([]u8, 16)`:

  | overflow offset | Linux | Windows |
  | --- | --- | --- |
  | +16 | not reported (still inside the allocator's slack, on both) | not reported |
  | +24 | `heap-buffer-overflow` | nothing |
  | +32 | `heap-buffer-overflow` | nothing — process died with no ASan output at all |
  | +64 | `heap-buffer-overflow` | nothing |
  | +256 | `heap-buffer-overflow` | nothing |

  Stack overflows are caught on both platforms, because that instrumentation is compiler-inserted rather
  than interception-based. The +16 row is worth keeping in mind for anyone writing their own probe: the
  allocator returns more than the requested 16 bytes, so a write there is genuinely in bounds and proves
  nothing either way.

  The README now also records that the Linux sanitizer runtime is a separate install — without it the link
  fails on a missing `libclang_rt.asan.a`, which on Debian/Ubuntu with clang 21 is `libclang-rt-21-dev`.

  No behaviour change; the recipes are untouched. A CI step asserting *detection* rather than
  compile-link-run was considered and dropped: it would have to encode "expect a heap catch on Linux, expect
  silence on Windows", which bakes a bug in as expected behaviour.

## [0.4.3] - 2026-08-07

### Added

- set `justfile` `minimum-version` explicitly to 1.49 as required by the user defined functions

## [0.4.2] - 2026-08-07

### Changed

- **`windows-shell` is now `cmd.exe /c` instead of PowerShell. `just run` drops from ~497ms to
  ~368ms and `just rerun` from ~178ms to ~28ms.** 0.4.1 moved only `mktarget_dirs` off PowerShell;
  measuring the rest showed the same tax on *every* recipe line, because just launches a fresh shell
  per line. Bare `<shell> exit` under hyperfine:

  | shell | startup |
  | --- | --- |
  | `cmd.exe /c` | ~9ms |
  | `nu -c` | ~41ms |
  | `powershell.exe -NoLogo -NoProfile -Command` | ~143ms |

  End to end that was ~178ms per recipe line under PowerShell against ~45ms under cmd. The worst case
  was `rerun_*`, whose entire reason to exist is skipping the compile Odin has no cache to avoid, and
  which spent ~178ms of shell startup to launch a binary that prints one line. For `just run` the
  overhead above Odin's own ~299ms of work fell from ~198ms to ~69ms.

  This also settles the portability question the other way. nu was dropped as the default because it is
  absent from stock machines and GitHub's windows runners; cmd is *more* portable than the PowerShell
  that replaced it — on every Windows, no install, and no profile to make a recipe unreproducible, so
  the `-NoProfile` guard is moot — while being ~16x faster to start. The one real cost is that cmd is a
  poor language for a multi-line recipe, which does not bite here: every Windows recipe body is a
  single command, and anything with logic already routes to `[script("python")]`.

  Consequently `mktarget_dirs` no longer needs 0.4.1's `[script("cmd.exe", "/c")]` + `[extension]`
  override, and shedding the temp file that attribute pair required took it from ~27ms to ~21ms.

- **Every build output path now goes through a `target_path(dir, name)` function** rather than being
  spelled out per recipe. It uses `join`, deliberately not the `/` operator: `/` always emits a forward
  slash, and while Odin accepts either inside an `-out:` *argument*, cmd.exe rejects a forward-slash
  path in *command* position — `target/debug/main.exe` as a recipe's command fails with `'target' is
  not recognized`, and quoting does not save it. `join` uses the native separator, so the five
  `rerun_*` recipes work on both platforms from one definition instead of needing `[windows]`/`[unix]`
  pairs. The `./` prefix they used to carry is gone: bash treats any path containing a slash as a path
  rather than a `PATH` lookup, so it was never load-bearing.

- `clean` on Windows uses `if exist target rmdir /s /q target`, since PowerShell's `Remove-Item` is no
  longer available. The `if exist` guard matters for the same reason the old `Test-Path` one did:
  `rmdir` exits non-zero on a missing path, which would fail the recipe on an already-clean tree.

### Fixed

- **`just test1` never worked: there is no `-test-name:` compiler flag.** It failed with
  `Unknown flag: 'test-name'` before building anything. Test selection is a `core:testing` define, so
  the recipe now passes `-define:ODIN_TEST_NAMES={{name}}`, which
  [the testing docs](https://odin-lang.org/docs/testing/) give as
  `ODIN_TEST_NAMES=<package.test_name,test_name,...>`. The value is a comma-separated list and the
  package prefix is optional, so `just test1 one,two` runs exactly those two.

  Nothing in CI exercises `test1`, which is why a recipe that could never have worked shipped anyway.

- **`just test_sanitize` died on startup on Windows** with a bare `0xc000001d`
  (illegal instruction) and no usable stack. Cause was `-linker:{{linker}}`, which on Windows defaults
  to `radlink`: a sanitizer has to interpose on the runtime and radlink's output does not survive it.
  Both `sanitize` and `test_sanitize` now omit the linker pin and let Odin choose, on the same
  reasoning `build_skel_release` already used — link speed is worth nothing on a diagnostic run, and
  pinning it turned these recipes into a report about the linker rather than about your code.

  Confirmed against the pre-existing path spelling, so this was never related to the `join` change
  above.

- **CI now runs the two sanitizer steps on Windows as well as Linux**, which is the gap that let the
  bug above ship: they were pinned to `ubuntu-latest`, where the linker resolves to `default`
  regardless, so no amount of green CI could have caught a radlink-only failure. macOS stays excluded —
  ASan there wants the Xcode runtime rather than the LLVM one `setup-odin` provides, so it would be
  platform noise rather than signal.

## [0.4.1] - 2026-08-07

### Changed

- **`mktarget_dirs` on Windows now runs under `cmd.exe` instead of PowerShell: ~189ms to ~32ms.**
  Every `run_*`, `test*` and `diagnose` recipe depends on it, so the saving lands on every iteration.
  The directory creation was never the slow part — hyperfine puts `powershell.exe -NoProfile -Command
  exit` at ~149ms against ~40ms for the actual `New-Item` work, so most of the recipe was paying for
  a shell to start. `[script("cmd.exe", "/c")]` plus `[extension(".cmd")]` override the shell for this
  one recipe without touching the file's `windows-shell` setting, and cmd starts in ~10ms.

  Worth recording the measurement that did *not* pay off: scoping the recipe to only the one
  directory a given build needs saves ~5ms of that ~40ms and nothing of the ~149ms. The cmd body uses
  `if not exist` rather than swallowing `md`'s "already exists" with `2>nul`, so a genuine failure
  still exits non-zero.

## [0.4.0] - 2026-08-07

### Changed

- Backtraces now come from `core:debug/trace` instead of the out-of-tree
  [laytan/back](https://github.com/laytan/back). The package was upstreamed into the standard library
  by the same author, so this is the same implementation under renamed APIs — with the sibling
  `../back` checkout requirement gone. That checkout was the only reason the feature shipped disabled
  behind a commented-out import.

  It also removes a dependency that had become actively dangerous: merely linking the current `back`
  into an `-o:speed` build without `-debug` segfaulted before `main`'s first statement, on any
  linker, with no calls into it at all. `core:debug/trace` was exercised at `-o:none`, `-o:minimal`,
  `-o:speed` and `-o:speed -debug` and never crashed; without debug info it degrades to bare
  `0x...` addresses rather than failing.

- **Backtraces on asserts and segfaults are now on by default and need no define.** They cost nothing
  until the program is already dying — a stack is captured at an assert or a fault, never during
  normal work — so the compile-time flag they used to share bought nothing. Set `ODIN_BACKTRACE` to
  `0`, `false` or `off` to turn them off for a run, in the spirit of `RUST_BACKTRACE` but defaulting
  on, since the audience for a skeleton is whoever is developing the program rather than whoever is
  running a shipped binary. Symbol names still require `-debug`.

- **BREAKING: `BACKTRACE_ENABLE` and `TRACKING_ALLOCATOR_ENABLE` are replaced by one three-state
  `-define:TRACKING_ALLOCATOR=off|basic|backtrace`.** Two booleans described four combinations of
  which only three meant anything — `TRACKING_ALLOCATOR_ENABLE=false` with
  `TRACKING_ALLOCATOR_BACKTRACE=true` compiled silently and tracked nothing, with no diagnostic. One
  setting cannot express that state, and a misspelled value now fails at compile time with
  `#panic("TRACKING_ALLOCATOR must be \"off\", \"basic\" or \"backtrace\"")` rather than quietly
  selecting the `off` arm.

  Measured per allocation, 200k × 32 bytes:

  | value | allocator | cost |
  | --- | --- | --- |
  | `off` | the raw allocator | ~44 ns |
  | `basic` | `mem.Tracking_Allocator` | ~599 ns (13.6x), +72 bytes per live allocation |
  | `backtrace` | `trace.Tracking_Allocator` | ~1385 ns (31x), +208 bytes per live allocation |

  `backtrace` buys caller attribution: `basic` reports every leak from a shared helper at the same
  `#caller_location`, while the capture says *which* caller asked for the memory. Both tracked modes
  also take a mutex on every alloc and free, so the cost lands hardest on allocation-heavy and
  multi-threaded code and is close to invisible for a program that allocates at startup and then
  works out of arenas.

- **The tracking allocator now defaults to `basic` under `-debug` and `off` otherwise**, instead of
  being unconditionally on. Previously `run_release` and `run_release_nochecks` — the recipes whose
  entire purpose is measuring — ran with a 13.6x allocation tax and a lock in the middle of it.
  Diagnostics now follow `-debug`, the same line the backtrace symbols already fell on, and the
  define still overrides in both directions: `-define:TRACKING_ALLOCATOR=backtrace` on a release
  build is exactly right for a leak that only reproduces optimized.

  The two-branch structure is kept rather than collapsed onto one always-capturing path, so the
  default build keeps the cheap `mem.Tracking_Allocator`. The branch has to be a compile-time `when`
  regardless: the two arms return different types (`^mem.Tracking_Allocator` vs
  `^trace.Tracking_Allocator`).

### Removed

- **`MIMALLOC_ENABLE`**, its `when` block, its doc bullet and the commented-out
  `// import mi "../odin-mimalloc/mimalloc"`. It shared the flaw this release removed from `back`: a
  define whose feature could not work without the reader first cloning a sibling repository the
  skeleton has no way to provide. A scaffolded project got a switch that did nothing until it was
  wired up by hand, which is the opposite of what a skeleton is for.

  [odin-lang/Odin#6909](https://github.com/odin-lang/Odin/pull/6909) ("feoramalloc") would land a
  faster allocator directly in `base:runtime` as the default heap — no import to swap, no
  `context.allocator` line to write, the default simply gets faster. That makes the block redundant
  by a second route, though the removal does not depend on it merging. If a project wants mimalloc
  specifically, one import and one assignment in `main` is a smaller thing to write than a dead
  define is to carry.

- **`TIME_PROGRAM_DURATION_ENABLE`**, along with `log_program_duration` and the `core:time` import —
  about fifteen lines of `main.odin` replaced by a flag just already has. `just --time <recipe>`
  reports a recipe's duration (`JUST_TIME=true` as an env var, which wants `true` rather than `1`),
  and the `rerun_*` family exists precisely so that timing excludes the compile Odin has no cache to
  avoid.

  The removed number was also easy to over-trust. It measured only the inside of `main`, deliberately
  stopping before profiler and allocator teardown: 42.3µs for a hello-world whose process took ~31ms
  of wall clock to start and stop, so ~0.1% of the real cost. Anything long enough for that gap not
  to matter is long enough for `just --time` to answer the same question with no code, and anything
  shorter wants `time.now()` / `time.since` around the specific phase, or the spall profiler — both
  better targeted than a whole-of-`main` figure.

### Added

- `register_segfault_handler` at the bottom of `main.odin` — the one thing `core:debug/trace` does
  not provide. Derived from back's handlers (MIT, © 2023 Laytan Laats) and rewritten against
  `trace.capture` / `resolve` / `print`. `SetUnhandledExceptionFilter` on Windows, `SIGSEGV` on
  POSIX, and neither branch on wasm/freestanding, where it compiles to a no-op. It formats its trace
  through an arena over a 16 KiB *stack* buffer: the usual reason to be in a segfault handler is heap
  corruption, and calling the global allocator there turns a reported crash into a second crash
  inside the handler.

  It earns its place by covering the failures that otherwise print *nothing at all* — a nil deref or
  a divide by zero exits with a bare code and no output. Asserts and type assertions already trace
  through `trace.assertion_failure_proc`, and a bounds check prints its own `file(line:col)`.

  Kept in `main.odin` behind `when ODIN_OS == ...` rather than in `#+build`-tagged files, so a
  scaffolded project stays a single `.odin` file. The cost is importing `core:sys/windows` and
  `core:sys/posix` in every build and three `_ ::` lines to stop the off-platform one failing the
  unused-import vet check. Verified clean under the full lint flags for `windows`, `linux_amd64` and
  `darwin_arm64`.

### Fixed

- A trap for anyone adapting the operational setup, now documented in `main.odin` where it bites:
  Odin's `context` is scope-local, so `if cond { context.assertion_failure_proc = ... }` reverts when
  the block exits and has no effect on anything `main` calls afterwards. The old `when` form was
  immune — `when` is compile-time and introduces no scope — so the hazard only appeared when the
  check became a runtime one. The assignment now sits in `main`'s own scope.

## [0.3.1] - 2026-08-07

### Changed

- README sections reordered to follow the path a reader takes: install `odin-skel`, scaffold a
  project, then drive it with `just`. "Choosing a linker" was sitting between the Quality and
  Housekeeping task bullets, so those later bullet groups read as if they belonged to it; it is now
  its own section after Tasks. It stays outside the `skeleton-only` markers — the `linker` variable
  and `ODIN_LINKER` override exist in a scaffolded project's justfile too. The two
  maintainer-only topics, snippet generation and cutting a release, are grouped under a new
  "Skeleton maintenance" section at the bottom, which `just new` strips like the rest.

## [0.3.0] - 2026-08-07

### Fixed

- `odin-skel new` no longer copies skeleton-only `.gitattributes` rules into a scaffolded project.
  0.2.1 added `linguist-generated` markings for `tools/skel/templates.odin` and the two
  `.sublime-snippet` files, but `.gitattributes` was copied verbatim, so every generated project got
  a rule for `tools/` — a directory scaffolding never creates — alongside a comment citing `just
  embed` and `just snippets`, recipes already stripped from its justfile. `.gitattributes` now joins
  the justfile and README.md as a template whose `>>> skeleton-only` blocks are stripped, reusing the
  marker mechanism those two already had rather than inventing a second one. Covered by a unit test
  against the embedded copy and a leak check in CI's end-to-end scaffold step, both mirroring the
  justfile's.

### Added

- Linker selection. A `linker` variable at the top of the justfile feeds `-linker:` to every recipe
  that links, defaulting to `radlink` on Windows — it ships with the Odin toolchain, so it needs no
  install — and to `default` elsewhere. Odin has no build cache and relinks on every `just run`, so
  this is a cost paid on each iteration. `ODIN_LINKER=<value>` overrides it for a single command;
  it is an environment variable rather than a recipe argument because `odin` errors on a repeated
  flag, so a `-linker:` passed through a recipe's extra args would collide.

  Availability is per-platform and the two failure modes differ. Odin knows mold is Linux-only and
  refuses it elsewhere before doing any work. `lld` gets no such check: Odin accepts it everywhere,
  but on a stock macOS the link runs through Apple's clang, which ships no lld and rejects
  `-fuse-ld=lld` as an invalid linker name. `radlink` is Windows-only. Both the justfile and the
  README spell this out per value.

  Not a free win in every configuration, and the justfile and README say so: neither radlink nor
  mold is an *incremental* linker, while MSVC `link.exe` is, so with `-use-separate-modules` (which
  `-lto` implies) an incremental relink of one changed module can beat a faster full link. Stock
  Odin builds are single-module and give LTO little to work with, and statically linked external C
  libraries do not get LTO regardless. `-lto` on Windows additionally *requires* `-linker:lld` and
  exits 1 against anything else pinned, which is what the override exists for.

- A scaffolded project's README now opens with its own `# <name>` H1 and two blank lines to write
  into, with everything the skeleton carried demoted one level beneath it. The copied README is
  reference material about the tooling, not the project's front page — left alone it titled someone
  else's project "Odin Programming Language Project Skeleton" and offered nowhere obvious to say
  what the project actually is. Only ATX headings outside fenced code blocks are touched, so a
  `# comment` in a `sh` block stays shell; a heading already at H6 is left alone rather than growing
  an invalid seventh `#`; and anchors are unaffected because markdown derives them from heading text
  rather than level.

- The README's task reference gained a `## Tasks` heading. `## Quick start` above it is
  skeleton-only — it is about cloning and scaffolding — so without this the whole task list had no
  heading of its own, and `Choosing a linker` sat two levels below its nearest ancestor in the
  generated file.

- `odin-skel new --linker=<default|lld|radlink|mold>` pins that linker for every platform in the
  generated project, rewriting the justfile's default assignment. `--linker=v` and `--linker v` are
  both accepted, the value is validated before anything touches the filesystem, and a justfile that
  no longer carries the assignment fails the scaffold rather than silently ignoring the flag.
  `just new` grew a flag passthrough so it works there too.

- `.sublime/**` is marked `linguist-vendored=true`, keeping editor configuration out of the
  repository's language statistics. Linguist reads `.sublime-build` / `.sublime-project` as JSON with
  Comments and `.sublime-snippet` as XML, which visibly skews the language bar on a project this
  small. `vendored` rather than `generated` because these are hand-written — they are simply not the
  project's own code, and that stays true after `odin-skel new` copies them, so unlike the
  `linguist-generated` rules this one is deliberately not skeleton-only. The trailing `**` is
  load-bearing: `.gitattributes` borrows gitignore's pattern syntax but not its directory semantics,
  so a bare `.sublime/` would silently match nothing.

## [0.2.1] - 2026-08-07

### Fixed

- `ols.json` is now gitignored. The README and the `ols-config` recipe both told you to ignore it —
  it holds a machine-specific absolute path to your collection — but `.gitignore` never listed it,
  so the first `just ols-config` left a file staged for commit that would break every other clone.

- `.gitignore` and `.gitattributes` covered the Windows artifact names only (`.exe`, `.pdb`, `.obj`,
  `.lib`, `.exp`), so on Linux and macOS an `odin build -build-mode:obj|shared|static` left `.o`,
  `.so`, `.dylib` and `.a` files untracked-but-visible, and a `-debug` build on macOS left a `.dSYM`
  bundle. `.dll` was missing from `.gitignore` despite `.gitattributes` already treating it as
  binary. Both lists now carry the whole matrix, annotated with which extension each platform
  produces for which build mode. The default executable is still uncatchable on Linux and macOS,
  where it takes the name of the package directory — the skeleton avoids it by writing `main.exe` on
  every platform.

### Added

- CI runs `just sanitize address` and `just test_sanitize address` on Linux. The skeleton ships five
  sanitizer recipes and the README recommends them, but nothing proved they still compiled — a
  broken flag would have been found by whoever first reached for one. Linux only: AddressSanitizer
  is the one of the three with broad support, and it is the last pair of steps in the job so a
  missing ASan runtime cannot cut short the scaffold and doctor checks that gate a release.

- Crash dumps (`core.<pid>`, `vgcore.*`) and OS droppings (`.DS_Store`, `Thumbs.db`) are ignored.
  The dumps matter here because the skeleton ships sanitizer recipes and a segfault handler.

- `tools/skel/templates.odin` and the two `.sublime-snippet` files are marked
  `linguist-generated=true`, so GitHub collapses their diffs and drops them from the repository's
  language statistics. All three are generated copies; without this a regenerated listing buries the
  real change in a review.

## [0.2.0] - 2026-08-07

### Added

- One-shot installs. On Linux and macOS, `packaging/install.sh` (`curl … | sh`) downloads the release
  archive, verifies it against the published `SHA256SUMS`, and places the binary in `~/.local/bin`.
  It does not edit shell profiles — it prints the `PATH` line to add if the directory is missing.
  On Windows, `packaging/scoop/odin-skel.json` can be installed by URL without a custom bucket, and
  scoop then handles `PATH`, update and uninstall.
- The scoop manifest is generated during the release and published as an asset, so
  `scoop install https://github.com/enerqi/odin-lang-skeleton/releases/latest/download/odin-skel.json`
  always resolves to the newest version. A committed manifest could not do this: its hash cannot
  exist until the archives do, which is after the tag, so it would always need a follow-up commit
  landing after the tag it describes.

## [0.1.2] - 2026-08-07

### Changed

- `mktarget_dirs` creates every build directory in one command instead of one per line. just starts a
  new shell for each recipe line, so the old version paid six shell launches; on Windows that is
  ~1.1s of PowerShell startup before *every* build, since every `run_*`, `test*` and `diagnose`
  recipe depends on it. Measured at 5.7x faster (1.125s -> 198ms).

## [0.1.1] - 2026-08-07

### Added

- `just release VERSION` promotes the Unreleased section to a dated version heading and fixes the
  link definitions. It edits `CHANGELOG.md` and stops — no staging, committing or tagging — and
  refuses to run twice for a version or when there is nothing to release.

### Changed

- The release workflow checks that a tag has changelog notes before installing the Odin toolchain,
  so a missing section fails in seconds rather than after all four platforms have built and
  uploaded.

- Release assets are archives (`.tar.gz`, `.zip` on Windows) rather than bare binaries. GitHub
  requires asset names to be unique within a release, so the platform now lives in the archive name
  and the binary inside is plainly `odin-skel` — nothing to rename after extracting. tar also
  preserves the executable bit, so `chmod +x` is no longer needed, and the licence travels with the
  binary.

### Fixed

- The release workflow no longer targets the retired `macos-13` runner, which sat queued
  indefinitely and blocked the whole release because publishing waits on every target. macOS builds
  are now pinned to `macos-15` / `macos-15-intel` rather than tracking `-latest`, so a published
  binary's minimum macOS version cannot rise without a commit.

## [0.1.0] - 2026-08-06

First release of `odin-skel`, the binary that scaffolds a project without cloning this repository.

### Added

- `odin-skel new <dest> [name]` — scaffolds a project from templates compiled into the binary, so it
  needs no network access and no git clone. Refuses a destination that exists and is non-empty,
  ignoring `.git`.
- `odin-skel doctor` — checks for `odin`, `just`, `odinfmt` and `git`; reports what is missing, what
  is too old, and where to get it. Exits non-zero only for required tools.
- `odin-skel version` / `help`.
- Release builds for `linux-x86_64`, `windows-x86_64`, `macos-arm64` and `macos-x86_64`, published
  with a `SHA256SUMS` file. The binaries are unsigned; see the README for the macOS Gatekeeper and
  Windows SmartScreen steps.
- CI across Linux, Windows and macOS, including an end-to-end check that scaffolds a project and
  builds it.
- Build tiers `run_fast_debug` (`-o:minimal -debug`), `run_release_debug` (`-o:speed -debug`) and
  `run_release_nochecks` (`-o:speed` with `-no-bounds-check`, `-disable-assert` and
  `-no-type-assert`), each writing to its own `target/` sub-directory.
- `just sanitize` and `just test_sanitize` for AddressSanitizer, MemorySanitizer and
  ThreadSanitizer builds.
- `just embed` / `just embed-check` to generate and verify the template list compiled into the
  binary, mirroring the existing snippet generator.

### Changed

- The Windows shell for `just` is now Windows PowerShell rather than nushell. PowerShell 5.1 ships
  with Windows, so recipes run on a stock machine and on CI runners with nothing to install.
- `just lint` adds `-vet-tabs`, which is the only compiler-side enforcement of `.editorconfig`'s
  `indent_style = tab` and is not implied by `-strict-style`.
- Line endings are pinned to LF in the working tree as well as the index, matching the Odin
  project's own `.editorconfig`, and `odinfmt.json` sets `newline_style: "LF"` to match.
- `-show-timings` is limited to `just diagnose` rather than every build recipe.
- Build tiers renamed to snake_case: `fastdebug` is now `fast_debug`, `releasedebug` is now
  `release_debug`.

### Fixed

- `just format` no longer leaves files with mixed line endings. odinfmt defaults to CRLF output and
  emits mixed endings when fed an LF file, which affected every platform, not just Windows.
- Scaffolding into a directory that already exists now works on Linux and macOS, where
  `os.make_directory_all` reports `Exist` for a directory that is already present.
- The Sublime build files no longer duplicate the `fastdebug` variants under a `debug` name, and
  their `debug` tier now uses `-o:none` to match what `-debug` actually implies.

[Unreleased]: https://github.com/enerqi/odin-lang-skeleton/compare/0.11.0...HEAD
[0.11.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.11.0
[0.10.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.10.1
[0.10.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.10.0
[0.9.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.9.0
[0.8.3]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.8.3
[0.8.2]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.8.2
[0.8.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.8.1
[0.8.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.8.0
[0.7.5]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.7.5
[0.7.4]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.7.4
[0.7.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.7.1
[0.7.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.7.0
[0.6.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.6.0
[0.5.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.5.0
[0.4.4]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.4.4
[0.4.3]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.4.3
[0.4.2]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.4.2
[0.4.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.4.1
[0.4.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.4.0
[0.3.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.3.1
[0.3.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.3.0
[0.2.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.2.1
[0.2.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.2.0
[0.1.2]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.1.2
[0.1.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.1.1
[0.1.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.1.0
