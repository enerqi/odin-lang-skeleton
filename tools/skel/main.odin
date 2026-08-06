package skel

import "core:fmt"
import "core:os"

// Bumped by the release process. `dev` marks a binary built straight from a working tree, which is
// also what `version` reports when nobody has stamped a release in.
VERSION :: #config(SKEL_VERSION, "dev")

// Subcommands the binary implements itself. The passthrough MUST refuse to forward any of these to
// `just`, otherwise `just new` -> `odin-skel new` -> `just new` ping-pongs forever once a name is
// added here but the dispatch below forgets it (see tools/DESIGN.md, Open items / Loop guard).
OWNED_COMMANDS :: []string{"version", "doctor", "help"}

USAGE :: `odin-skel - project scaffolding for the Odin skeleton

Usage:
  odin-skel <command> [args...]

Commands:
  doctor     check the toolchain (odin, just, odinfmt, git) and report what is missing
  version    print the binary version
  help       print this message

Not implemented yet:
  new        scaffold a project (phase 2 - see tools/DESIGN.md)
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
		fmt.eprintln("odin-skel: `new` is not implemented yet - use `just new` inside a skeleton clone")
		return 1
	case:
		fmt.eprintfln("odin-skel: unknown command %q", args[0])
		fmt.eprint(USAGE)
		return 2
	}
}
