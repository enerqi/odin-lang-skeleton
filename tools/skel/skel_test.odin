package skel

import "core:slice"
import "core:testing"

@(test)
test_parse_version_plain :: proc(t: ^testing.T) {
	major, minor, patch, ok := parse_version("just 1.46.0")
	testing.expect(t, ok)
	testing.expect_value(t, major, 1)
	testing.expect_value(t, minor, 46)
	testing.expect_value(t, patch, 0)
}

@(test)
test_parse_version_bare :: proc(t: ^testing.T) {
	major, minor, patch, ok := parse_version("1.32.5")
	testing.expect(t, ok)
	testing.expect_value(t, major, 1)
	testing.expect_value(t, minor, 32)
	testing.expect_value(t, patch, 5)
}

// A two-component version must read as x.y.0 so that "1.32" and "1.32.0" compare equal.
@(test)
test_parse_version_two_components :: proc(t: ^testing.T) {
	major, minor, patch, ok := parse_version("just 1.32")
	testing.expect(t, ok)
	testing.expect_value(t, major, 1)
	testing.expect_value(t, minor, 32)
	testing.expect_value(t, patch, 0)
}

// Suffixes must terminate the version rather than being folded into the patch number.
@(test)
test_parse_version_suffix :: proc(t: ^testing.T) {
	major, minor, patch, ok := parse_version("just 1.46.0-rc1")
	testing.expect(t, ok)
	testing.expect_value(t, major, 1)
	testing.expect_value(t, minor, 46)
	testing.expect_value(t, patch, 0)
}

// The Odin compiler reports a date-stamped nightly, not a semver. It must parse without crashing;
// the numbers are meaningless, which is why `odin` carries no min_version.
@(test)
test_parse_version_odin_nightly :: proc(t: ^testing.T) {
	_, _, _, ok := parse_version("odin version dev-2026-07-nightly:819fdc7")
	testing.expect(t, ok, "a digit is present, so parsing should succeed")
}

@(test)
test_parse_version_no_digits :: proc(t: ^testing.T) {
	_, _, _, ok := parse_version("command not found")
	testing.expect(t, !ok)
}

@(test)
test_version_at_least :: proc(t: ^testing.T) {
	testing.expect(t, version_at_least(1, 46, 0, 1, 32, 0), "1.46.0 satisfies 1.32.0")
	testing.expect(t, version_at_least(1, 32, 0, 1, 32, 0), "equal satisfies")
	testing.expect(t, !version_at_least(1, 31, 9, 1, 32, 0), "1.31.9 falls short of 1.32.0")
	testing.expect(t, !version_at_least(0, 99, 0, 1, 0, 0), "major dominates minor")
	testing.expect(t, version_at_least(2, 0, 0, 1, 32, 0), "a newer major satisfies")
}

// A command that does not exist must report found=false rather than a zero exit code, because
// doctor uses that flag to tell "install it" apart from "it is broken".
@(test)
test_probe_missing_command :: proc(t: ^testing.T) {
	result := probe({"odin-skel-definitely-not-a-real-binary"})
	testing.expect(t, !result.found)
}

@(test)
test_probe_finds_odin :: proc(t: ^testing.T) {
	result := probe({"odin", "version"})
	defer if result.found {
		delete(result.output)
	}
	testing.expect(t, result.found, "odin must be on PATH for the rest of the suite to mean anything")
	testing.expect(t, len(result.output) > 0, "a version banner should have been captured")
}

// The loop guard from tools/DESIGN.md: every command main.odin dispatches on must appear in
// OWNED_COMMANDS, or the future passthrough will forward it to `just` and bounce back.
@(test)
test_owned_commands_cover_dispatch :: proc(t: ^testing.T) {
	owned := OWNED_COMMANDS
	for name in ([]string{"version", "doctor", "help"}) {
		testing.expect(t, slice.contains(owned, name), "dispatched command missing from OWNED_COMMANDS")
	}
}
