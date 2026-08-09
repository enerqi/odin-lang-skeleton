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
	got := strip_marked_blocks(input, drop_names(.Exe))
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
	got := strip_marked_blocks(input, drop_names(.Exe))
	defer delete(got)

	testing.expect(t, strings.contains(got, "kept_recipe:"), "body of a non-skeleton block was dropped")
	testing.expect(t, !strings.contains(got, "snippet-exclude"), "marker line survived")
}

@(test)
test_strip_normalises_trailing_newline :: proc(t: ^testing.T) {
	got := strip_marked_blocks("a:\n\techo a\n\n\n\n", drop_names(.Exe))
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

	got := strip_marked_blocks(source, drop_names(.Exe))
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

	got := strip_marked_blocks(source, drop_names(.Exe))
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

	stripped := strip_marked_blocks(source, drop_names(.Exe))
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

	stripped := strip_marked_blocks(source, drop_names(.Exe))
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
	// The example lines in that comment are themselves kind-specific, so this is the exe spelling -
	// `stripped` above was produced with the exe drop set.
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

// The drop set is what tells the two project kinds apart, and it is reached through `drop_names`
// rather than a constant at every call site, so that indirection is what has to be right.
@(test)
test_drop_names_per_kind :: proc(t: ^testing.T) {
	exe := drop_names(.Exe)
	testing.expect(t, name_in(exe, "skeleton-only"), "exe must drop skeleton-only")
	testing.expect(t, name_in(exe, "lib-only"), "exe must drop lib-only")
	testing.expect(t, !name_in(exe, "exe-only"), "exe must keep its own recipes")

	lib := drop_names(.Lib)
	testing.expect(t, name_in(lib, "skeleton-only"), "lib must drop skeleton-only")
	testing.expect(t, name_in(lib, "exe-only"), "lib must drop exe-only")
	testing.expect(t, !name_in(lib, "lib-only"), "lib must keep its own recipes")
}

// Each kind keeps its own block and drops the other's, and a block named by neither keeps its body.
@(test)
test_strip_is_per_kind :: proc(t: ^testing.T) {
	input := `shared:
	echo shared

# >>> exe-only
run:
	echo run
# <<< exe-only

# >>> lib-only
check:
	echo check
# <<< lib-only
`
	for_exe := strip_marked_blocks(input, drop_names(.Exe))
	defer delete(for_exe)
	testing.expect(t, strings.contains(for_exe, "shared:"))
	testing.expect(t, strings.contains(for_exe, "echo run"), "exe-only body was dropped from an exe project")
	testing.expect(t, !strings.contains(for_exe, "echo check"), "lib-only body leaked into an exe project")

	for_lib := strip_marked_blocks(input, drop_names(.Lib))
	defer delete(for_lib)
	testing.expect(t, strings.contains(for_lib, "shared:"))
	testing.expect(t, strings.contains(for_lib, "echo check"), "lib-only body was dropped from a lib project")
	testing.expect(t, !strings.contains(for_lib, "echo run"), "exe-only body leaked into a lib project")
	testing.expect(t, !strings.contains(for_lib, ">>>"), "a marker line leaked")
}

/*
Every `>>> name` in an embedded template must have a matching `<<< name`.

`strip_marked_blocks` has no runtime guard for this, unlike its Python twin in the justfile, and that is
deliberate: the templates are `#load`ed at compile time, so a balanced file stays balanced for the life
of the binary. Checking here catches it before release instead of letting `odin-skel new` truncate a
generated justfile from the missing marker onwards and still report `created N files` with exit 0.

Blocks do not nest, so a simple open/close pairing is the whole contract.
*/
@(test)
test_embedded_templates_have_balanced_markers :: proc(t: ^testing.T) {
	for tmpl in TEMPLATES {
		open := ""
		line_no := 0
		rest := tmpl.data
		for len(rest) > 0 {
			line: string
			if i := strings.index_byte(rest, '\n'); i >= 0 {
				line, rest = rest[:i], rest[i + 1:]
			} else {
				line, rest = rest, ""
			}
			line_no += 1

			marker := marker_text(strings.trim_space(line))
			switch {
			case strings.has_prefix(marker, ">>> "):
				testing.expectf(
					t,
					open == "",
					"%s:%d: `%s` opens while `>>> %s` is still open",
					tmpl.path,
					line_no,
					marker,
					open,
				)
				open = marker[4:]
			case strings.has_prefix(marker, "<<< "):
				testing.expectf(
					t,
					open == marker[4:],
					"%s:%d: `%s` closes a block that is not open (open: %q)",
					tmpl.path,
					line_no,
					marker,
					open,
				)
				open = ""
			}
		}
		testing.expectf(t, open == "", "%s: `>>> %s` is never closed", tmpl.path, open)
	}
}

@(test)
test_marker_spellings :: proc(t: ^testing.T) {
	for line in ([]string{"# >>> exe-only", "<!-- >>> exe-only -->"}) {
		testing.expectf(t, marker_text(line) == ">>> exe-only", "%q was not recognised as a marker", line)
	}
	// Not markers: a shebang, a `//` comment and ordinary prose all read as empty. The `//` case
	// matters - the `.sublime-build` files are full of them and are deliberately never stripped.
	for line in ([]string{"#!/bin/sh", "// >>> exe-only", "just some text", "#"}) {
		testing.expectf(t, marker_text(line) == "", "%q was mistaken for a marker", line)
	}
}

/*
The Sublime build systems must reach both project kinds intact.

`just install-sublime` copies them into Sublime's global `Packages/User`, where they match on
`source.odin` and drive every Odin project on the machine - so a copy specialised to the project it
was scaffolded from would take the other kind's build variants away everywhere. Scaffolding therefore
does not strip them, and they list both kinds' recipes.
*/
@(test)
test_sublime_build_serves_both_kinds :: proc(t: ^testing.T) {
	source := ""
	for tmpl in TEMPLATES {
		if tmpl.path == ".sublime/OdinJustTarget.sublime-build" {
			source = tmpl.data
			break
		}
	}
	testing.expect(t, source != "", "OdinJustTarget.sublime-build missing from TEMPLATES - run `just embed`")

	// Matched on the variant names: the `shell_cmd` values carry JSON-escaped quotes, and `run` is a
	// prefix of `run_release`.
	for wanted in ([]string{
			"project - just run (debug)",
			"project - just run_release\"",
			"project - just sanitize",
			"project - just diagnose",
			"project - just check",
			"project - just doc",
			"project - just examples",
			"project - just test\"",
			"project - just test_sanitize",
		}) {
		testing.expectf(t, strings.contains(source, wanted), "%q is missing from the build system", wanted)
	}
	// Kind markers here would be silently inert, because `marker_text` does not recognise the `//`
	// spelling and nothing strips this file anyway. That is a worse failure than a leak - it looks like
	// it works - so assert that nobody has added them expecting otherwise.
	testing.expect(
		t,
		!strings.contains(source, ">>> exe-only") && !strings.contains(source, ">>> lib-only"),
		"this file is never stripped, so kind markers in it would do nothing",
	)
}

// The case the end-to-end scaffold exercises: the real justfile, stripped for a library. The exe
// build tiers have to go, the shared recipes have to stay, and the skeleton's own recipes must not
// survive in either kind.
@(test)
test_strip_real_justfile_for_lib :: proc(t: ^testing.T) {
	source := ""
	for tmpl in TEMPLATES {
		if tmpl.path == "justfile" {
			source = tmpl.data
			break
		}
	}
	testing.expect(t, source != "", "justfile missing from TEMPLATES - run `just embed`")

	got := strip_marked_blocks(source, drop_names(.Lib))
	defer delete(got)

	// Matched as recipe or assignment headers, not as bare words: `test_main_name` contains
	// `main_name`, and the shared `mktarget_dirs` comment mentions the build recipes by name.
	for gone in ([]string{"\nrun_debug *args:", "\nrerun_debug *args:", "\ndiagnose *args:", "\nmain_name :=", "\nbuild_skel *args:", "\n_embed mode:"}) {
		testing.expectf(t, !strings.contains(got, gone), "%q survived into a library justfile", gone)
	}
	for kept in ([]string{"\ncheck *args:", "\nexample name", "\ndoc *args:", "\ntest *args:", "mktarget_dirs"}) {
		testing.expectf(t, strings.contains(got, kept), "library recipe %q was stripped", kept)
	}
}

@(test)
test_odin_package_name :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		want:  string,
		ok:    bool,
	}
	cases := []Case {
		{"mylib", "mylib", true},
		{"odin-toml", "odin_toml", true},
		{"my lib", "my_lib", true},
		{"a.b.c", "a_b_c", true},
		{"already_fine", "already_fine", true},
		{"Mixed-Case", "Mixed_Case", true},
		{"lib2", "lib2", true},
		// Not repairable by substitution.
		{"", "", false},
		{"2d-math", "", false},
		{"package", "", false},
		{"map", "", false},
		{"-", "", false},
		{"weird!name", "", false},
		// Not an Odin keyword, but unusable here: the examples are `package main` and import the
		// library, and two packages of the same name in one build is a compile error. Rejecting it at
		// scaffold time is the difference between a clear message and `just example` failing later.
		{"main", "", false},
		// Byte-wise validation, so non-ASCII is rejected - the message has to say that rather than
		// claim `é` is not a letter.
		{"café", "", false},
		// Odin refuses a source file whose name starts with `_`, and the file is named after the
		// package. `.mylib` reaches the same place, since a leading separator becomes an underscore.
		{"_internal", "", false},
		{".mylib", "", false},
		// The file would be `<name>.odin`, whose trailing target name Odin reads as a build tag - the
		// package would then compile on that one target and be invisible everywhere else.
		{"odin-js", "", false},
		{"thing_amd64", "", false},
		{"_js", "", false},
		// ... but only at an underscore boundary: these merely end in the same letters.
		{"odinjs", "odinjs", true},
		{"jsonwasm32", "jsonwasm32", true},
	}
	for c in cases {
		got, reason, ok := odin_package_name(c.input)
		defer if ok {
			delete(got)
		}
		testing.expectf(t, ok == c.ok, "%q: expected ok=%v, got %v (%s)", c.input, c.ok, ok, reason)
		if ok && c.ok {
			testing.expectf(t, got == c.want, "%q: expected %q, got %q", c.input, c.want, got)
		}
		if !ok {
			testing.expectf(t, reason != "", "%q was rejected without a reason", c.input)
		}
	}
}

