package skel

import "core:fmt"
import "core:os"
import "core:strings"

/*
Write an optional feature's files into a project that already exists.

The counterpart to `new`, and deliberately much smaller. A feature is a directory of files that are
copied verbatim to the same relative path they occupy in the skeleton - no marker stripping, no package
clause rewriting, no relocation - because the whole design of the feature mechanism is that adding one
touches nothing the project already has. Its recipes arrive in a `.just` file that the project
justfile's `import?` line was already waiting for. See the `Feature` doc comment in template.odin.

Two guards, both about not surprising somebody:

  - the destination must look like a project this tool scaffolded, i.e. have a justfile. Writing
    `bench/` into an arbitrary directory would produce a harness with no way to run it.
  - the feature's directory must not already exist. There is no merge here and no way to tell an
    untouched copy from one somebody spent a week writing benchmarks in, so an existing directory is
    refused rather than overwritten.

Returns a process exit code.
*/
add :: proc(dest: string, feature_name: string) -> int {
	feature, known := find_feature(feature_name)
	if !known {
		fmt.eprintfln("odin-skel: unknown feature %q", feature_name)
		fmt.eprintln("features:")
		for f in FEATURES {
			fmt.eprintfln("  %-8s %s", f.name, f.description)
		}
		return 2
	}

	if !os.is_directory(dest) {
		fmt.eprintfln("odin-skel: %q is not a directory", dest)
		return 1
	}

	// The justfile is what makes a directory a project of this shape, and it is what carries the
	// `import?` line the feature's recipes arrive through. Without it the files would land and do
	// nothing, which is a worse outcome than refusing.
	justfile := join_path(dest, "justfile")
	defer delete(justfile)
	if !os.is_file(justfile) {
		fmt.eprintfln("odin-skel: %q has no justfile - is it a project scaffolded by odin-skel?", dest)
		return 1
	}

	target := join_path(dest, feature.dir)
	defer delete(target)
	if os.exists(target) {
		fmt.eprintfln("odin-skel: %q already exists - remove it first, or you would lose whatever is in it", target)
		return 1
	}

	// A failure part way through would otherwise leave a half-written directory that the `os.exists`
	// guard above then refuses to replace, so the only way to retry would be deleting it by hand.
	// Nothing here existed before this call - the guard proved that - so removing it on the error path
	// destroys nothing.
	failed := false
	defer if failed {
		if err := os.remove_all(target); err != nil {
			fmt.eprintfln("odin-skel: could not clean up %q after the failure: %v", target, err)
			fmt.eprintfln("remove it by hand before retrying")
		}
	}

	written := 0
	for tmpl in TEMPLATES {
		if tmpl.feature != feature.name {
			continue
		}

		full := join_path(dest, tmpl.path)
		defer delete(full)

		if dir := path_dir(full); dir != "" {
			if err := ensure_directory(dir); err != nil {
				fmt.eprintfln("odin-skel: could not create %q: %v", dir, err)
				failed = true
				return 1
			}
		}
		if err := os.write_entire_file(full, transmute([]byte)tmpl.data); err != nil {
			fmt.eprintfln("odin-skel: could not write %q: %v", full, err)
			failed = true
			return 1
		}
		written += 1
	}

	// Reachable only if every file of this feature lost its tag, which would mean the binary and its
	// template have drifted. Reported rather than passed off as success, since nothing was created.
	if written == 0 {
		fmt.eprintfln(
			"odin-skel: no embedded files carry feature %q - this binary and its template have drifted",
			feature.name,
		)
		return 1
	}

	fmt.printfln("added %d files to %s/ (%s)", written, feature.dir, feature.description)

	// The import line is the one thing that has to be present in a project this did not scaffold, or
	// that was scaffolded before the feature existed. Cheap to check, and the failure it prevents -
	// files copied, recipes invisible, no error - is the confusing kind.
	if !justfile_imports(justfile, feature.dir) {
		fmt.eprintln()
		fmt.eprintfln("warning: the justfile does not import the feature's recipes. Add this line to it:")
		fmt.eprintfln("    import? '%s/%s.just'", feature.dir, feature.dir)
	}
	return 0
}

// Whether the justfile already carries the feature's optional import. Matched on the quoted path
// rather than the whole line so that either quote style, or a comment after it, still counts.
@(require_results)
justfile_imports :: proc(justfile: string, dir: string) -> bool {
	data, err := os.read_entire_file(justfile, context.temp_allocator)
	if err != nil {
		// Unreadable is not proof of absence, and a spurious warning about a file we could not read
		// helps nobody. The write already succeeded by this point.
		return true
	}

	needle := strings.concatenate({dir, "/", dir, ".just"}, context.temp_allocator)
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		trimmed := strings.trim_space(line)
		if strings.has_prefix(trimmed, "import") && strings.contains(trimmed, needle) {
			return true
		}
	}
	return false
}
