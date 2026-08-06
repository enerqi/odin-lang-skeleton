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

USAGE :: `odin-skel - project scaffolding for the Odin skeleton

Usage:
  odin-skel <command> [args...]

Commands:
  new <dest> [name]  scaffold a project into dest (must be empty apart from .git)
  doctor             check the toolchain (odin, just, odinfmt, git) and report what is missing
  version            print the binary version
  help               print this message
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
