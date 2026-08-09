/*
SKELETON: this is the library's root package. Rename the directory, this file and the package clause
below together - `odin-skel new --lib` does all three, deriving the package name from the project
name.

The directory IS the package: a consumer clones or copies this directory into their own tree and
imports it by path, so the name they give the directory becomes the import path, and the name declared
below is what binds in their file.

	import toml "libs/toml"

Keep the two the same unless there is a reason not to. A package name must be a valid Odin identifier,
which a repository name often is not: `odin-toml` is a fine directory name and an illegal package
clause, so `--lib` turns it into `odin_toml` unless `--pkg` says otherwise.
*/
package mylib

// Delete this and its test once there is something real here. It exists so that `just test` and
// `just example basic` have something to run in a freshly scaffolded project.
add :: proc(a, b: int) -> int {
	return a + b
}
