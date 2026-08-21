package skel

import "core:fmt"
import "core:os"
import "core:strings"

// Where the ols pin lives, and what `sync` carries over from the destination rather than overwriting.
// Both lines are rewritten by `just bump-ols` (see .just/toolchain.just), so the destination's copy is
// newer than this binary's whenever anybody has run it - which is the point.
//
// Anchored at the start of a line, so the tag named in the file's own comments cannot be matched
// instead. Same reason `toolchain_ols_tag` anchors.
@(rodata)
OLS_PIN_PREFIXES := [?]string{"ols_tag := ", "ols_sha256 := "}

// A file that exists only in the skeleton repository, never in a scaffolded project - `_embed` excludes
// all of `tools/`. Its presence means the destination is the template source rather than a project made
// from it, which is the one place a sync would destroy what it is supposed to distribute.
SKEL_SOURCE_MARKER :: "tools/skel/templates.odin"

// What to do with the destination's ols pin. `.Keep` is the default and the reason `sync` is safe to
// run at all: `bump-ols` adopts whatever GitHub marks *latest*, which these date-shaped tags do not
// order, so taking this binary's pin can move a deliberately chosen one backwards - the same hazard
// `new --no-bump` exists for.
Sync_Pin :: enum {
	Keep,
	Template,
}

// What `sync` did, or would do, to one file. `.Created` covers a project scaffolded before the file
// existed, which is a normal outcome rather than an error.
Sync_Action :: enum {
	Unchanged,
	Updated,
	Created,
}

// One planned write. `rel` borrows the template's path; `full` and `content` are owned, and `note` is
// owned when non-empty.
Sync_Item :: struct {
	rel:     string,
	full:    string,
	content: string,
	note:    string,
	action:  Sync_Action,
}

