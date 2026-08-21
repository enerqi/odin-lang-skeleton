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

`offline` skips the ols pin check, install and format at the end - see `pin_and_install_ols`. Everything
up to that point is local, so an offline scaffold is a complete one. `bump` = false keeps the pin the
templates carry but still installs it, for a pin chosen deliberately.

Not everything is copied verbatim:

  - the justfile, its `.just/` recipe fragments, README.md and .gitattributes have their marker
    blocks stripped, per kind
  - README.md is additionally demoted one heading level and given a `# <name>` title of its own
  - `*.sublime-project` is renamed to `<name>.sublime-project`
  - LICENSE is replaced with a fresh Zlib licence
  - for `.Lib`, the template's `mylib/` files move to the destination root and their package clause
    is rewritten

Returns a process exit code.
*/
new :: proc(
	dest: string,
	name: string,
	linker: string = "",
	kind := Project_Kind.Exe,
	pkg: string = "",
	offline := false,
	bump := true,
) -> int {
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
		// Optional features are never part of a scaffold, whatever the kind - `odin-skel add <name>`
		// writes them into a project that already exists. The justfile's `import?` line ships either
		// way and is inert until the directory is there.
		if tmpl.feature != "" {
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
		//
		// `.just/` holds the justfile's imported recipe fragments, which are part of the same file for
		// this purpose - .just/editor.just carries a `snippet-exclude` block whose marker lines have to
		// go the same way the justfile's do. A prefix test rather than another name in the list, so a
		// fragment added later is covered without editing this line. Note bench/bench.just is NOT here:
		// feature files arrive via `add`, which copies them verbatim, so they carry no markers.
		case tmpl.path ==
		     "justfile",
		     tmpl.path ==
		     "README.md",
		     tmpl.path ==
		     ".gitattributes",
		     strings.has_prefix(tmpl.path, FRAGMENT_DIR):
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

	if !offline {
		pin_and_install_ols(dest, bump)
	}
	return 0
}

/*
Bring the new project's ols pin up to date, install it, and - only if the pin actually moved - format
with it. Warns and continues on any failure. `bump` = false keeps the shipped pin and does the install
alone.

The pin the templates carry is as old as the last odin-skel release, so without the bump a new project
starts several ols releases behind and takes a reformatting diff across files nobody edited the first
time anybody bumps it. odinfmt ships inside an ols release and cannot report its own version, which is
why the pin exists at all - see `ols_tag` in .just/toolchain.just.

The format is what makes the bump honest. The files were just written from templates formatted by
whichever odinfmt the *skeleton* pinned, and the bump may have pointed the project at a newer one - so
without it the first `just format` reformats files the user never wrote. That is the same diff the bump
exists to prevent, moved to a worse moment: here the project has no history, so the churn is invisible;
later it is noise in a real review. Only when the pin moved, because otherwise the templates already
match the pin and running odinfmt would be a no-op with a download attached.

Whether it moved is decided by reading the pin back, not by parsing `bump-ols` output: the file is the
only authority on what changed, and the recipe prints several different shapes of message.

No step is reimplemented here. `just bump-ols`, `just fetch-ols` and `just format` are recipes in the
justfile that was just written, so the tool and the scaffolded project cannot disagree about how a pin
is chosen, verified or applied - the same reason `just new` is a thin wrapper around this binary rather
than a second copy of the logic (tools/DESIGN.md, Decision 2). The cost is that they need `just` and
`uv`, so a missing one is reported as that rather than as a failure.

Every failure here is a warning, never an exit code: the files are already written and correct, and what
is at stake is only whether the pin is current and the tools are on disk. A scaffold that reported
failure because GitHub was unreachable would be lying about what happened.
*/
pin_and_install_ols :: proc(dest: string, bump := true) {
	shipped, shipped_ok := toolchain_ols_tag(dest)
	defer if shipped_ok {
		delete(shipped)
	}

	pin_moved := false
	fmt.println()
	if !bump {
		if shipped_ok {
			fmt.printfln("keeping the pin the templates carry, ols_tag = %q (--no-bump)", shipped)
		} else {
			fmt.println("keeping the pin the templates carry (--no-bump)")
		}
	} else {
		fmt.println("checking for the latest ols release (`--offline` skips this and the install below)")
		bumped := probe({"just", "bump-ols"}, dest)
		defer delete(bumped.output)
		if bumped.output != "" {
			fmt.println(bumped.output)
		}
		if !bumped.found {
			fmt.eprintln("odin-skel: warning: `just` is not on PATH, so the ols pin was not checked")
		} else if bumped.exit_code != 0 {
			fmt.eprintfln("odin-skel: warning: could not check for the latest ols release (exit %d)", bumped.exit_code)
		}
		if !bumped.found || bumped.exit_code != 0 {
			if shipped_ok {
				fmt.eprintfln("  the project keeps the pin it shipped with, ols_tag = %q", shipped)
			}
			fmt.eprintln("  run `just bump-ols` in the project to adopt the latest release")
		} else if shipped_ok {
			if current, current_ok := toolchain_ols_tag(dest); current_ok {
				pin_moved = current != shipped
				delete(current)
			}
		}
	}

	fmt.println("installing the pinned ols + odinfmt")
	fetch := probe({"just", "fetch-ols"}, dest)
	defer delete(fetch.output)
	if fetch.output != "" {
		fmt.println(fetch.output)
	}
	if !fetch.found {
		fmt.eprintln("odin-skel: warning: `just` is not on PATH, so the pinned tools were not installed")
	} else if fetch.exit_code != 0 {
		fmt.eprintfln("odin-skel: warning: could not install the pinned ols + odinfmt (exit %d)", fetch.exit_code)
	}
	if !fetch.found || fetch.exit_code != 0 {
		// `format` depends on `ensure-odinfmt`, so the download is retried at the point it is needed.
		fmt.eprintln("  the first `just format` installs them anyway, or run `just fetch-ols` when ready")
	}

	if !pin_moved {
		return
	}
	if !fetch.found || fetch.exit_code != 0 {
		// Formatting with an odinfmt that is not there would only repeat the failure above.
		fmt.eprintln("odin-skel: warning: the pin moved but the tools are missing, so the files were not reformatted")
		fmt.eprintln("  run `just format` once `just fetch-ols` has succeeded, and commit that as the scaffold")
		return
	}

	fmt.println("reformatting with the newly pinned odinfmt")
	formatted := probe({"just", "format"}, dest)
	defer delete(formatted.output)
	if formatted.output != "" {
		fmt.println(formatted.output)
	}
	if !formatted.found {
		fmt.eprintln("odin-skel: warning: `just` is not on PATH, so the files were not reformatted")
	} else if formatted.exit_code != 0 {
		fmt.eprintfln("odin-skel: warning: could not reformat with the new pin (exit %d)", formatted.exit_code)
	}
	if !formatted.found || formatted.exit_code != 0 {
		fmt.eprintln(
			"  run `just format` before committing, or the first one you run will churn files you did not write",
		)
	}
}

// The `ols_tag` the written .just/toolchain.just carries, for a warning that can name it. Anchored to
// the start of a line so the tag mentioned in the file's own comments cannot be read instead. Unreadable
// or absent is not worth a message of its own - the caller just leaves the tag out of its warning.
@(require_results)
toolchain_ols_tag :: proc(dest: string, allocator := context.allocator) -> (tag: string, ok: bool) {
	full := join_path(dest, TOOLCHAIN_FRAGMENT)
	defer delete(full)

	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil {
		return "", false
	}

	PREFIX :: "ols_tag := \""
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		if !strings.has_prefix(line, PREFIX) {
			continue
		}
		rest := line[len(PREFIX):]
		if end := strings.index_byte(rest, '"'); end >= 0 {
			return strings.clone(rest[:end], allocator), true
		}
	}
	return "", false
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
