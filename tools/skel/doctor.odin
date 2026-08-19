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
	// A fact about the tool's role, shown whether or not it was found. `why` cannot carry these: a
	// bare `ok hyperfine 1.20.0` answers "is it installed" but not "does this toolchain need it",
	// and for odinfmt the answer is no either way.
	note:          string,
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
		name        = "just",
		probe_args  = {"just", "--version"},
		required    = true,
		// Must match the justfile's own `set minimum-version`, which is the real gate - it fires on
		// every `just` invocation, while this only fires when someone runs `doctor`. The duplication
		// buys a better first-run experience: doctor names the tool, why it is needed and where to get
		// it, alongside the odin/git/odinfmt checks, rather than erroring at a justfile line.
		//
		// The floor is set by the newest just feature the justfile uses - currently user-defined
		// functions (1.49), for `target_path`. Raise all three (here, the justfile, the README)
		// together when a recipe adopts something newer.
		min_version = {1, 49, 0},
		why         = "runs every recipe in the justfile",
		install     = "https://just.systems/",
	},
	{
		name          = "odinfmt",
		// odinfmt has no version flag (`[path] [-config] [-stdin] [-w]`), so a bare invocation is
		// the probe: it prints usage and exits non-zero, which still proves it is installed.
		//
		// Probes PATH, which is NOT what `just format` runs - see `note`, and the justfile's `ols_tag`.
		// Reported anyway: a PATH copy is what an editor or a hand-run `odinfmt` picks up, and knowing a
		// second formatter sits in front of the pinned one beats a silent pass.
		probe_args    = {"odinfmt"},
		required      = false,
		presence_only = true,
		note          = "`just format` fetches and runs its own pinned copy either way; PATH matters only for a hand-run odinfmt",
		install       = "`just fetch-ols` (or build from the ols repo: https://github.com/DanielGavin/ols)",
	},
	{
		name = "git",
		probe_args = {"git", "--version"},
		required = false,
		why = "needed by `just new` and by update checks",
		install = "https://git-scm.com/downloads",
	},
	{
		name       = "uv",
		probe_args = {"uv", "--version"},
		required   = false,
		// `install-sublime`, `sublime-build-init` and `ols-config` are `[script]` recipes that run on
		// `uv run -p 3.14 python` (see the justfile's `set script-interpreter`) rather than a bare
		// `python`, so a version-pinned interpreter downloads itself instead of depending on whatever
		// `python` happens to resolve to on the machine (unpinned on scoop, distro-versioned on Linux).
		// Deliberately not a recipe list: this one binary scaffolds both project kinds, and the
		// `[script]` recipes differ between them - `examples` exists only in a library, the editor-setup
		// ones in both.
		why        = "runs the justfile's `[script]` recipes - `fetch-ols`, which `just format` depends on, editor setup everywhere, `examples` in a library - without a system python",
		install    = "https://docs.astral.sh/uv/getting-started/installation/",
	},
	{
		name = "hyperfine",
		probe_args = {"hyperfine", "--version"},
		required = false,
		note = "only `just time_release` / `just time_profiles` need it - whole-process timings",
		install = "https://github.com/sharkdp/hyperfine#installation",
	},
	{
		name       = "valgrind",
		probe_args = {"valgrind", "--version"},
		required   = false,
		// Listed even though most projects never add the bench feature: it is the one tool here whose
		// absence is not obvious from the error. `just bench_count` fails at the point of use with a
		// message naming it, and doctor is where somebody looks before that happens. Not available on
		// Windows at all, which the report says rather than making it look installable.
		why        = "only `just bench_count` needs it (the bench feature; not available on Windows)",
		install    = "apt install valgrind / brew install valgrind",
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
		note := check.note == "" ? "" : fmt.tprintf(" - %s", check.note)
		// `(optional)` on a tool that WAS found, too. This report exists to say what the toolchain
		// needs, and a line that only ever reads `ok` cannot answer "can I ignore this one".
		tail := check.required ? note : fmt.tprintf(" (%s)%s", label, note)

		if !result.found {
			reason := check.why == "" ? "" : fmt.tprintf(" - %s", check.why)
			if check.required {
				failures += 1
				fmt.eprintfln("MISSING  %-9s (%s)%s%s", check.name, label, reason, note)
				fmt.eprintfln("         install: %s", check.install)
			} else {
				fmt.printfln("absent   %-9s (%s)%s%s", check.name, label, reason, note)
				fmt.printfln("         install: %s", check.install)
			}
			continue
		}

		if check.presence_only {
			fmt.printfln("ok       %-9s present%s", check.name, tail)
			continue
		}

		banner := first_line(result.output)

		if check.min_version != {0, 0, 0} {
			major, minor, patch, ok := parse_version(banner)
			if !ok {
				// Present and runnable but unparseable: warn, do not fail. A version-banner change
				// upstream should not brick the tool.
				fmt.printfln("ok?      %-9s %s (could not parse a version)%s", check.name, banner, tail)
				continue
			}
			req := check.min_version
			if !version_at_least(major, minor, patch, req[0], req[1], req[2]) {
				failures += 1
				fmt.eprintfln("TOO OLD  %-9s %s - need >= %d.%d.%d", check.name, banner, req[0], req[1], req[2])
				fmt.eprintfln("         install: %s", check.install)
				continue
			}
		}

		fmt.printfln("ok       %-9s %s%s", check.name, banner, tail)
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
