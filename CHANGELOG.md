# Changelog

Notable changes to this skeleton and to the `odin-skel` binary.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The section matching a
release tag is prepended to that release's auto-generated notes, so anything written here shows up
above the pull-request list on the GitHub release page. A tag with no matching section here fails the
release deliberately — a release with no notes is the thing this file exists to prevent.

## [Unreleased]

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

[Unreleased]: https://github.com/enerqi/odin-lang-skeleton/compare/0.2.1...HEAD
[0.2.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.2.1
[0.2.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.2.0
[0.1.2]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.1.2
[0.1.1]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.1.1
[0.1.0]: https://github.com/enerqi/odin-lang-skeleton/releases/tag/0.1.0
