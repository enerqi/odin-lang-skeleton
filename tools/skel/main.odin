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
OWNED_COMMANDS :: []string{"new", "version", "doctor", "help"}

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
      --linker=<v>    Pin the generated justfile's linker for every platform, where <v> is one of
                      default, lld, radlink or mold. Omit it to keep the skeleton's per-OS default:
                      radlink on Windows (it ships with the Odin toolchain), "default" elsewhere.
                      mold is Linux-only and must be installed separately. Whatever is chosen,
                      ODIN_LINKER=<v> overrides it for a single command.
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
		kind := Project_Kind.Exe
		for i := 1; i < len(args); i += 1 {
			arg := args[i]

			if arg == "--lib" {
				kind = .Lib
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
				pkg = value
			}
		}

		if len(positional) == 0 {
			fmt.eprintln("odin-skel: `new` needs a destination directory")
			fmt.eprintln(
				"usage: odin-skel new <dest> [name] [--lib] [--pkg=<name>] [--linker=<default|lld|radlink|mold>]",
			)
			return 2
		}
		// Accepted rather than rejected when `--lib` is absent: it is only ever a hint about a
		// library, and a stray one should not fail a scaffold that otherwise succeeds. Say so, since
		// silently ignoring a flag somebody typed is how a wrong package name goes unnoticed.
		if pkg != "" && kind != .Lib {
			fmt.eprintln("odin-skel: --pkg only applies to --lib; ignoring it")
		}
		name := len(positional) >= 2 ? positional[1] : ""
		return new(positional[0], name, linker, kind, pkg)
	case:
		fmt.eprintfln("odin-skel: unknown command %q", args[0])
		fmt.eprint(USAGE)
		return 2
	}
}
