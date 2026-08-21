package skel

import "core:fmt"
import "core:os"
import "core:strings"

// Bumped by the release process. `dev` marks a binary built straight from a working tree, which is
// also what `version` reports when nobody has stamped a release in.
VERSION :: #config(SKEL_VERSION, "dev")

// Subcommands the binary implements itself. The passthrough MUST refuse to forward any of these to
// `just`, otherwise `just new` -> `odin-skel new` -> `just new` ping-pongs forever once a name is
// added here but the dispatch below forgets it (see tools/DESIGN.md, Open items / Loop guard).
OWNED_COMMANDS :: []string{"new", "add", "sync", "version", "doctor", "help"}

HOMEPAGE :: "https://github.com/enerqi/odin-lang-skeleton"

// A released binary is downloaded on its own, with no repository and no README next to it, so this
// has to answer "what is this and what do I type" without anything else to hand.
USAGE ::
	`odin-skel - scaffold a new Odin project

Creates a ready-to-build Odin project: a justfile with debug/release build tiers, editor config,
.gitignore/.gitattributes, and Sublime Text build systems. The project template is compiled into
this binary, so scaffolding needs no network access and no git clone.

Usage:
  odin-skel <command> [arguments]

Commands:
  new <dest> [name]   Scaffold a project into <dest>. The directory must not exist, or must be
                      empty apart from .git. [name] defaults to the directory's own name and is
                      used for the .sublime-project file.
      --lib           Scaffold a library - an Odin source package a consumer clones or copies into
                      their own tree, frequently renaming it - instead of an executable. The
                      destination directory IS the package: they import it by the path they put it
                      at, or mount that directory as a collection and import it by name. Which of
                      the two is their choice, not the library's. Examples live in examples/ as
                      single-file programs.
      --pkg=<name>    The library's package name. Defaults to the project name with -, . and
                      spaces turned into underscores, since a directory name like "odin-mylib" is
                      not a legal package clause. Ignored without --lib.
      --offline       Skip the ols release check and tool install that normally finish a scaffold.
                      Without it, new runs the project's own bump-ols and fetch-ols recipes so it
                      starts on the current odinfmt - and format, when the pin actually moved, so
                      the files delivered match the pin they were delivered with. Any of the three
                      failing is a warning, not an error.
      --no-bump       Keep the ols pin the templates carry, but still install it. For a deliberately
                      chosen pin: the release GitHub marks "latest" is not always the newest, so a
                      bump can move a hand-picked pin backwards. --offline also keeps the pin, but
                      skips the install too.
      --linker=<v>    Pin the generated justfile's linker for every platform, where <v> is one of
                      default, lld, radlink or mold. Omit it to keep the skeleton's per-OS default:
                      radlink on Windows (it ships with the Odin toolchain), "default" elsewhere.
                      mold is Linux-only and must be installed separately. Whatever is chosen,
                      ODIN_LINKER=<v> overrides it for a single command.
  add <feature> [dir] Add an optional feature to an existing project (default: the current
                      directory). Features are left out of "new" so that a project that does not
                      want one carries none of its bulk - one optional import line in the justfile
                      is the whole footprint. Removing one is deleting the feature's directory.
      bench           Benchmark harness: warmup, iteration ramp with a robust line fit, outlier
                      counts, JSON reports and a Mann-Whitney comparison against a baseline, plus
                      instruction counts under callgrind for a gate that does not drift.
                      Adds bench/ and the just recipes bench, bench_build, bench_cmp,
                      bench_count, bench_count_check, bench_lint, bench_save and rerun_bench.
  sync [dir]          Overwrite a project's mechanical files with this binary's copies (default: the
                      current directory). Only files nobody is expected to have edited: .editorconfig,
                      .gitattributes, .gitignore, .just/editor.just, .just/toolchain.just and
                      odinfmt.json. The justfile, README.md, LICENSE, your source and the .sublime
                      files are never touched - they carry either your work or this project's own name.
                      A file the project does not have yet is created, so a project scaffolded before a
                      template existed picks it up.
      --check         Write nothing; exit 1 if anything has drifted. For CI.
      --dry-run       Write nothing; list what would change and exit 0.
      --only=<paths>  Sync only these comma-separated paths, instead of the whole set.
      --pin=<which>   keep (default) carries the project's own ols_tag and ols_sha256 across, so a
                      sync never undoes "just bump-ols" or moves a hand-picked pin backwards.
                      template takes this binary's pin instead.
      --force         Skip the two overridable refusals: that the directory holds no .odin files, and
                      that git reports a file to be overwritten as modified, untracked or ignored.
                      The second is the only way back from a sync you did not want. This repository
                      itself is refused either way.
  doctor              Check for odin, just, odinfmt, git and uv; report what is missing, what is
                      too old, and where to get it.
  version             Print this binary's version.
  help                Print this message.

Examples:
  odin-skel new ../my-game            scaffold into ../my-game, project name "my-game"
  odin-skel new ../dir my-game        scaffold into ../dir, but name the project "my-game"
  odin-skel new . my-game             scaffold into the current directory (must be empty; a name
                                      is needed here because "." is not one)
  odin-skel new ../srv --linker=mold  scaffold with mold pinned as the project's linker
  odin-skel new ../odin-toml --lib    scaffold a library; package name defaults to "odin_toml"
  odin-skel new ../odin-toml --lib --pkg=toml   ... or name the package yourself
  odin-skel add bench                 add the benchmark harness to the project in this directory
  odin-skel add bench ../my-game      ... or to one somewhere else
  odin-skel sync                      refresh this project's mechanical files from this binary
  odin-skel sync --check              exit 1 if any of them has drifted (CI)
  odin-skel sync ../my-game --dry-run show what a sync would change, and change nothing
  odin-skel doctor                    check the toolchain before starting

After scaffolding, the project is driven by just (https://just.systems):
  just run          build and run a debug build (executables only; a library has just check)
  just test         run the tests
  just lint         type check, vet and style check
  just --list       every available recipe

Homepage: ` +
	HOMEPAGE +
	`
`

