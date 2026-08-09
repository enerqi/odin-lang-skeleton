package skel

import "core:strings"

// What shape of project `new` is scaffolding. `--lib` selects `.Lib`; everything else is `.Exe`.
Project_Kind :: enum {
	Exe,
	Lib,
}

// Which project kinds a template file belongs to. `.Both` is the zero value so the generated
// templates.odin only has to name the exceptions.
Template_Kind :: enum {
	Both,
	Exe,
	Lib,
}

// One embedded template file. `path` is repo-relative with forward slashes, as `git ls-files`
// reports it; `data` is the file's contents baked in at compile time.
//
// The list itself lives in the generated templates.odin - see `just embed`.
Template :: struct {
	path: string,
	data: string,
	kind: Template_Kind,
}

@(require_results)
template_wanted :: proc(tmpl: Template_Kind, project: Project_Kind) -> bool {
	switch tmpl {
	case .Both:
		return true
	case .Exe:
		return project == .Exe
	case .Lib:
		return project == .Lib
	}
	return false
}

/*
The directory holding the lib template inside this repository, and the placeholder package name its
files declare.

They are the same word on purpose: `lib_out_path` strips the directory prefix and then renames any
file whose base name starts with it, so `mylib/mylib_test.odin` lands as `<pkg>_test.odin` without a
second rule. See tools/DESIGN.md, "Keeping the lib template live".
*/
LIB_TEMPLATE_DIR :: "mylib"
LIB_TEMPLATE_PACKAGE :: "mylib"

/*
Marker blocks stripped when scaffolding, by project kind. `skeleton-only` goes in both directions; the
kind markers keep one shape's recipes and prose out of the other's files.

Backed by `@(rodata)` arrays rather than written as `::` slice constants, because a constant slice
returned from `drop_names` does not survive the return: the compiler materialises the literal into the
callee's frame, and by the time `strip_marked_blocks` iterates it, the memory is gone. That failed
silently and in the worst possible way - every name compared unequal, so nothing was ever dropped and
scaffolding produced a justfile with the skeleton's own recipes still in it, no error anywhere. A
static array has a lifetime that outlives the call.
*/
@(rodata)
drop_for_exe := [?]string{"skeleton-only", "lib-only"}

@(rodata)
drop_for_lib := [?]string{"skeleton-only", "exe-only"}

@(require_results)
drop_names :: proc(kind: Project_Kind) -> []string {
	return kind == .Lib ? drop_for_lib[:] : drop_for_exe[:]
}

/*
Reduce a line to its marker text, or "" when it is not a marker.

Two spellings are recognised so the same mechanism works in both file types the skeleton strips:

	# >>> skeleton-only              justfile - a normal comment
	<!-- >>> skeleton-only -->       README.md - an HTML comment, invisible when the markdown renders

Markdown cannot use the `#` form: a line starting with `#` is a heading, so the marker would show up
as a title on the repository's front page.

There is deliberately no `//` spelling for the `.sublime-build` files. They are not stripped at all:
`just install-sublime` copies them into Sublime's global `Packages/User`, where they match on
`source.odin` and serve every Odin project on the machine, so they must list both kinds' recipes
rather than the scaffolded project's.
*/
marker_text :: proc(trimmed: string) -> string {
	if strings.has_prefix(trimmed, "# ") {
		return strings.trim_space(trimmed[2:])
	}
	if strings.has_prefix(trimmed, "<!--") && strings.has_suffix(trimmed, "-->") {
		return strings.trim_space(trimmed[4:len(trimmed) - 3])
	}
	return ""
}