/*
Bring a project's mechanical files back in line with this binary's templates.

The counterpart to `add`, making a different promise from both `new` and `add`: this one *overwrites*.
That is only safe for files nobody is expected to have edited, so the syncable set is a tagged subset
of the templates - `sync = true` in the generated templates.odin, driven by `SYNCABLE_FILES` in the
justfile's `_embed` recipe, so it cannot become a second hand-maintained file list that rots against
the embed list. Three properties have to hold for a file to be in it:

  - no project-specific substitution. The justfile has `--linker`, README.md has the project's H1,
    LICENSE has a year and `.sublime-project` has the project name; none of those can be reconstructed
    from the destination directory alone.
  - the same rendered output for both project kinds, so `sync` never has to work out whether it is
    looking at an executable or a library. Enforced by `test_syncable_templates_are_kind_independent`,
    which is why the strip below can name one kind arbitrarily.
  - configuration rather than code, so a project has no reason to have edited it. The justfile is the
    counter-example: it is a file projects grow into, and replacing it replaces somebody's work.

The .sublime files are deliberately out, even though they would satisfy the first two: they are
starting points a project is expected to edit, and `.sublime-project` is renamed on the way in.

Three things stand between this and losing work:

  - the destination must look like an Odin project: a justfile, and .odin source somewhere under it.
    A justfile alone is weak evidence, since `just` is a general-purpose runner. This repository itself
    is refused outright - see SKEL_SOURCE_MARKER.
  - the ols pin in .just/toolchain.just is carried over from the destination, not overwritten. It is
    live project state, so a blind copy would undo `just bump-ols` and can move a pin backwards.
    `--pin=template` opts out.
  - git is the undo. Any file that would be *changed* is checked with `git status --porcelain`, and a
    dirty or untracked one refuses the sync unless `--force`. A project not under git, or without git
    installed, gets a warning and proceeds - having no history is the author's own choice and applies
    to their whole tree, where an uncommitted edit to exactly the file being replaced is a specific
    thing about to be destroyed.

`force` overrides both of the guards it can override - the Odin-source check and the git one. It has
no effect on the pin, which is `--pin=template`'s job.

`check` writes nothing and returns 1 when anything has drifted, for CI - the same contract
`just embed-check` has. `dry_run` writes nothing and returns 0. `only` restricts the run to named
paths; empty means the whole syncable set.

Contents are compared byte for byte, which is safe because .gitattributes pins `eol=lf` in the working
directory on every platform and is itself part of the syncable set. A project that lost that rule and
checked out CRLF will see every file as drifted once, and converge after the sync that restores it.

Returns a process exit code.
*/
sync :: proc(
	dest: string,
	only: []string,
	pin := Sync_Pin.Keep,
	check := false,
	dry_run := false,
	force := false,
) -> int {
	if !os.is_directory(dest) {
		fmt.eprintfln("odin-skel: %q is not a directory", dest)
		return 1
	}

	// The same guard `add` has, for the same reason: the justfile is what makes a directory a project
	// of this shape. Writing .just/toolchain.just into an arbitrary tree would deliver recipes with no
	// justfile to import them.
	justfile := join_path(dest, "justfile")
	defer delete(justfile)
	if !os.is_file(justfile) {
		fmt.eprintfln("odin-skel: %q has no justfile - is it a project scaffolded by odin-skel?", dest)
		return 1
	}

	// This repository is not a project of its own shape, and it is the one destination where syncing is
	// pure damage: its templates are the *unstripped* originals, so writing the rendered versions back
	// would delete .gitattributes' `skeleton-only` block and the fragments' `snippet-exclude` markers -
	// the very text the scaffolding reads. Every other guard would wave it through, since the files are
	// committed and there is Odin source everywhere. Not overridable by --force, because there is no
	// version of this anybody wants.
	skel_source := join_path(dest, SKEL_SOURCE_MARKER)
	defer delete(skel_source)
	if os.is_file(skel_source) {
		fmt.eprintfln("odin-skel: %q is the skeleton repository itself", dest)
		fmt.eprintfln("  it holds %s, so its copies of these files are the unstripped originals", SKEL_SOURCE_MARKER)
		fmt.eprintln("  syncing would strip the marker blocks that scaffolding reads - edit them here instead")
		return 1
	}

	// A justfile on its own is weak evidence: `just` is a general-purpose runner, and plenty of
	// directories have one. Overwriting somebody's .editorconfig and .gitignore because they happened
	// to be standing in a Rust project with a justfile is the mistake worth one directory walk. Odin
	// source anywhere under the tree is what makes this an Odin project - anywhere, because a library
	// keeps its source at the root, an executable may keep it in a subdirectory, and a workspace of
	// several packages has none at the top at all.
	if !force && !has_odin_source(dest) {
		fmt.eprintfln("odin-skel: %q has a justfile but no .odin files anywhere under it", dest)
		fmt.eprintln("  refusing to overwrite config files in a directory that does not look like an Odin project")
		fmt.eprintln("  `--dry-run` shows what would change; `--force` syncs anyway")
		return 1
	}

	// Validated up front so a typo, or a request for a file that is deliberately not syncable, is
	// reported before anything is written rather than silently matching nothing.
	for want in only {
		if syncable_path(want) {
			continue
		}
		if template_path(want) {
			fmt.eprintfln("odin-skel: %q is not syncable", want)
			fmt.eprintln(
				"  it carries project-specific content, or is a file projects edit - replacing it would replace your work",
			)
		} else {
			fmt.eprintfln("odin-skel: %q is not a template file", want)
		}
		fmt.eprintln("syncable files:")
		for tmpl in TEMPLATES {
			if tmpl.sync {
				fmt.eprintfln("  %s", tmpl.path)
			}
		}
		return 2
	}

	items: [dynamic]Sync_Item
	defer {
		for item in items {
			delete(item.full)
			delete(item.content)
			if item.note != "" {
				delete(item.note)
			}
		}
		delete(items)
	}

	for tmpl in TEMPLATES {
		if !tmpl.sync {
			continue
		}
		if len(only) > 0 && !path_in(only, tmpl.path) {
			continue
		}

		// Naming a kind here is arbitrary and safe: every syncable file strips identically for both,
		// which is one of the three properties that put it in the set.
		content := strip_marked_blocks(tmpl.data, drop_names(.Exe))
		full := join_path(dest, tmpl.path)
		note := ""

		existing, read_err := os.read_entire_file(full, context.temp_allocator)

		if tmpl.path == TOOLCHAIN_FRAGMENT && pin == .Keep && read_err == nil {
			kept, missing, pin_ok := preserve_ols_pin(content, string(existing))
			if !pin_ok {
				delete(content)
				delete(full)
				fmt.eprintfln("odin-skel: could not carry the ols pin over into %q", tmpl.path)
				fmt.eprintfln("  no line starting %q in one of the two files - they have drifted apart", missing)
				fmt.eprintln("  `--pin=template` takes this binary's pin instead; `just bump-ols` then re-chooses it")
				return 1
			}
			delete(content)
			content = kept

			if tag, tag_ok := toolchain_ols_tag(dest); tag_ok {
				note = strings.concatenate({"ols pin kept: ", tag})
				delete(tag)
			} else {
				note = strings.clone("ols pin kept")
			}
		}

		// An unreadable-but-present file is reported as `.Created` here and then fails on the write
		// below with an error naming the real problem, which beats guessing at one now.
		action := Sync_Action.Created
		if read_err == nil {
			action = string(existing) == content ? .Unchanged : .Updated
		}

		append(&items, Sync_Item{rel = tmpl.path, full = full, content = content, note = note, action = action})
	}

	// Only reachable with an empty `only` - the validation above proved every named path is syncable -
	// so it means this binary carries no syncable templates at all.
	if len(items) == 0 {
		fmt.eprintln(
			"odin-skel: no embedded templates are marked syncable - this binary and its template have drifted",
		)
		return 1
	}

	updated, created, unchanged := 0, 0, 0
	for item in items {
		switch item.action {
		case .Updated:
			updated += 1
		case .Created:
			created += 1
		case .Unchanged:
			unchanged += 1
		}
	}

	if check {
		if updated + created == 0 {
			fmt.printfln("odin-skel %s: %d syncable files are up to date", VERSION, len(items))
			return 0
		}
		fmt.eprintfln("odin-skel %s: %d syncable files have drifted", VERSION, updated + created)
		for item in items {
			if item.action != .Unchanged {
				fmt.eprintfln("  %-9s %s", sync_action_name(item.action), item.rel)
			}
		}
		fmt.eprintln("run `odin-skel sync` to bring them up to date")
		return 1
	}

	fmt.printfln("odin-skel %s -> %s%s", VERSION, dest, dry_run ? " (dry run)" : "")
	for item in items {
		if item.note != "" {
			fmt.printfln("  %-9s %s (%s)", sync_action_name(item.action), item.rel, item.note)
		} else {
			fmt.printfln("  %-9s %s", sync_action_name(item.action), item.rel)
		}
	}

	if updated + created == 0 {
		fmt.println("already up to date")
		return 0
	}

	// Only `.Updated` files have anything to lose: `.Created` means there was no file there to read.
	if updated > 0 && !dry_run {
		paths := make([dynamic]string, 0, updated, context.temp_allocator)
		for item in items {
			if item.action == .Updated {
				append(&paths, item.rel)
			}
		}
		dirty, checked := git_status(dest, paths[:])
		defer delete(dirty)

		switch {
		case !checked:
			fmt.eprintln()
			fmt.eprintln("odin-skel: warning: could not ask git what is committed here")
			fmt.eprintln("  these files are about to be overwritten with nothing to restore them from")
		case dirty != "" && !force:
			fmt.eprintln()
			fmt.eprintln("odin-skel: refusing - files this would overwrite are not committed:")
			fmt.eprintln(dirty)
			// `!!` means git found a repository above this directory and that repository ignores the
			// path, so "commit them" is not the advice - there is nothing here git will ever track.
			if strings.contains(dirty, "!!") {
				fmt.eprintln(
					"(!! is a path the only repository git found above here ignores, so it tracks nothing of yours)",
				)
			}
			fmt.eprintln("commit or stash them first, so the sync is a diff you can read and revert")
			fmt.eprintln("  `--force` overwrites them anyway, `--dry-run` shows what would change")
			return 1
		}
	}

	if dry_run {
		fmt.printfln("would update %d, create %d, leave %d unchanged", updated, created, unchanged)
		return 0
	}

	// No rollback, deliberately. Unlike `add`, which creates a directory that did not exist and can
	// therefore remove it again, this replaces files that did - so restoring them means restoring
	// their previous contents, which is what git is for and what the guard above insisted on. A
	// failure part way through names the files already written, so the diff is explicable.
	done := 0
	for item in items {
		if item.action == .Unchanged {
			continue
		}
		if dir := path_dir(item.full); dir != "" {
			if err := ensure_directory(dir); err != nil {
				fmt.eprintfln("odin-skel: could not create %q: %v", dir, err)
				fmt.eprintfln("  %d files were already written; `git diff` shows them", done)
				return 1
			}
		}
		if err := os.write_entire_file(item.full, transmute([]byte)item.content); err != nil {
			fmt.eprintfln("odin-skel: could not write %q: %v", item.full, err)
			fmt.eprintfln("  %d files were already written; `git diff` shows them", done)
			return 1
		}
		done += 1
	}

	fmt.printfln("updated %d, created %d, left %d unchanged", updated, created, unchanged)
	return 0
}

