package skel

import "core:fmt"
import "core:strings"

// A tool the skeleton expects to find, and how badly it is needed.
//
// `required` tools make `doctor` exit non-zero: without them the core workflow does not run.
// Everything else is reported but tolerated, because only some recipes need it - a project that
// never runs `just format` does not need odinfmt installed.
Tool_Check :: struct {
	name:          string,
	probe_args:    []string,
	required:      bool,
	min_version:   [3]int, // {0,0,0} means "any version is fine"
	// Some tools have no version flag at all (odinfmt). For those we only care that the executable
	// exists, so the captured output is usage text and must not be shown as if it were a version.
	presence_only: bool,
	why:           string, // what breaks without it, shown only when it is missing
	install:       string,
}

CHECKS :: []Tool_Check {
	{
		name = "odin",
		probe_args = {"odin", "version"},
		required = true,
		why = "the compiler - nothing builds without it",
		install = "https://odin-lang.org/docs/install/",
	},
	{
		name = "just",
		probe_args = {"just", "--version"},
		required = true,
		// The skeleton's README states 1.32 as the floor; recipes use features from that era.
		min_version = {1, 32, 0},
		why = "runs every recipe in the justfile",
		install = "https://just.systems/",
	},
	{
		name = "odinfmt",
		// odinfmt has no version flag (`[path] [-config] [-stdin] [-w]`), so a bare invocation is
		// the probe: it prints usage and exits non-zero, which still proves it is installed.
		probe_args = {"odinfmt"},
		required = false,
		presence_only = true,
		why = "only `just format` needs it",
		install = "build from the ols repo: https://github.com/DanielGavin/ols",
	},
	{
		name = "git",
		probe_args = {"git", "--version"},
		required = false,
		why = "needed by `just new` and by update checks",
		install = "https://git-scm.com/downloads",
	},
}

/*
Report on the toolchain.

Exits non-zero when a required tool is missing or too old, so it is usable as a CI gate and as a
precondition for `new` later. Optional tools never affect the exit code.
*/
doctor :: proc() -> int {
	failures := 0

	for check in CHECKS {
		result := probe(check.probe_args)
		defer if result.found {
			delete(result.output)
		}

		label := check.required ? "required" : "optional"

		if !result.found {
			if check.required {
				failures += 1
				fmt.eprintfln("MISSING  %-8s (%s) - %s", check.name, label, check.why)
				fmt.eprintfln("         install: %s", check.install)
			} else {
				fmt.printfln("absent   %-8s (%s) - %s", check.name, label, check.why)
				fmt.printfln("         install: %s", check.install)
			}
			continue
		}

		if check.presence_only {
			fmt.printfln("ok       %-8s present", check.name)
			continue
		}

		banner := first_line(result.output)

		if check.min_version != {0, 0, 0} {
			major, minor, patch, ok := parse_version(banner)
			if !ok {
				// Present and runnable but unparseable: warn, do not fail. A version-banner change
				// upstream should not brick the tool.
				fmt.printfln("ok?      %-8s %s (could not parse a version)", check.name, banner)
				continue
			}
			req := check.min_version
			if !version_at_least(major, minor, patch, req[0], req[1], req[2]) {
				failures += 1
				fmt.eprintfln(
					"TOO OLD  %-8s %s - need >= %d.%d.%d",
					check.name,
					banner,
					req[0],
					req[1],
					req[2],
				)
				fmt.eprintfln("         install: %s", check.install)
				continue
			}
		}

		fmt.printfln("ok       %-8s %s", check.name, banner)
	}

	if failures > 0 {
		fmt.eprintfln("\n%d required tool(s) missing or too old", failures)
		return 1
	}
	fmt.println("\ntoolchain ok")
	return 0
}

// Version banners are sometimes multi-line; only the first line identifies the tool.
first_line :: proc(s: string) -> string {
	if i := strings.index_byte(s, '\n'); i >= 0 {
		return strings.trim_space(s[:i])
	}
	return s
}