/*
Strip the marker blocks named in `drop`, body and markers together.

`skeleton-only` content maintains the skeleton itself - the scaffolding, snippet and embed recipes,
and the notes on installing and releasing this tool - and is meaningless once the file has been copied
into a real project. `exe-only` and `lib-only` carry the parts of the justfile and README that belong
to one project shape and would be wrong in the other: the five-tier build ladder means nothing to a
library, and `just example` means nothing to a program.

Every other marker block - `snippet-exclude` today - keeps its body, but its marker lines are dropped
because they only mean something in the skeleton repo.

Applied to the justfile, README.md and .gitattributes. The README needed it because it is copied
verbatim and was documenting recipes (`just new`, `just snippets`) that the stripped justfile no
longer contains; .gitattributes because its `linguist-generated` rules name `tools/`, which a
scaffolded project never receives.

Only the marker that opened a drop can close it, and nothing re-opens one while a drop is already open.
Blocks do not nest today; tracking the open block's name rather than a bare flag costs nothing and
means a future nested block cannot silently spill the rest of its parent into the output.

An unterminated block is not detected here - the templates are compiled in, so it cannot vary at
runtime, and `test_embedded_templates_have_balanced_markers` catches it at build time instead.
*/
strip_marked_blocks :: proc(text: string, drop: []string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	// The result is a fresh allocation below, so the builder's scratch buffer must not outlive us.
	defer strings.builder_destroy(&b)

	// The name of the block currently being dropped, or "" for none.
	dropping := ""
	rest := text
	for len(rest) > 0 {
		line: string
		if i := strings.index_byte(rest, '\n'); i >= 0 {
			line, rest = rest[:i + 1], rest[i + 1:]
		} else {
			line, rest = rest, ""
		}

		marker := marker_text(strings.trim_space(line))
		switch {
		case strings.has_prefix(marker, ">>> "):
			// A block not being dropped still loses its marker line: it only means something here.
			if name := marker[4:]; dropping == "" && name_in(drop, name) {
				dropping = name
			}
		case strings.has_prefix(marker, "<<< "):
			if dropping == marker[4:] {
				dropping = ""
			}
		case dropping == "":
			strings.write_string(&b, line)
		}
	}

	// Normalise to exactly one trailing newline, matching the previous implementation's
	// `.rstrip("\n") + "\n"`.
	out := strings.trim_right(strings.to_string(b), "\n")
	return strings.concatenate({out, "\n"}, allocator)
}

@(require_results)
name_in :: proc(names: []string, name: string) -> bool {
	for candidate in names {
		if candidate == name {
			return true
		}
	}
	return false
}

/*
Where a lib template file lands in a scaffolded project.

The template lives under `mylib/` here because this repository's root is already `package main`, but a
scaffolded library's root IS the package - that is the layout the surrounding Odin ecosystem uses (see
tools/DESIGN.md, Decision 4a). So the directory prefix is stripped, and a base name starting with the
placeholder package is renamed to the real one:

	mylib/mylib.odin           -> <pkg>.odin
	mylib/mylib_test.odin      -> <pkg>_test.odin
	mylib/examples/basic.odin  -> examples/basic.odin

Returns `ok = false` for a path that is not under the template directory, which would mean the embed
list and this rule have drifted apart.
*/
@(require_results)
lib_out_path :: proc(path: string, pkg: string, allocator := context.allocator) -> (result: string, ok: bool) {
	PREFIX :: LIB_TEMPLATE_DIR + "/"
	if !strings.has_prefix(path, PREFIX) {
		return "", false
	}
	rel := path[len(PREFIX):]

	base := path_base(rel)
	if !strings.has_prefix(base, LIB_TEMPLATE_PACKAGE) {
		return strings.clone(rel, allocator), true
	}
	renamed := strings.concatenate({pkg, base[len(LIB_TEMPLATE_PACKAGE):]}, allocator)
	defer delete(renamed, allocator)
	if dir := path_dir(rel); dir != "" {
		return strings.concatenate({dir, "/", renamed}, allocator), true
	}
	return strings.clone(renamed, allocator), true
}

