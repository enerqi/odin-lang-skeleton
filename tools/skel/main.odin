package skel

import "core:fmt"
import "core:os"

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
USAGE :: `odin-skel - scaffold a new Odin project

Creates a ready-to-build Odin project: a justfile with debug/release build tiers, editor config,
.gitignore/.gitattributes, and Sublime Text build systems. The project template is compiled into
this binary, so scaffolding needs no network access and no git clone.

Usage:
  odin-skel <command> [arguments]

Commands:
  new <dest> [name]   Scaffold a project into <dest>. The directory must not exist, or must be
                      empty apart from .git. [name] defaults to the directory's own name and is
                      used for the .sublime-project file.
  doctor              Check for odin, just, odinfmt and git; report what is missing, what is too
                      old, and where to get it.
  version             Print this binary's version.
  help                Print this message.

Examples:
  odin-skel new ../my-game            scaffold into ../my-game, project name "my-game"
  odin-skel new ../dir my-game        scaffold into ../dir, but name the project "my-game"
  odin-skel new . my-game             scaffold into the current directory (must be empty; a name
                                      is needed here because "." is not one)
  odin-skel doctor                    check the toolchain before starting

After scaffolding, the project is driven by just (https://just.systems):
  just run          build and run a debug build
  just test         run the tests
  just lint         type check, vet and style check
  just --list       every available recipe

Homepage: ` + HOMEPAGE + `
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
		if len(args) < 2 {
			fmt.eprintln("odin-skel: `new` needs a destination directory")
			fmt.eprintln("usage: odin-skel new <dest> [name]")
			return 2
		}
		name := len(args) >= 3 ? args[2] : ""
		return new(args[1], name)
	case:
		fmt.eprintfln("odin-skel: unknown command %q", args[0])
		fmt.eprint(USAGE)
		return 2
	}
}
