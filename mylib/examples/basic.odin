/*
Examples are single-file `main` packages built with `-file`, which makes each file self-contained.
That is what lets several of them share this one directory without their `main` procedures colliding:

	just example basic
*/
package main

import lib ".."
import "core:fmt"

main :: proc() {
	fmt.println("1 + 2 =", lib.add(1, 2))
}