sync_action_name :: proc(action: Sync_Action) -> string {
	switch action {
	case .Unchanged:
		return "unchanged"
	case .Updated:
		return "updated"
	case .Created:
		return "created"
	}
	return "?"
}

/*
Ask git which of `paths` are not safely committed inside `dest`.

`--porcelain` reports modified, staged and untracked paths alike, which is exactly the set worth
refusing: an untracked file has no committed version to go back to either.

`--ignored=matching` closes a hole that reads as safety. Git searches upwards for a repository, so a
directory under no repository of its own is answered by some ancestor - a home-directory dotfiles repo
answers for everything below it. If that ancestor *ignores* the path, plain `--porcelain` prints
nothing and the sync proceeds believing the files are committed, when in truth git has never heard of
them. With this flag they come back as `!!` and are refused like any other uncommitted file.
`--untracked-files=all` names individual files rather than the directory holding them.

Returns `checked = false` when git could not answer - not installed, or nowhere near a repository -
which is a warning rather than a refusal, since having no history at all is the author's choice about
their whole tree. The caller owns `dirty`.
*/
@(require_results)
git_status :: proc(dest: string, paths: []string, allocator := context.allocator) -> (dirty: string, checked: bool) {
	command := make([dynamic]string, 0, len(paths) + 4, context.temp_allocator)
	append(&command, "git", "status", "--porcelain", "--untracked-files=all", "--ignored=matching", "--")
	for path in paths {
		append(&command, path)
	}

	result := probe(command[:], dest, allocator)
	if !result.found || result.exit_code != 0 {
		delete(result.output, allocator)
		return "", false
	}
	return result.output, true
}

