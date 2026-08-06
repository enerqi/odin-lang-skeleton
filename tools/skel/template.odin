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
Strip `# >>> skeleton-only` ... `# <<< skeleton-only` blocks from the justfile.

Recipes inside those markers maintain the skeleton itself (scaffolding, the snippet and embed
generators, building this tool) and are meaningless in a generated project.

Other marker blocks - `snippet-exclude` today - are kept, but their marker comment lines are dropped
because they only mean something in the skeleton repo.

This must stay behaviourally identical to the `strip_skeleton_only` helper that `just new` used
before the cutover; the two were compared on the real justfile.
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

		trimmed := strings.trim_space(line)
		switch {
		case trimmed == "# >>> skeleton-only":
			skip = true
		case trimmed == "# <<< skeleton-only":
			skip = false
		case strings.has_prefix(trimmed, "# >>> "), strings.has_prefix(trimmed, "# <<< "):
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
