package skel

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

/*
Scaffold a new project from the embedded templates.

`dest` may already exist as long as it is empty apart from `.git` - the common case is a directory
somebody just ran `git init` in. `name` defaults to the destination directory's base name and is
used for the `.sublime-project` file.

`linker` is one of LINKERS, or "" to keep the skeleton's per-OS default (radlink on Windows,
`default` elsewhere). When set, the generated justfile pins that linker for every platform.

Not everything is copied verbatim:

  - the justfile, README.md and .gitattributes have their `>>> skeleton-only` blocks stripped
  - README.md is additionally demoted one heading level and given a `# <name>` title of its own
  - `*.sublime-project` is renamed to `<name>.sublime-project`
  - LICENSE is replaced with a fresh Zlib licence

Returns a process exit code.
*/
new :: proc(dest: string, name: string, linker: string = "") -> int {
	if os.is_file(dest) {
		fmt.eprintfln("odin-skel: refusing - %q is a file", dest)
		return 1
	}
	if !dir_is_empty_enough(dest) {
		fmt.eprintfln("odin-skel: refusing - %q exists and is not empty (ignoring .git)", dest)
		return 1
	}

	project := name if name != "" else path_base(dest)
	if project == "" || project == "." || project == ".." {
		fmt.eprintfln("odin-skel: could not derive a project name from %q - pass one explicitly", dest)
		return 1
	}

	year, _, _ := time.date(time.now())

	sublime_name := strings.concatenate({project, ".sublime-project"})
	defer delete(sublime_name)

	written := 0
	for tmpl in TEMPLATES {
		out_rel, content: string
		owned_rel, owned_content: bool

		switch {
		// All three carry `skeleton-only` marker blocks: the justfile's recipes that only maintain
		// this repo, the README sections documenting those recipes plus how to install and release
		// odin-skel itself, and .gitattributes' linguist rules for files that either do not exist in
		// a scaffolded project or are not generated once they land there.
		case tmpl.path == "justfile", tmpl.path == "README.md", tmpl.path == ".gitattributes":
			out_rel, content = tmpl.path, strip_skeleton_only(tmpl.data)
			owned_content = true

			// `--linker` only touches the justfile, and only after the strip: the assignment it
			// rewrites lives outside every marker block, so doing it in this order means the
			// anchor search runs over exactly the text being written out.
			if linker != "" && tmpl.path == "justfile" {
				pinned, pinned_ok := set_linker_default(content, linker)
				if !pinned_ok {
					delete(content)
					fmt.eprintln(
						"odin-skel: could not find the justfile's `linker :=` line - this binary and its template have drifted",
					)
					return 1
				}
				delete(content)
				content = pinned
			}

			// The README is guidance about the tooling, not this project's front page, so it drops
			// a level and the project takes the H1. See `project_readme`.
			if tmpl.path == "README.md" {
				titled := project_readme(content, project)
				delete(content)
				content = titled
			}
		case tmpl.path == "LICENSE":
			out_rel, content = tmpl.path, zlib_license(year)
			owned_content = true
		case strings.has_suffix(tmpl.path, ".sublime-project"):
			out_rel, content = replace_base(tmpl.path, sublime_name), tmpl.data
			owned_rel = true
		case:
			out_rel, content = tmpl.path, tmpl.data
		}
		defer if owned_rel {
			delete(out_rel)
		}
		defer if owned_content {
			delete(content)
		}

		full := join_path(dest, out_rel)
		defer delete(full)

		if dir := path_dir(full); dir != "" {
			if err := ensure_directory(dir); err != nil {
				fmt.eprintfln("odin-skel: could not create %q: %v", dir, err)
				return 1
			}
		}

		if err := os.write_entire_file(full, transmute([]byte)content); err != nil {
			fmt.eprintfln("odin-skel: could not write %q: %v", full, err)
			return 1
		}
		written += 1
	}

	fmt.printfln("created %d files in %s (project %q, Zlib license)", written, dest, project)
	return 0
}

/*
Create `dir` and any missing parents, treating "it is already there" as success.

`os.make_directory_all` does not mean the same thing on every platform, and the difference is not
cosmetic:

  Linux/macOS  returns `.Exist` when nothing was created, i.e. the directory was already there
               (`return nil if has_created else .Exist`)
  Windows      returns nil when the path is already a directory, and `.Exist` only when the path
               exists but is *not* a directory - a genuine error

Every template file after the first in a given directory hits that path, so the naive version
scaffolded fine on Windows and failed on the second file everywhere else.

So `.Exist` is tolerated only when the path really is a directory afterwards. That makes the POSIX
"already there" case succeed without also swallowing the Windows "there is a file in the way" case.
The leading `is_directory` check is kept so the common path never provokes an error at all.
*/
ensure_directory :: proc(dir: string) -> os.Error {
	if os.is_directory(dir) {
		return nil
	}
	err := os.make_directory_all(dir)
	if general, ok := err.(os.General_Error); ok && general == .Exist && os.is_directory(dir) {
		return nil
	}
	return err
}

// A destination is usable when it does not exist, or exists with nothing in it but `.git`.
dir_is_empty_enough :: proc(dest: string) -> bool {
	if !os.exists(dest) {
		return true
	}

	entries, err := os.read_directory_by_path(dest, -1, context.temp_allocator)
	if err != nil {
		// Unreadable: let the later write fail with a more specific message than a guess here.
		return true
	}
	for entry in entries {
		if path_base(entry.fullpath) != ".git" {
			return false
		}
	}
	return true
}

// Paths handled here come from two places: `git ls-files` output, which always uses forward slashes,
// and a user-supplied destination, which on Windows may use either. So both separators are treated
// as one rather than reaching for core:path/filepath, whose helpers return allocator errors and
// whose SEPARATOR is platform-specific.
is_separator :: proc(c: byte) -> bool {
	return c == '/' || c == '\\'
}

last_separator :: proc(path: string) -> int {
	for i := len(path) - 1; i >= 0; i -= 1 {
		if is_separator(path[i]) {
			return i
		}
	}
	return -1
}

// Final component, ignoring any trailing separators ("a/b/" -> "b").
path_base :: proc(path: string) -> string {
	end := len(path)
	for end > 0 && is_separator(path[end - 1]) {
		end -= 1
	}
	trimmed := path[:end]
	if i := last_separator(trimmed); i >= 0 {
		return trimmed[i + 1:]
	}
	return trimmed
}

// Everything before the final component; empty when there is no directory part.
path_dir :: proc(path: string) -> string {
	if i := last_separator(path); i > 0 {
		return path[:i]
	}
	return ""
}

join_path :: proc(dir: string, rel: string, allocator := context.allocator) -> string {
	trimmed := dir
	for len(trimmed) > 0 && is_separator(trimmed[len(trimmed) - 1]) {
		trimmed = trimmed[:len(trimmed) - 1]
	}
	return strings.concatenate({trimmed, "/", rel}, allocator)
}

// Swap the final path component, keeping any directory prefix.
replace_base :: proc(path: string, new_base: string, allocator := context.allocator) -> string {
	if i := last_separator(path); i >= 0 {
		return strings.concatenate({path[:i + 1], new_base}, allocator)
	}
	return strings.clone(new_base, allocator)
}