/*
Rewrite the lib template's `package mylib` clause to the project's own package name.

Matched on a whole line so that prose mentioning the word is left alone - the template's own doc
comment talks about package names at length, and `odin-mylib` appears in it as an example of a
directory name.

Returns `ok = false` when no such line exists. Callers apply this only to the files that must declare
the library package (those at the template's root); the examples are `package main` and are never
passed through it, so a missing clause means the template changed shape and is worth failing on -
the same contract `set_linker_default` has.
*/
@(require_results)
rewrite_package_clause :: proc(
	text: string,
	pkg: string,
	allocator := context.allocator,
) -> (
	result: string,
	ok: bool,
) {
	CLAUSE :: "package " + LIB_TEMPLATE_PACKAGE

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

		if strings.trim_space(line) == CLAUSE {
			tail := text[offset + len(line):]
			return strings.concatenate({text[:offset], "package ", pkg, tail}, allocator), true
		}

		offset += line_len
		rest = rest[line_len:]
	}
	return "", false
}

/*
Target names Odin reads as a build tag on the END OF A FILE NAME - `foo_windows.odin` is compiled only
when targeting Windows.

This is a constraint on the package name because the lib template names its file after the package:
`--pkg=odin_js` writes `odin_js.odin`, whose trailing `_js` excludes it from every target but
WebAssembly/JS. The scaffold succeeds, and then the library's own contents are invisible - `just check`
reports `Undeclared name: add` about a procedure that is right there in the file.

Taken from the compiler's own tables, `src/build_settings.cpp` (`target_os_names`, `target_arch_names`).
*/
ODIN_TARGET_SUFFIXES :: []string {
	// operating systems
	"windows",
	"darwin",
	"linux",
	"freebsd",
	"openbsd",
	"netbsd",
	"wasi",
	"js",
	"orca",
	"freestanding",
	// architectures
	"amd64",
	"i386",
	"arm32",
	"arm64",
	"wasm32",
	"wasm64p32",
	"riscv64",
}

// Words Odin reserves. A package clause using one is a compile error, and the error points at the
// generated file rather than at the name that was passed in, so it is caught here instead.
ODIN_KEYWORDS :: []string {
	"asm",
	"auto_cast",
	"bit_field",
	"bit_set",
	"break",
	"case",
	"cast",
	"context",
	"continue",
	"defer",
	"distinct",
	"do",
	"dynamic",
	"else",
	"enum",
	"fallthrough",
	"for",
	"foreign",
	"if",
	"import",
	"in",
	"map",
	"matrix",
	"not_in",
	"or_break",
	"or_continue",
	"or_else",
	"or_return",
	"package",
	"proc",
	"return",
	"struct",
	"switch",
	"transmute",
	"typeid",
	"union",
	"using",
	"when",
	"where",
}