main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	args := os.args[1:]
	if len(args) == 0 {
		fmt.print(USAGE)
		return 2
	}

	switch args[0] {
	case "version":
		fmt.printfln("odin-skel %s", VERSION)
		return 0
	case "--version", "-V":
		// Not in OWNED_COMMANDS: flags are never forwarded to `just`, only bare subcommands are.
		fmt.printfln("odin-skel %s", VERSION)
		return 0
	case "add":
		// No flags, so no parser: `add <feature> [dir]`, and the directory defaults to the one the
		// user is standing in, which is where somebody adding a feature to their own project already is.
		if len(args) < 2 {
			fmt.eprintln("odin-skel: `add` needs a feature name")
			fmt.eprintln("usage: odin-skel add <feature> [dir]")
			fmt.eprintln("features:")
			for f in FEATURES {
				fmt.eprintfln("  %-8s %s", f.name, f.description)
			}
			return 2
		}
		if len(args) > 3 {
			fmt.eprintfln("odin-skel: `add` takes at most a feature and a directory, got %d arguments", len(args) - 1)
			return 2
		}
		dest := len(args) >= 3 ? args[2] : "."
		return add(dest, args[1])
	case "sync":
		// Flags may appear anywhere after `sync`, like `new`; the single leftover positional is the
		// directory, and it defaults to the one the user is standing in - somebody syncing their own
		// project is already in it.
		dest := ""
		only: [dynamic]string
		defer delete(only)
		pin := Sync_Pin.Keep
		check, dry_run, force := false, false, false
		for i := 1; i < len(args); i += 1 {
			arg := args[i]

			switch arg {
			case "--check":
				check = true
				continue
			case "--dry-run":
				dry_run = true
				continue
			case "--force":
				force = true
				continue
			}

			name, value: string
			switch {
			case strings.has_prefix(arg, "--only="):
				name, value = "--only", arg[len("--only="):]
			case strings.has_prefix(arg, "--pin="):
				name, value = "--pin", arg[len("--pin="):]
			case arg == "--only", arg == "--pin":
				if i + 1 >= len(args) {
					fmt.eprintfln(
						"odin-skel: %s needs a value, e.g. %s=%s",
						arg,
						arg,
						arg == "--pin" ? "keep" : ".gitignore",
					)
					return 2
				}
				i += 1
				name, value = arg, args[i]
			case:
				if dest != "" {
					fmt.eprintfln("odin-skel: `sync` takes one directory, got %q as well as %q", arg, dest)
					fmt.eprintln("  to name individual files, use --only=<paths>")
					return 2
				}
				dest = arg
				continue
			}

			switch name {
			case "--only":
				if value == "" {
					fmt.eprintln("odin-skel: --only needs at least one path, e.g. --only=.gitignore")
					return 2
				}
				// Split rather than repeated: one flag holding a list reads the way the paths are
				// written down, and there is no shell quoting to get wrong.
				for path in strings.split(value, ",", context.temp_allocator) {
					trimmed := strings.trim_space(path)
					if trimmed != "" {
						append(&only, trimmed)
					}
				}
			case "--pin":
				switch value {
				case "keep":
					pin = .Keep
				case "template":
					pin = .Template
				case:
					fmt.eprintfln("odin-skel: unknown --pin value %q", value)
					fmt.eprintln("choices: keep, template")
					return 2
				}
			}
		}
		// Both mean "write nothing", but they disagree about what that is worth: --check is a gate and
		// fails on drift, --dry-run is a preview and succeeds. Silently picking one would make a CI
		// job that passed both green whatever it found.
		if check && dry_run {
			fmt.eprintln(
				"odin-skel: --check and --dry-run contradict each other - --check fails on drift, --dry-run does not",
			)
			return 2
		}
		return sync(dest if dest != "" else ".", only[:], pin, check, dry_run, force)
	case "doctor":
		return doctor()
	case "help", "-h", "--help":
		fmt.print(USAGE)
		return 0
	case "new":
		// Flags may appear anywhere after `new`; what is left over is positional. Both the
		// `--flag=value` and `--flag value` spellings are accepted because both are what people type.
		positional: [dynamic]string
		defer delete(positional)
		linker := ""
		pkg := ""
		// Tracked separately from `pkg != ""`, so that `--pkg=` with an empty value is an error rather
		// than a silent fall back to the derived name - somebody who typed the flag meant to choose.
		pkg_given := false
		kind := Project_Kind.Exe
		offline := false
		bump := true
		for i := 1; i < len(args); i += 1 {
			arg := args[i]

			if arg == "--lib" {
				kind = .Lib
				continue
			}
			if arg == "--offline" {
				offline = true
				continue
			}
			if arg == "--no-bump" {
				bump = false
				continue
			}

			// Which flag is being read, so the shared `--flag value` handling below only has to know
			// that a value is wanted, not which one.
			name, value: string
			switch {
			case strings.has_prefix(arg, "--linker="):
				name, value = "--linker", arg[len("--linker="):]
			case strings.has_prefix(arg, "--pkg="):
				name, value = "--pkg", arg[len("--pkg="):]
			case arg == "--linker", arg == "--pkg":
				if i + 1 >= len(args) {
					fmt.eprintfln(
						"odin-skel: %s needs a value, e.g. %s=%s",
						arg,
						arg,
						arg == "--pkg" ? "my_lib" : "mold",
					)
					return 2
				}
				i += 1
				name, value = arg, args[i]
			case:
				append(&positional, arg)
				continue
			}

			switch name {
			case "--linker":
				if !valid_linker(value) {
					fmt.eprintfln("odin-skel: unknown linker %q", value)
					fmt.eprintfln("choices: %s", strings.join(LINKERS, ", ", context.temp_allocator))
					return 2
				}
				linker = value
			case "--pkg":
				if value == "" {
					fmt.eprintln("odin-skel: --pkg needs a package name, e.g. --pkg=my_lib")
					return 2
				}
				pkg, pkg_given = value, true
			}
		}

		if len(positional) == 0 {
			fmt.eprintln("odin-skel: `new` needs a destination directory")
			fmt.eprintln(
				"usage: odin-skel new <dest> [name] [--lib] [--pkg=<name>] [--linker=<default|lld|radlink|mold>] [--offline] [--no-bump]",
			)
			return 2
		}
		// Accepted rather than rejected when `--lib` is absent: it is only ever a hint about a
		// library, and a stray one should not fail a scaffold that otherwise succeeds. Say so, since
		// silently ignoring a flag somebody typed is how a wrong package name goes unnoticed.
		if pkg_given && kind != .Lib {
			fmt.eprintln("odin-skel: --pkg only applies to --lib; ignoring it")
		}
		name := len(positional) >= 2 ? positional[1] : ""
		return new(positional[0], name, linker, kind, pkg, offline, bump)
	case:
		fmt.eprintfln("odin-skel: unknown command %q", args[0])
		fmt.eprint(USAGE)
		return 2
	}
}
