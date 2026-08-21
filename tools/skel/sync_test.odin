package skel

import "core:strings"
import "core:testing"

// The set has to be non-empty, or `sync` reports drift and does nothing. Named files rather than a
// count, so adding a syncable template does not need this test edited but losing one of these does.
@(test)
test_syncable_set_contents :: proc(t: ^testing.T) {
	expected := []string {
		".editorconfig",
		".gitattributes",
		".gitignore",
		".just/editor.just",
		".just/toolchain.just",
		"odinfmt.json",
	}
	for path in expected {
		testing.expectf(
			t,
			syncable_path(path),
			"%s is not marked sync = true - check SYNCABLE_FILES in the justfile",
			path,
		)
	}
}

// The files `sync` must never touch, because they carry either the author's work or the project's own
// identity. A template that gained `sync = true` by accident shows up here rather than as somebody's
// justfile being replaced.
@(test)
test_syncable_excludes_hand_edited :: proc(t: ^testing.T) {
	for path in ([]string{"justfile", "README.md", "LICENSE", "main.odin"}) {
		testing.expectf(t, !syncable_path(path), "%s is marked sync = true and must never be", path)
	}
	for tmpl in TEMPLATES {
		if strings.has_prefix(tmpl.path, ".sublime/") {
			testing.expect(t, !tmpl.sync, "the .sublime files are starting points, not settings")
		}
		// Feature files arrive through `add`, which refuses an existing directory precisely because it
		// cannot tell an untouched copy from a week's work. Syncing one would do what that refuses.
		if tmpl.feature != "" {
			testing.expect(t, !tmpl.sync, "a feature file must not be syncable")
		}
	}
}

/*
The invariant `sync` rests on: every syncable file renders the same for both project kinds, so the
command never has to work out whether the destination is an executable or a library.

Without this, syncing would either have to guess the kind or would write a library's file into an
executable. A syncable template that gained an `exe-only` / `lib-only` block fails here.
*/
@(test)
test_syncable_templates_are_kind_independent :: proc(t: ^testing.T) {
	for tmpl in TEMPLATES {
		if !tmpl.sync {
			continue
		}
		as_exe := strip_marked_blocks(tmpl.data, drop_names(.Exe))
		defer delete(as_exe)
		as_lib := strip_marked_blocks(tmpl.data, drop_names(.Lib))
		defer delete(as_lib)
		testing.expectf(
			t,
			as_exe == as_lib,
			"%s differs between project kinds - it has an exe-only or lib-only block",
			tmpl.path,
		)
	}
}

// The real embedded toolchain fragment must carry every pin line `sync` promises to carry over. Were
// one renamed here, a sync would write this binary's value into a project that had chosen its own.
@(test)
test_real_toolchain_has_the_pin_lines :: proc(t: ^testing.T) {
	rendered := strip_marked_blocks(embedded_template(TOOLCHAIN_FRAGMENT), drop_names(.Exe))
	defer delete(rendered)

	for prefix in OLS_PIN_PREFIXES {
		_, found := line_with_prefix(rendered, prefix)
		testing.expectf(t, found, "the stripped toolchain fragment declares no line starting %q", prefix)
	}
}

// The case the whole command is built around: a project whose pin has moved on keeps it, and takes
// everything else from the binary.
@(test)
test_preserve_ols_pin_keeps_the_projects_pin :: proc(t: ^testing.T) {
	rendered := strip_marked_blocks(embedded_template(TOOLCHAIN_FRAGMENT), drop_names(.Exe))
	defer delete(rendered)

	// Stands in for a project that has run `just bump-ols` since this binary was built. Same length as
	// the shipped tag, so the assertion below can tell "only the pin moved" from "text was lost".
	NEWER :: "ols_tag := \"dev-2099-12\""
	existing, existing_ok := replace_line_with_prefix(rendered, "ols_tag := ", NEWER)
	defer delete(existing)
	testing.expect(t, existing_ok)

	kept, missing, ok := preserve_ols_pin(rendered, existing)
	defer delete(kept)
	testing.expect(t, ok, "both pin lines are present in both files")
	testing.expect_value(t, missing, "")

	tag, found := line_with_prefix(kept, "ols_tag := ")
	testing.expect(t, found)
	testing.expect_value(t, tag, NEWER)

	testing.expect(t, kept != rendered, "the pin line should have changed")
	testing.expect(t, len(kept) == len(existing), "nothing but the pin lines should have moved")
}