/*
Derive a legal Odin package name from a project name.

A project name only ever had to be a directory name before, and `odin-mylib` is a perfectly good one.
It is not a legal package clause: a hyphen is not an identifier character. So the separators people
actually type - `-`, `.` and spaces - become underscores, and everything else is rejected rather than
mangled, because silently dropping characters produces a package name the author did not choose and
will not recognise.

Returns `ok = false` with a reason for anything that cannot be repaired this way.
*/
@(require_results)
odin_package_name :: proc(
	project: string,
	allocator := context.allocator,
) -> (
	name: string,
	reason: string,
	ok: bool,
) {
	if project == "" {
		return "", "it is empty", false
	}

	b := strings.builder_make(allocator)
	defer strings.builder_destroy(&b)

	for i in 0 ..< len(project) {
		c := project[i]
		switch {
		case c == '-', c == '.', c == ' ', c == '_':
			strings.write_byte(&b, '_')
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
			strings.write_byte(&b, c)
		case:
			// Byte-wise, so anything outside ASCII lands here. Odin identifiers do accept unicode
			// letters, so the message names the constraint this check actually imposes rather than
			// telling somebody scaffolding `../café` that `é` is not a letter.
			return "", "it contains characters outside ASCII letters, digits, `-`, `.`, `_` and spaces", false
		}
	}

	candidate := strings.to_string(b)
	// A leading digit is the one case a substitution cannot fix: `2d_math` is not an identifier and
	// `_2d_math` would be a name nobody asked for.
	if candidate[0] >= '0' && candidate[0] <= '9' {
		return "", "it starts with a digit", false
	}
	if name_in(ODIN_KEYWORDS, candidate) {
		return "", "it is an Odin keyword", false
	}
	// Legal Odin, but not here: the examples are `package main` and import the library, and two
	// packages of the same name in one build is an error. It surfaces as a compile failure in
	// `just example` long after scaffolding claimed success, so it is caught with the other names
	// that cannot work.
	if candidate == "main" {
		return "", "the examples are `package main`, so the library cannot also be called `main`", false
	}
	// The package file is named after the package, and Odin reads a trailing target name in a file name
	// as a build tag. `odin_js` would write `odin_js.odin`, compiled on nothing but a JS target.
	// Every other reason is a literal, so this one is too: an allocated message would be the only
	// return the caller had to free.
	for suffix in ODIN_TARGET_SUFFIXES {
		if len(candidate) > len(suffix) + 1 &&
		   strings.has_suffix(candidate, suffix) &&
		   candidate[len(candidate) - len(suffix) - 1] == '_' {
			return "",
				"the package file is named after the package, and Odin reads a trailing target name (`_js`, `_linux`, `_amd64`, ...) in a file name as a build tag - the package would compile on that one target only",
				false
		}
	}
	// `_` alone is Odin's blank identifier, and a name made entirely of separators leaves nothing of
	// the project in it anyway.
	if strings.trim_left(candidate, "_") == "" {
		return "", "it has no letters or digits in it", false
	}
	// Odin refuses to compile a source file whose name starts with `_`, and the package file is named
	// after the package: `--pkg=_internal` scaffolds cleanly and then fails on the first `just check`
	// with `Files cannot start with '_'`. A leading separator in the project name lands here too, since
	// separators become underscores above (`.mylib` -> `_mylib`).
	//
	// This also closes the only gap in the target-suffix check below, which requires at least one
	// character before the `_` and so could not have rejected a bare `_js`.
	if candidate[0] == '_' {
		return "", "Odin will not compile a file whose name starts with `_`, and the file is named after the package", false
	}

	return strings.clone(candidate, allocator), "", true
}

/*
Give the scaffolded README the project's own H1 and demote everything it already had.

The copied README is reference material for the tooling - build tiers, linker choice, editor setup -
not the project's own front page. Left as-is it opens with "# Odin Programming Language Project
Skeleton", which is the wrong title for somebody else's project and leaves nowhere obvious to write
what the project actually *is*. So the whole document drops one level and a fresh H1 carrying the
project name goes on top, with blank lines under it for the description the author will want to add.

Anchor links survive this untouched: markdown anchors come from the heading text, not its level, so
`[Choosing a linker](#choosing-a-linker)` still resolves after the heading becomes an H3.

Only ATX headings (`# foo`) are touched, and only outside fenced code blocks - the README is full of
```sh blocks, and a `# comment` inside one is shell, not a heading. The skeleton's own README bottoms
out at H3 so nothing is near markdown's H6 limit, but a heading already at H6 is left alone rather
than growing a seventh `#`, which renders as literal text.
*/
project_readme :: proc(text: string, project: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	defer strings.builder_destroy(&b)

	strings.write_string(&b, "# ")
	strings.write_string(&b, project)
	strings.write_string(&b, "\n\n\n")

	in_fence := false
	rest := text
	for len(rest) > 0 {
		line: string
		if i := strings.index_byte(rest, '\n'); i >= 0 {
			line, rest = rest[:i + 1], rest[i + 1:]
		} else {
			line, rest = rest, ""
		}

		if strings.has_prefix(line, "```") {
			in_fence = !in_fence
		} else if !in_fence && strings.has_prefix(line, "#") {
			level := 0
			for level < len(line) && line[level] == '#' {
				level += 1
			}
			// `#` must be followed by a space to be a heading rather than `#!/bin/sh` or `#include`.
			if level < 6 && level < len(line) && line[level] == ' ' {
				strings.write_byte(&b, '#')
			}
		}
		strings.write_string(&b, line)
	}

	return strings.clone(strings.to_string(b), allocator)
}

