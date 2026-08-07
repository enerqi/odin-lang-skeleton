package skel

import "core:os"
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

// .gitattributes is the third stripped template. Its `linguist-generated` rules name `tools/`, which
// a scaffolded project never receives, and claim the snippets are generated when the recipe that
// generates them has itself been stripped. The line-ending rules underneath must survive - they are
// the reason the file is copied at all.
@(test)
test_strip_on_the_real_gitattributes :: proc(t: ^testing.T) {
	source := ""
	for tmpl in TEMPLATES {
		if tmpl.path == ".gitattributes" {
			source = tmpl.data
			break
		}
	}
	testing.expect(t, source != "", ".gitattributes missing from TEMPLATES - run `just embed`")

	got := strip_skeleton_only(source)
	defer delete(got)

	for gone in ([]string{"linguist-generated", "tools/skel"}) {
		testing.expectf(t, !strings.contains(got, gone), "skeleton-only rule %q leaked", gone)
	}
	// `.sublime/**` is vendored, not generated, so unlike the rules above it must survive: a
	// scaffolded project gets the same editor files and the same reason to keep them out of its
	// language statistics.
	for kept in ([]string{"* text=auto eol=lf", "*.ps1 text eol=crlf", "*.dylib binary", ".sublime/** linguist-vendored=true"}) {
		testing.expectf(t, strings.contains(got, kept), "template rule %q was stripped", kept)
	}
	testing.expect(t, !strings.contains(got, "# >>>"), "a marker line leaked")
}

// Headings shift one level, a `#` that is shell rather than markdown is left alone, and the project
// gets the H1.
@(test)
test_project_readme_demotes_headings :: proc(t: ^testing.T) {
	input :=
		`# Skeleton

## Quick start

` +
		"```sh\n" +
		`# not a heading, this is a shell comment
just run
` +
		"```\n" +
		`### Deep

###### Already at the limit
#no-space-so-not-a-heading
`
	got := project_readme(input, "myproj")
	defer delete(got)

	testing.expect(t, strings.has_prefix(got, "# myproj\n\n\n## Skeleton"), "title or spacing wrong")
	testing.expect(t, strings.contains(got, "\n## Skeleton\n"), "H1 should become H2")
	testing.expect(t, strings.contains(got, "\n### Quick start\n"), "H2 should become H3")
	testing.expect(t, strings.contains(got, "\n#### Deep\n"), "H3 should become H4")
	testing.expect(t, strings.contains(got, "\n###### Already at the limit\n"), "H6 must not grow a seventh #")
	testing.expect(
		t,
		strings.contains(got, "\n# not a heading, this is a shell comment\n"),
		"a # inside a fenced block must not be demoted",
	)
	testing.expect(t, strings.contains(got, "\n#no-space-so-not-a-heading\n"), "# without a space is not a heading")
}

// The real README must come out with exactly one H1 - the project's - and nothing left at the level
// it had before.
@(test)
test_project_readme_on_the_real_readme :: proc(t: ^testing.T) {
	source := ""
	for tmpl in TEMPLATES {
		if tmpl.path == "README.md" {
			source = tmpl.data
			break
		}
	}
	testing.expect(t, source != "", "README.md missing from TEMPLATES - run `just embed`")

	stripped := strip_skeleton_only(source)
	defer delete(stripped)
	got := project_readme(stripped, "myproj")
	defer delete(got)

	testing.expect(t, strings.has_prefix(got, "# myproj\n\n\n"), "the project H1 is missing")
	// One `# ` at the very start and none after it: `count` sees the leading one via the "\n# "
	// probe only if preceded by a newline, so the prefix check above covers the first.
	testing.expect_value(t, strings.count(got, "\n# "), 0)
	testing.expect(
		t,
		strings.contains(got, "\n## Odin Programming Language Project Skeleton\n"),
		"the old H1 should now be an H2",
	)
	// Every heading that survives the strip is an H2 - the H3s all live in skeleton-only sections -
	// so this is the deepest level the scaffolded README can exercise.
	testing.expect(t, strings.contains(got, "\n### Choosing a linker\n"), "an H2 should now be an H3")
	// Anchors come from heading text, not level, so an in-document link and the heading it points
	// at must both still be there - and matched to each other - after the demotion.
	testing.expect(t, strings.contains(got, "(#language-server-configuration)"), "anchor link damaged")
	testing.expect(
		t,
		strings.contains(got, "\n### Language Server Configuration\n"),
		"the heading that anchor points at is missing or at an unexpected level",
	)
}

@(test)
test_valid_linker :: proc(t: ^testing.T) {
	for good in LINKERS {
		testing.expectf(t, valid_linker(good), "%q should be accepted", good)
	}
	// `gold` and `ld` are real linkers, just not ones Odin's `-linker:` takes - the likeliest wrong
	// answer, and the one worth failing on rather than passing straight through to the compiler.
	for bad in ([]string{"", "gold", "ld", "gnu-ld", "gcc", "Default", "RADLINK"}) {
		testing.expectf(t, !valid_linker(bad), "%q should be rejected", bad)
	}
}

