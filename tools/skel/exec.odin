package skel

import "core:os"
import "core:strings"

// Result of probing an external tool. `found` distinguishes "not on PATH" from "ran but failed",
// because those need different advice: install it, versus something is wrong with the install.
Probe :: struct {
	found:     bool,
	exit_code: int,
	output:    string, // stdout and stderr joined and trimmed; empty when the tool was not found
}

/*
Run `command` and capture its output.

Odin's core has no TLS and no shell, so every external interaction in this tool goes through here.
Both streams are captured because version banners are inconsistent about which one they use - `odin
version` writes to stdout, some tools write to stderr - and for a probe we only care that a version
string came back at all. A command that *failed* is the other case: it has usually written a progress
line to stdout and the reason to stderr, so for a non-zero exit both are returned rather than the first
non-empty one. Preferring stdout there loses the only thing worth reporting.

`working_dir` runs the command somewhere else, which `new` needs: the recipes it calls belong to the
project it has just written, not to whatever directory odin-skel was invoked from. Empty means "here".

The caller owns the returned `output`.
*/
probe :: proc(command: []string, working_dir := "", allocator := context.allocator) -> Probe {
	state, out, errout, err := os.process_exec({command = command, working_dir = working_dir}, allocator)
	defer delete(out, allocator)
	defer delete(errout, allocator)

	if err != nil {
		// Could not be spawned at all: not on PATH, or not executable.
		return Probe{found = false}
	}

	text := strings.trim_space(string(out))
	problem := strings.trim_space(string(errout))
	switch {
	case problem == "":
	case text == "":
		text = problem
	case state.exit_code != 0:
		joined := strings.concatenate({text, "\n", problem}, allocator)
		return Probe{found = true, exit_code = state.exit_code, output = joined}
	}

	return Probe{found = true, exit_code = state.exit_code, output = strings.clone(text, allocator)}
}

/*
Parse a leading `major.minor.patch` out of a version banner.

Deliberately lenient: it scans for the first digit and reads as far as it can, so it copes with
`just 1.46.0`, `odinfmt 0.1.0` and a bare `1.46.0` alike. Missing components read as 0, so "1.32"
compares equal to "1.32.0".

Returns ok=false when there is no digit at all to work with.
*/
parse_version :: proc(banner: string) -> (major, minor, patch: int, ok: bool) {
	start := -1
	for r, i in banner {
		if r >= '0' && r <= '9' {
			start = i
			break
		}
	}
	if start < 0 {
		return 0, 0, 0, false
	}

	part, component := 0, 0
	seen_digit := false
	for i := start; i < len(banner); i += 1 {
		c := banner[i]
		switch {
		case c >= '0' && c <= '9':
			component = component * 10 + int(c - '0')
			seen_digit = true
		case c == '.' && seen_digit && part < 2:
			switch part {
			case 0:
				major = component
			case 1:
				minor = component
			}
			part += 1
			component = 0
		case:
			// Anything else ends the version: `1.46.0-rc1`, `dev-2026-07-nightly`, trailing spaces.
			i = len(banner)
		}
	}
	switch part {
	case 0:
		major = component
	case 1:
		minor = component
	case 2:
		patch = component
	}

	return major, minor, patch, seen_digit
}

// Reports whether the version is at least the required one. Ordering only; no opinion on what the
// numbers mean.
version_at_least :: proc(major, minor, patch: int, req_major, req_minor, req_patch: int) -> bool {
	if major != req_major {
		return major > req_major
	}
	if minor != req_minor {
		return minor > req_minor
	}
	return patch >= req_patch
}
