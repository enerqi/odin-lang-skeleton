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
OWNED_COMMANDS :: []string{"new", "add", "version", "doctor", "help"}

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
      --lib           Scaffold a library - an Odin source package that other projects copy into
                      their tree and import - instead of an executable. The destination directory
                      IS the package, and examples live in examples/ as single-file programs.
      --pkg=<name>    The library's package name. Defaults to the project name with -, . and
                      spaces turned into underscores, since a directory name like "odin-mylib" is
                      not a legal package clause. Ignored without --lib.
      --offline       Skip the ols release check and tool install that normally finish a scaffold.
                      Without it, new runs the project's own bump-ols and fetch-ols recipes so it
                      starts on the current odinfmt; either failing is a warning, not an error.
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
				"usage: odin-skel new <dest> [name] [--lib] [--pkg=<name>] [--linker=<default|lld|radlink|mold>] [--offline]",
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
		return new(positional[0], name, linker, kind, pkg, offline)
	case:
		fmt.eprintfln("odin-skel: unknown command %q", args[0])
		fmt.eprint(USAGE)
		return 2
	}
}