/*
Splice the destination's ols pin lines into freshly rendered template text.

`rendered` is this binary's .just/toolchain.just, `existing` is the project's. Every prefix in
OLS_PIN_PREFIXES must appear in both, or the two files have drifted far enough that guessing would be
worse than failing: silently writing this binary's pin is the one outcome the caller is trying to
avoid.

Returns the offending prefix in `missing` when it does not hold, so the error can name it.
*/
@(require_results)
preserve_ols_pin :: proc(
	rendered: string,
	existing: string,
	allocator := context.allocator,
) -> (
	result: string,
	missing: string,
	ok: bool,
) {
	out := strings.clone(rendered, allocator)
	for prefix in OLS_PIN_PREFIXES {
		keep, found := line_with_prefix(existing, prefix)
		if !found {
			delete(out, allocator)
			return "", prefix, false
		}
		replaced, replaced_ok := replace_line_with_prefix(out, prefix, keep, allocator)
		delete(out, allocator)
		if !replaced_ok {
			return "", prefix, false
		}
		out = replaced
	}
	return out, "", true
}

// The first line of `text` beginning with `prefix`, without its newline. A borrowed slice of `text`.
@(require_results)
line_with_prefix :: proc(text: string, prefix: string) -> (line: string, ok: bool) {
	rest := text
	for candidate in strings.split_lines_iterator(&rest) {
		if strings.has_prefix(candidate, prefix) {
			return candidate, true
		}
	}
	return "", false
}

