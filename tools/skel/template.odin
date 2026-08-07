package skel

import "core:strings"

// One embedded template file. `path` is repo-relative with forward slashes, as `git ls-files`
// reports it; `data` is the file's contents baked in at compile time.
//
// The list itself lives in the generated templates.odin - see `just embed`.
Template :: struct {
	path: string,
	data: string,
}

/*
Reduce a line to its marker text, or "" when it is not a marker.

Two spellings are recognised so the same mechanism works in both file types the skeleton strips:

	# >>> skeleton-only              justfile - a normal comment
	<!-- >>> skeleton-only -->       README.md - an HTML comment, invisible when the markdown renders

Markdown cannot use the `#` form: a line starting with `#` is a heading, so the marker would show up
as a title on the repository's front page.
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
Strip `>>> skeleton-only` ... `<<< skeleton-only` blocks.

Content inside those markers maintains the skeleton itself - the scaffolding, snippet and embed
recipes, and the notes on installing and releasing this tool - and is meaningless once the file has
been copied into a real project.

Other marker blocks - `snippet-exclude` today - keep their body, but their marker lines are dropped
because they only mean something in the skeleton repo.

Applied to the justfile, README.md and .gitattributes. The README needed it because it is copied
verbatim and was documenting recipes (`just new`, `just snippets`) that the stripped justfile no
longer contains; .gitattributes because its `linguist-generated` rules name `tools/`, which a
scaffolded project never receives.
*/
strip_skeleton_only :: proc(text: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	// The result is a fresh allocation below, so the builder's scratch buffer must not outlive us.
	defer strings.builder_destroy(&b)

	skip := false
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
		case marker == ">>> skeleton-only":
			skip = true
		case marker == "<<< skeleton-only":
			skip = false
		case strings.has_prefix(marker, ">>> "), strings.has_prefix(marker, "<<< "):
		// A different marker block: drop the marker line, keep the body.
		case !skip:
			strings.write_string(&b, line)
		}
	}

	// Normalise to exactly one trailing newline, matching the previous implementation's
	// `.rstrip("\n") + "\n"`.
	out := strings.trim_right(strings.to_string(b), "\n")
	return strings.concatenate({out, "\n"}, allocator)
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
