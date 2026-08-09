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

`kind` selects the project shape. `.Exe` is the default; `.Lib` scaffolds a source package whose root
directory is the package itself. `pkg` names that package and is only consulted for `.Lib`; when
empty it is derived from the project name, which frequently is not a legal package clause on its own.

Not everything is copied verbatim:

  - the justfile, README.md and .gitattributes have their marker blocks stripped, per kind
  - README.md is additionally demoted one heading level and given a `# <name>` title of its own
  - `*.sublime-project` is renamed to `<name>.sublime-project`
  - LICENSE is replaced with a fresh Zlib licence
  - for `.Lib`, the template's `mylib/` files move to the destination root and their package clause
    is rewritten

Returns a process exit code.
*/
new :: proc(dest: string, name: string, linker: string = "", kind := Project_Kind.Exe, pkg: string = "") -> int {
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

	// Resolved for every kind so that an illegal name is reported before any file is written, but only
	// used by `.Lib` - an executable's directory name never has to be an identifier.
	package_name := ""
	if kind == .Lib {
		source := pkg if pkg != "" else project
		reason: string
		name_ok: bool
		package_name, reason, name_ok = odin_package_name(source)
		if !name_ok {
			fmt.eprintfln("odin-skel: %q cannot be an Odin package name - %s", source, reason)
			fmt.eprintln("pass one explicitly, e.g. --pkg=my_lib")
			return 1
		}
	}
	// Registered at function scope, not inside the branch above: a `defer` fires at the end of the
	// block it appears in, so freeing it there would leave `package_name` dangling for the whole loop.
	defer if package_name != "" {
		delete(package_name)
	}

	year, _, _ := time.date(time.now())

	sublime_name := strings.concatenate({project, ".sublime-project"})
	defer delete(sublime_name)

	written := 0
	for tmpl in TEMPLATES {
		if !template_wanted(tmpl.kind, kind) {
			continue
		}

		out_rel, content: string
		owned_rel, owned_content: bool

		switch {
		// All three carry `skeleton-only` marker blocks: the justfile's recipes that only maintain
		// this repo, the README sections documenting those recipes plus how to install and release
		// odin-skel itself, and .gitattributes' linguist rules for files that either do not exist in
		// a scaffolded project or are not generated once they land there. The justfile and README
		// additionally carry `exe-only` / `lib-only` blocks, which is why the drop set is per kind.
		case tmpl.path == "justfile", tmpl.path == "README.md", tmpl.path == ".gitattributes":
			out_rel, content = tmpl.path, strip_marked_blocks(tmpl.data, drop_names(kind))
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

		// The lib template lives under `mylib/` here only because this repository's root is already
		// `package main`. A scaffolded library's root IS the package, so the prefix comes off and the
		// package clause is rewritten - see tools/DESIGN.md, Decision 4a.
		case tmpl.kind == .Lib:
			rel, rel_ok := lib_out_path(tmpl.path, package_name)
			if !rel_ok {
				fmt.eprintfln(
					"odin-skel: %q is marked as a lib template but is not under %q - this binary and its template have drifted",
					tmpl.path,
					LIB_TEMPLATE_DIR,
				)
				return 1
			}
			out_rel, owned_rel = rel, true
			content = tmpl.data

			// Only the files at the template's root declare the library package; everything below it
			// is an example, which is `package main` and must keep that clause.
			if path_dir(tmpl.path) == LIB_TEMPLATE_DIR && strings.has_suffix(tmpl.path, ".odin") {
				renamed, clause_ok := rewrite_package_clause(content, package_name)
				if !clause_ok {
					delete(out_rel)
					fmt.eprintfln(
						"odin-skel: %q has no `package %s` line - this binary and its template have drifted",
						tmpl.path,
						LIB_TEMPLATE_PACKAGE,
					)
					return 1
				}
				content, owned_content = renamed, true
			}
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

	if kind == .Lib {
		fmt.printfln(
			"created %d files in %s (library %q, package %q, Zlib license)",
			written,
			dest,
			project,
			package_name,
		)
	} else {
		fmt.printfln("created %d files in %s (project %q, Zlib license)", written, dest, project)
	}
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
