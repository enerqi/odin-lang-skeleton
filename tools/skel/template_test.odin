package skel

import "core:strings"
import "core:testing"

@(test)
test_strip_removes_skeleton_only_block :: proc(t: ^testing.T) {
	input := `keep_me:
	echo one

# >>> skeleton-only
drop_me:
	echo two
# <<< skeleton-only

also_keep:
	echo three
`
	got := strip_skeleton_only(input)
	defer delete(got)

	testing.expect(t, strings.contains(got, "keep_me:"))
	testing.expect(t, strings.contains(got, "also_keep:"))
	testing.expect(t, !strings.contains(got, "drop_me"), "skeleton-only recipe survived")
	testing.expect(t, !strings.contains(got, ">>>"), "marker line survived")
}

// Other marker blocks keep their body; only the marker comment lines go.
@(test)
test_strip_keeps_other_marker_bodies :: proc(t: ^testing.T) {
	input := `# >>> snippet-exclude
kept_recipe:
	echo hi
# <<< snippet-exclude
`
	got := strip_skeleton_only(input)
	defer delete(got)

	testing.expect(t, strings.contains(got, "kept_recipe:"), "body of a non-skeleton block was dropped")
	testing.expect(t, !strings.contains(got, "snippet-exclude"), "marker line survived")
}

@(test)
test_strip_normalises_trailing_newline :: proc(t: ^testing.T) {
	got := strip_skeleton_only("a:\n\techo a\n\n\n\n")
	defer delete(got)
	testing.expect(t, strings.has_suffix(got, "echo a\n"), "should end with exactly one newline")
	testing.expect(t, !strings.has_suffix(got, "\n\n"))
}

// The real justfile must survive the strip with its skeleton-only recipes gone and its template
// recipes intact. This is the case that actually matters, and it uses the embedded copy.
@(test)
test_strip_on_the_real_justfile :: proc(t: ^testing.T) {
	source := ""
	for tmpl in TEMPLATES {
		if tmpl.path == "justfile" {
			source = tmpl.data
			break
		}
	}
	testing.expect(t, source != "", "justfile missing from TEMPLATES - run `just embed`")

	got := strip_skeleton_only(source)
	defer delete(got)

	for gone in ([]string{"new dest", "build_skel", "lint_skel", "test_skel", "_embed", "_snippets"}) {
		testing.expectf(t, !strings.contains(got, gone), "skeleton-only recipe %q leaked", gone)
	}
	for kept in ([]string{"run_debug", "run_release_nochecks", "sanitize", "mktarget_dirs"}) {
		testing.expectf(t, strings.contains(got, kept), "template recipe %q was stripped", kept)
	}
	testing.expect(t, !strings.contains(got, "# >>>"), "a marker line leaked")
}

@(test)
test_zlib_license_shape :: proc(t: ^testing.T) {
	got := zlib_license(2026)
	defer delete(got)
	testing.expect(t, strings.has_prefix(got, "Copyright (c) 2026\n\n"), "needs a blank separator line")
	testing.expect(t, strings.contains(got, "This software is provided 'as-is'"))
	testing.expect(t, strings.has_suffix(got, "source distribution.\n"))
}

@(test)
test_path_helpers :: proc(t: ^testing.T) {
	testing.expect_value(t, path_base("a/b/c.txt"), "c.txt")
	testing.expect_value(t, path_base("a/b/"), "b")
	testing.expect_value(t, path_base(`a\b`), "b")
	testing.expect_value(t, path_base("solo"), "solo")
	testing.expect_value(t, path_dir("a/b/c.txt"), "a/b")
	testing.expect_value(t, path_dir("c.txt"), "")
}

@(test)
test_replace_base :: proc(t: ^testing.T) {
	nested := replace_base(".sublime/skeleton.sublime-project", "demo.sublime-project")
	defer delete(nested)
	testing.expect_value(t, nested, ".sublime/demo.sublime-project")

	flat := replace_base("skeleton.sublime-project", "demo.sublime-project")
	defer delete(flat)
	testing.expect_value(t, flat, "demo.sublime-project")
}

@(test)
test_join_path_collapses_separators :: proc(t: ^testing.T) {
	joined := join_path("out/", "a/b.txt")
	defer delete(joined)
	testing.expect_value(t, joined, "out/a/b.txt")
}

// tools/ must never reach a scaffolded project; the embed generator is what enforces it.
@(test)
test_templates_exclude_tooling :: proc(t: ^testing.T) {
	testing.expect(t, len(TEMPLATES) > 0, "no templates embedded - run `just embed`")
	for tmpl in TEMPLATES {
		testing.expectf(t, !strings.has_prefix(tmpl.path, "tools/"), "tooling file %q was embedded", tmpl.path)
	}
}

@(test)
test_templates_include_essentials :: proc(t: ^testing.T) {
	for want in ([]string{"justfile", "main.odin", "odinfmt.json", ".gitattributes", ".editorconfig"}) {
		found := false
		for tmpl in TEMPLATES {
			if tmpl.path == want {
				found = true
				break
			}
		}
		testing.expectf(t, found, "template %q missing - run `just embed`", want)
	}
}