// The lib template's directory prefix comes off and the placeholder package name in the base name is
// replaced; anything below the template root keeps its own name.
@(test)
test_lib_out_path :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		want:  string,
	}
	cases := []Case {
		{"mylib/mylib.odin", "toml.odin"},
		{"mylib/mylib_test.odin", "toml_test.odin"},
		{"mylib/examples/basic.odin", "examples/basic.odin"},
	}
	for c in cases {
		got, ok := lib_out_path(c.input, "toml")
		defer if ok {
			delete(got)
		}
		testing.expectf(t, ok, "%q was rejected", c.input)
		testing.expectf(t, got == c.want, "%q: expected %q, got %q", c.input, c.want, got)
	}

	// A path outside the template directory means the embed list and this rule have drifted.
	_, ok := lib_out_path("main.odin", "toml")
	testing.expect(t, !ok, "a non-template path should be rejected")
}

@(test)
test_rewrite_package_clause :: proc(t: ^testing.T) {
	// The template's own doc comment discusses package names at length, so prose that merely contains
	// the word - including a line that starts with it - must be left alone.
	input := `/*
Rename the directory, this file and the
package clause together. odin-mylib is a directory, package mylib is the clause.
*/
package mylib

add :: proc() {}
`
	got, ok := rewrite_package_clause(input, "toml")
	defer if ok {
		delete(got)
	}
	testing.expect(t, ok)
	testing.expect(t, strings.contains(got, "\npackage toml\n"), "the clause was not rewritten")
	testing.expect(t, !strings.contains(got, "\npackage mylib\n"), "the old clause survived")
	testing.expect(t, strings.contains(got, "package clause together"), "prose was rewritten")
	testing.expect(t, strings.contains(got, "package mylib is the clause"), "prose was rewritten")

	// `package main` examples are never passed through this, and a template that lost its clause is
	// drift worth failing on rather than skipping.
	_, missing_ok := rewrite_package_clause("package main\n", "toml")
	testing.expect(t, !missing_ok, "a missing clause must be reported")
}