// An identical pin must round-trip to identical text, so syncing an up-to-date project reports
// `unchanged` instead of rewriting the file every time it runs.
@(test)
test_preserve_ols_pin_is_a_no_op_when_equal :: proc(t: ^testing.T) {
	rendered := strip_marked_blocks(embedded_template(TOOLCHAIN_FRAGMENT), drop_names(.Exe))
	defer delete(rendered)

	kept, _, ok := preserve_ols_pin(rendered, rendered)
	defer delete(kept)
	testing.expect(t, ok)
	testing.expect(t, kept == rendered, "carrying a pin over from an identical file must change nothing")
}

// A destination file with no pin line fails rather than falling back to this binary's pin. That
// fallback is the exact outcome `--pin=keep` exists to prevent, so it must not happen by accident.
@(test)
test_preserve_ols_pin_reports_a_missing_line :: proc(t: ^testing.T) {
	rendered := strip_marked_blocks(embedded_template(TOOLCHAIN_FRAGMENT), drop_names(.Exe))
	defer delete(rendered)

	_, missing, ok := preserve_ols_pin(rendered, "# an old toolchain fragment with no pin in it\n")
	testing.expect(t, !ok, "a destination with no pin must not silently take the template's")
	testing.expect_value(t, missing, "ols_tag := ")
}

@(test)
test_line_with_prefix :: proc(t: ^testing.T) {
	text := "# ols_tag mentioned in a comment\nols_tag := \"dev-2026-06\"\nother := 1\n"

	// Anchored at the start of a line, so the comment above cannot be matched instead.
	line, ok := line_with_prefix(text, "ols_tag := ")
	testing.expect(t, ok)
	testing.expect_value(t, line, "ols_tag := \"dev-2026-06\"")

	_, missing_ok := line_with_prefix(text, "absent := ")
	testing.expect(t, !missing_ok)
}

@(test)
test_replace_line_with_prefix :: proc(t: ^testing.T) {
	text := "a := 1\nb := 2\nc := 3\n"

	middle, ok := replace_line_with_prefix(text, "b := ", "b := 9")
	defer delete(middle)
	testing.expect(t, ok)
	testing.expect_value(t, middle, "a := 1\nb := 9\nc := 3\n")

	// A final line with no trailing newline must neither grow one nor lose the line.
	last, last_ok := replace_line_with_prefix("a := 1\nb := 2", "b := ", "b := 9")
	defer delete(last)
	testing.expect(t, last_ok)
	testing.expect_value(t, last, "a := 1\nb := 9")

	_, absent_ok := replace_line_with_prefix(text, "z := ", "z := 0")
	testing.expect(t, !absent_ok)
}

// Template paths always use forward slashes, but a path typed on a Windows command line may not, and
// a backslash is what tab completion produces there.
@(test)
test_same_path_accepts_either_separator :: proc(t: ^testing.T) {
	testing.expect(t, same_path(".just/toolchain.just", ".just\\toolchain.just"))
	testing.expect(t, same_path(".gitignore", ".gitignore"))
	testing.expect(t, !same_path(".gitignore", ".gitattributes"))
	testing.expect(t, !same_path(".just/editor.just", ".just/editor.jus"))
	testing.expect(t, syncable_path(".just\\toolchain.just"), "--only must accept a backslash path")
}

// Drives the two different error messages `sync` prints for a rejected `--only` path: a file that is
// deliberately not syncable needs a different answer from one that does not exist.
@(test)
test_template_path_distinguishes_unknown_from_unsyncable :: proc(t: ^testing.T) {
	testing.expect(t, template_path("justfile"), "justfile is a template, just not a syncable one")
	testing.expect(t, !template_path("no/such/file"))
}

/*
The marker file that identifies this repository must not itself be a template.

If it ever were embedded, every scaffolded project would receive it and every one of them would then be
refused a sync - the guard would have inverted, turning "never sync the template source" into "never
sync anything".
*/
@(test)
test_skel_source_marker_is_not_a_template :: proc(t: ^testing.T) {
	testing.expect(
		t,
		!template_path(SKEL_SOURCE_MARKER),
		"the marker must be skeleton-only, or the guard refuses every project instead of just this repo",
	)
	testing.expect(
		t,
		strings.has_prefix(SKEL_SOURCE_MARKER, "tools/"),
		"the marker has to sit under the prefix `_embed` excludes, or it would become a template",
	)
}

// The embedded copy of one template, for the tests that run the real thing through a transform. A
// missing path is a mistake in the test, not a condition to handle.
embedded_template :: proc(path: string) -> string {
	for tmpl in TEMPLATES {
		if tmpl.path == path {
			return tmpl.data
		}
	}
	return ""
}
