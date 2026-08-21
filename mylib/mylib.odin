// SKELETON: a comment directly above the package clause is the package's doc comment - `just doc`
// prints it, and it is what a consumer reads first. Replace this with what your package is for.
package mylib

// Delete this and its test once there is something real here. It exists so that `just test` and
// `just example basic` have something to run in a freshly scaffolded project.
add :: proc(a, b: int) -> int {
	return a + b
}