// The `--linker` rewrite runs against the real embedded justfile, so a reworded default or a moved
// line fails here rather than silently producing a project whose linker choice was ignored.
@(test)
test_set_linker_default_on_the_real_justfile :: proc(t: ^testing.T) {
	source := ""
	for tmpl in TEMPLATES {
		if tmpl.path == "justfile" {
			source = tmpl.data
			break
		}
	}
	testing.expect(t, source != "", "justfile missing from TEMPLATES - run `just embed`")

	stripped := strip_skeleton_only(source)
	defer delete(stripped)
	testing.expect(
		t,
		strings.contains(stripped, "if os() == \"windows\""),
		"the per-OS default should survive the skeleton-only strip",
	)

	got, ok := set_linker_default(stripped, "mold")
	testing.expect(t, ok, "the `linker :=` anchor was not found")
	defer delete(got)

	testing.expect(
		t,
		strings.contains(got, "linker := env_var_or_default(\"ODIN_LINKER\", \"mold\")\n"),
		"the pinned assignment was not written",
	)
	testing.expect(t, !strings.contains(got, "if os() =="), "the per-OS conditional survived")
	// Only the one line may change: the recipes that consume {{linker}} and the comment block above
	// the assignment both have to come through untouched.
	testing.expect(t, strings.contains(got, "-linker:{{linker}} -out:"), "the recipes were damaged")
	testing.expect(t, strings.contains(got, "ODIN_LINKER=lld just run"), "the comment block was damaged")
	testing.expect_value(t, strings.count(got, "\n"), strings.count(stripped, "\n"))
}

// A justfile that no longer carries the anchor must report failure rather than quietly scaffolding a
// project where `--linker` did nothing.
@(test)
test_set_linker_default_missing_anchor :: proc(t: ^testing.T) {
	_, ok := set_linker_default("main_name := \"main.exe\"\n", "mold")
	testing.expect(t, !ok, "a missing anchor must not report success")
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

/*
Regression test for the CI failure where scaffolding worked on Windows and failed on Linux and macOS.

`os.make_directory_all` returns `General_Error.Exist` for an existing directory on POSIX but succeeds
on Windows, so every template file after the first in a directory aborted `new` on non-Windows. This
asserts the idempotence directly rather than relying on a platform to expose it.
*/
@(test)
test_ensure_directory_is_idempotent :: proc(t: ^testing.T) {
	root, terr := os.make_directory_temp("", "odin-skel-test-*", context.allocator)
	if !testing.expect_value(t, terr, nil) {
		return
	}
	defer {
		os.remove_all(root)
		delete(root)
	}

	nested := strings.concatenate({root, "/a/b"})
	defer delete(nested)

	testing.expect_value(t, ensure_directory(nested), nil)
	// The call that used to fail: same directory, already present.
	testing.expect_value(t, ensure_directory(nested), nil)
	// And an existing intermediate with a new leaf below it.
	deeper := strings.concatenate({nested, "/c"})
	defer delete(deeper)
	testing.expect_value(t, ensure_directory(deeper), nil)

	testing.expect(t, os.is_directory(deeper))
}

// A file where a directory is expected must stay an error on every platform. Windows reports it as
// `.Exist`, the same code POSIX uses for the harmless "already there" case, so tolerating `.Exist`
// unconditionally would silently swallow it.
@(test)
test_ensure_directory_rejects_a_file_in_the_way :: proc(t: ^testing.T) {
	root, terr := os.make_directory_temp("", "odin-skel-test-*", context.allocator)
	if !testing.expect_value(t, terr, nil) {
		return
	}
	defer {
		os.remove_all(root)
		delete(root)
	}

	blocker := strings.concatenate({root, "/blocker"})
	defer delete(blocker)
	testing.expect_value(t, os.write_entire_file(blocker, transmute([]byte)string("x")), nil)

	testing.expect(t, ensure_directory(blocker) != nil, "a file in the way must not be reported as success")
}

// Markdown cannot use the justfile's `# >>>` spelling: a leading `#` is a heading, so the marker
// would render as a title on the repository front page. HTML comments are invisible instead.
@(test)
test_strip_handles_html_comment_markers :: proc(t: ^testing.T) {
	input := `keep this

<!-- >>> skeleton-only -->
drop this
<!-- <<< skeleton-only -->

keep this too
`
	got := strip_skeleton_only(input)
	defer delete(got)

	testing.expect(t, strings.contains(got, "keep this"))
	testing.expect(t, strings.contains(got, "keep this too"))
	testing.expect(t, !strings.contains(got, "drop this"), "skeleton-only markdown survived")
	testing.expect(t, !strings.contains(got, "skeleton-only"), "marker line survived")
}

// A `#` heading must not be mistaken for a marker comment now that markdown is stripped too.
@(test)
test_strip_keeps_markdown_headings :: proc(t: ^testing.T) {
	got := strip_skeleton_only("# Title\n\n## Section\n\ntext\n")
	defer delete(got)
	testing.expect(t, strings.contains(got, "# Title"), "a markdown H1 was eaten")
	testing.expect(t, strings.contains(got, "## Section"))
}

// The real README must lose its skeleton-only sections and keep everything a project still needs.
@(test)
test_strip_on_the_real_readme :: proc(t: ^testing.T) {
	source := ""
	for tmpl in TEMPLATES {
		if tmpl.path == "README.md" {
			source = tmpl.data
			break
		}
	}
	testing.expect(t, source != "", "README.md missing from TEMPLATES - run `just embed`")

	got := strip_skeleton_only(source)
	defer delete(got)

	// "just new", "just snippets" and "odin-skel" name recipes and a binary that a scaffolded
	// project does not have, so any mention of them is a leak wherever it appears in the file.
	for gone in ([]string{"Installing odin-skel", "Cutting a release", "just new", "just embed", "just snippets", "odin-skel", "skeleton-only"}) {
		testing.expectf(t, !strings.contains(got, gone), "skeleton-only README content %q leaked", gone)
	}
	// "Choosing a linker" documents a justfile variable the scaffolded project still has, so it must
	// stay outside the markers however the section is nested or moved.
	for kept in ([]string{"just run", "just lint", "Language Server Configuration", "Choosing a linker"}) {
		testing.expectf(t, strings.contains(got, kept), "README content %q was stripped", kept)
	}
}
