/*
Examples are single-file `main` packages built with `-file`, which makes each file self-contained.
That is what lets several of them share this one directory without their `main` procedures colliding:

	just example basic

WATCH THE IMPORT DEPTH. In `-file` mode a relative import resolves against the file's own directory,
so this file - one level below the library - imports `".."`. The layout other Odin libraries use,
`examples/<name>/main.odin`, is one level deeper and imports `"../.."`. Getting it wrong reports

	Syntax Error: Empty directory that contains no .odin files: ../..

which names the path but not the reason.

Importing by relative path rather than through a `-collection:` flag is deliberate: it exercises the
same directory a consumer would copy into their own tree, with no build-time flag propping it up.

The import is aliased to `lib` rather than to the package's own name so that renaming the package -
which is the first thing anyone does here - leaves this file alone.
*/
package main

import lib ".."
import "core:fmt"

main :: proc() {
	fmt.println("1 + 2 =", lib.add(1, 2))
}