// Replace the first line beginning with `prefix` by `replacement`, keeping everything around it.
// Returns `ok = false` when there is no such line, like `rewrite_package_clause`.
@(require_results)
replace_line_with_prefix :: proc(
	text: string,
	prefix: string,
	replacement: string,
	allocator := context.allocator,
) -> (
	result: string,
	ok: bool,
) {
	rest := text
	offset := 0
	for len(rest) > 0 {
		line: string
		line_len := 0
		if i := strings.index_byte(rest, '\n'); i >= 0 {
			line, line_len = rest[:i], i + 1
		} else {
			line, line_len = rest, len(rest)
		}

		if strings.has_prefix(line, prefix) {
			tail := text[offset + len(line):]
			return strings.concatenate({text[:offset], replacement, tail}, allocator), true
		}

		offset += line_len
		rest = rest[line_len:]
	}
	return "", false
}

// Template paths come from `git ls-files` and always use forward slashes; a path typed on the command
// line may use either, on Windows in particular. Compared here rather than normalising a copy, so
// neither side has to be allocated.
@(require_results)
same_path :: proc(a: string, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		if a[i] == b[i] {
			continue
		}
		if !is_separator(a[i]) || !is_separator(b[i]) {
			return false
		}
	}
	return true
}

@(require_results)
path_in :: proc(paths: []string, path: string) -> bool {
	for candidate in paths {
		if same_path(candidate, path) {
			return true
		}
	}
	return false
}

@(require_results)
syncable_path :: proc(path: string) -> bool {
	for tmpl in TEMPLATES {
		if tmpl.sync && same_path(tmpl.path, path) {
			return true
		}
	}
	return false
}

@(require_results)
template_path :: proc(path: string) -> bool {
	for tmpl in TEMPLATES {
		if same_path(tmpl.path, path) {
			return true
		}
	}
	return false
}

// How deep `has_odin_source` will look. A bound rather than an unbounded walk: a directory symlink
// pointing at an ancestor would otherwise loop, and nothing legitimate buries the first .odin file
// this far down - the skeleton's own deepest is mylib/examples/basic.odin, at two.
ODIN_SEARCH_MAX_DEPTH :: 8

/*
Whether there is any .odin file under `dir`, at any depth.

The evidence that `dir` is an Odin project rather than some other directory that happens to have a
justfile. Any depth, because the three layouts this tool produces put source in different places: a
library at the root, an executable at the root with packages beside it, and neither is guaranteed once
a project has grown.

`.git` and `target` are skipped - the first can be enormous and holds no source, the second is build
output whose contents prove nothing about the project. An unreadable directory reads as "nothing here"
rather than an error: the caller only needs a yes, and the refusal it prints tells the user how to
override it.
*/
@(require_results)
has_odin_source :: proc(dir: string, depth := 0) -> bool {
	if depth > ODIN_SEARCH_MAX_DEPTH {
		return false
	}

	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		return false
	}

	// Files first, so the common case - source in the directory being checked - never descends at all.
	for entry in entries {
		if !os.is_directory(entry.fullpath) && strings.has_suffix(path_base(entry.fullpath), ".odin") {
			return true
		}
	}
	for entry in entries {
		if !os.is_directory(entry.fullpath) {
			continue
		}
		switch path_base(entry.fullpath) {
		case ".git", "target":
			continue
		}
		if has_odin_source(entry.fullpath, depth + 1) {
			return true
		}
	}
	return false
}
