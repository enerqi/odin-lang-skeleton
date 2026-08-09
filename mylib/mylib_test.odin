package mylib

import "core:testing"

/*
Tests live in the package rather than in a separate tree, which is what the surrounding Odin
ecosystem does and what lets a test reach `@(private)` symbols.

The cost is that this file is part of the package, so a consumer building it also builds
`import "core:testing"`. Optimization does not remove that: the `@(test)` procedure body is
eliminated, but `core:testing`'s transitive `@(init)`/`@(fini)` procedures are entry points and stay
live. Measured on a `-o:speed` build, it is up to ~8.6 KB against a consumer that imports nothing else
from core, and ~80 bytes against one that already uses `core:log` - almost all of the cost is overlap
with packages a real program links anyway.

If that matters - a freestanding or WASM target, say - move the tests to a `tests/` package that
imports this one, the way Odin's own `core` does it. See the README.
*/
@(test)
test_add :: proc(t: ^testing.T) {
	testing.expect_value(t, add(1, 2), 3)
}