// The values `odin build -linker:` accepts. Kept in the same order the compiler lists them so the
// error message below reads like `odin -help`.
LINKERS :: []string{"default", "lld", "radlink", "mold"}

// The justfile line `set_linker_default` rewrites. Matching on the assignment rather than the whole
// expression means the per-OS default can be reworded without breaking scaffolding.
LINKER_ASSIGN :: "linker := env_var_or_default(\"ODIN_LINKER\", "

@(require_results)
valid_linker :: proc(value: string) -> bool {
	for candidate in LINKERS {
		if candidate == value {
			return true
		}
	}
	return false
}

/*
Replace the justfile's per-OS linker default with an unconditional `value`.

The skeleton ships a default that depends on the platform it is building on:

	linker := env_var_or_default("ODIN_LINKER", if os() == "windows" { "radlink" } else { "default" })

`odin-skel new --linker=mold` turns that into a flat choice the whole project agrees on:

	linker := env_var_or_default("ODIN_LINKER", "mold")

Only the assignment is rewritten. The comment block above it documents all four values and the
ODIN_LINKER override, which stays true either way, so there is no second copy of that prose living
in this binary to drift out of step with the justfile.

Returns `ok = false` when the anchor is missing, which means the justfile changed shape - the same
"fail loudly rather than silently skip" contract `field_sub` has in the snippet generator.
*/
set_linker_default :: proc(text: string, value: string, allocator := context.allocator) -> (result: string, ok: bool) {
	start := strings.index(text, LINKER_ASSIGN)
	if start < 0 {
		return "", false
	}
	// The assignment runs to the end of its line; just has no line continuations to worry about.
	rest := text[start:]
	line_len := strings.index_byte(rest, '\n')
	if line_len < 0 {
		line_len = len(rest)
	}

	return strings.concatenate({text[:start], LINKER_ASSIGN, "\"", value, "\")", rest[line_len:]}, allocator), true
}

ZLIB_LICENSE_BODY :: `
This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.

3. This notice may not be removed or altered from any source distribution.
`

/*
Build a fresh Zlib licence for `year`.

The skeleton itself is Unlicense, but a generated project gets Zlib to match the Odin project's own
licence. That is why LICENSE is embedded yet never copied verbatim.
*/
zlib_license :: proc(year: int, allocator := context.allocator) -> string {
	// ZLIB_LICENSE_BODY opens with the newline that follows the backtick, so appending it straight
	// after the copyright line yields the blank separator line the licence text needs.
	year_text := itoa(year, allocator)
	defer delete(year_text, allocator)
	return strings.concatenate({"Copyright (c) ", year_text, "\n", ZLIB_LICENSE_BODY}, allocator)
}

// Small non-allocating-path integer formatter; avoids pulling core:strconv in for one call.
itoa :: proc(value: int, allocator := context.allocator) -> string {
	if value == 0 {
		return strings.clone("0", allocator)
	}
	buf: [20]byte
	i := len(buf)
	v := value
	neg := v < 0
	if neg {
		v = -v
	}
	for v > 0 {
		i -= 1
		buf[i] = byte('0' + v % 10)
		v /= 10
	}
	if neg {
		i -= 1
		buf[i] = '-'
	}
	return strings.clone(string(buf[i:]), allocator)
}