// The two kinds must actually be represented in the embed list, or `--lib` would scaffold a project
// with no package in it and `new` would still report success.
@(test)
test_templates_carry_both_kinds :: proc(t: ^testing.T) {
	lib_files, exe_files := 0, 0
	for tmpl in TEMPLATES {
		switch tmpl.kind {
		case .Lib:
			lib_files += 1
			testing.expectf(
				t,
				strings.has_prefix(tmpl.path, LIB_TEMPLATE_DIR + "/"),
				"%q is kind .Lib but is not under %q",
				tmpl.path,
				LIB_TEMPLATE_DIR,
			)
		case .Exe:
			exe_files += 1
		case .Both:
		}
	}
	testing.expect(t, lib_files > 0, "no lib template files embedded - run `just embed`")
	testing.expect(t, exe_files > 0, "no exe-only template files embedded - run `just embed`")
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
	got := strip_marked_blocks(input, drop_names(.Exe))
	defer delete(got)

	testing.expect(t, strings.contains(got, "keep this"))
	testing.expect(t, strings.contains(got, "keep this too"))
	testing.expect(t, !strings.contains(got, "drop this"), "skeleton-only markdown survived")
	testing.expect(t, !strings.contains(got, "skeleton-only"), "marker line survived")
}

// A `#` heading must not be mistaken for a marker comment now that markdown is stripped too.
@(test)
test_strip_keeps_markdown_headings :: proc(t: ^testing.T) {
	got := strip_marked_blocks("# Title\n\n## Section\n\ntext\n", drop_names(.Exe))
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

	got := strip_marked_blocks(source, drop_names(.Exe))
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
