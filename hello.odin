package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:sync"
import "core:time"


main_program :: proc() {
	fmt.println("Hello")
}


main :: proc() { 	// Operational setup before calling `main_program`

	// (1) program duration tracking
	when TIME_PROGRAM_DURATION_ENABLE {
		start_time := time.now()
	}
	// (2) Global allocator change
	when MIMALLOC_ENABLE {
		context.allocator = mi.global_allocator()
	}
	// (3) Profiler setup
	when SPALL_ENABLE {
		spall_profiler_setup()
		defer spall_profiler_destroy()
	}
	spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)
	// (4) Back trace improvements
	when BACKTRACE_ENABLE {
		context.assertion_failure_proc = back.assertion_failure_proc
		back.register_segfault_handler()
	}
	// (5) Memory tracking allocator to debug leaks and bad frees (double frees)
	when TRACKING_ALLOCATOR_ENABLE {
		alloc_interface, tracking_allocator := make_tracking_allocator_context()
		context.allocator = alloc_interface
		defer tracking_allocator_finalise(tracking_allocator)
	}
	// (6) Logger setup to stdout
	context.logger = make_logging_context()
	defer destroy_logging_context()
	// (7) Time program duration on shutdown
	when TIME_PROGRAM_DURATION_ENABLE {
		defer log_program_duration(start_time)
	}

	main_program()
}


/*
___________________________________________________________________________________________________________________
	Operational Setup - profiling, logging, telemetry etc. (not program semantics related)

	- Build with `-define:SPALL_ENABLE=true` option to emit a spall profiling `trace.spall` file (adds 2+ seconds)
		* https://github.com/colrdavidson/spall-web
	- Build with `-define:MIMALLOC_ENABLE=true` and provide a `mi` mimalloc import to override the global allocator
		* https://github.com/jakubtomsu/odin-mimalloc
	- Build with `-define:BACKTRACE_ENABLE=true` and provide a back import path to improve backtraces
		* https://github.com/laytan/back
	- Build with `-define:TIME_PROGRAM_DURATION_ENABLE=true` to turn on the program duration logging
	- Build with `-define:TRACKING_ALLOCATOR_ENABLE=false` to turn off the memory tracking and reporting
___________________________________________________________________________________________________________________
*/
TIME_PROGRAM_DURATION_ENABLE :: #config(TIME_PROGRAM_DURATION_ENABLE, false)
MIMALLOC_ENABLE :: #config(MIMALLOC_ENABLE, false)
SPALL_ENABLE :: #config(SPALL_ENABLE, false)
BACKTRACE_ENABLE :: #config(BACKTRACE_ENABLE, false)
TRACKING_ALLOCATOR_ENABLE :: #config(TRACKING_ALLOCATOR_ENABLE, true)

import "core:debug/trace"
import spall "core:prof/spall"
// import mi "../odin-mimalloc/mimalloc"
// import back "../back"


// Profiling global / thread local data
global_spall_ctx: spall.Context
@(thread_local)
g_spall_buffer: spall.Buffer

@(cold)
spall_profiler_setup :: proc() {
	global_spall_ctx = spall.context_create("trace.spall") // global
	buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
	g_spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
}
@(cold)
spall_profiler_destroy :: proc() {
	spall.buffer_destroy(&global_spall_ctx, &g_spall_buffer)
	spall.context_destroy(&global_spall_ctx)
}

when TRACKING_ALLOCATOR_ENABLE && !BACKTRACE_ENABLE {
	@(cold)
	@(require_results)
	make_tracking_allocator_context :: proc(
		allocator := context.allocator,
		loc := #caller_location,
	) -> (
		mem.Allocator,
		^mem.Tracking_Allocator,
	) {
		spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)
		tracking_allocator := new(mem.Tracking_Allocator, allocator = allocator, loc = loc)
		mem.tracking_allocator_init(tracking_allocator, context.allocator)
		return mem.tracking_allocator(tracking_allocator), tracking_allocator
	}

	@(cold)
	tracking_allocator_finalise :: proc(tracking_allocator: ^mem.Tracking_Allocator) {
		spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)

		if len(tracking_allocator.allocation_map) > 0 || len(tracking_allocator.bad_free_array) > 0 {
			for _, v in tracking_allocator.allocation_map {
				log.errorf("Memory Leak:\t%v", v)
			}
			for bad_free in tracking_allocator.bad_free_array {
				log.errorf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
			}
		}

		mem.tracking_allocator_destroy(tracking_allocator)
	}
} else when TRACKING_ALLOCATOR_ENABLE && BACKTRACE_ENABLE {
	@(cold)
	@(require_results)
	make_tracking_allocator_context :: proc(
		allocator := context.allocator,
		loc := #caller_location,
	) -> (
		mem.Allocator,
		^back.Tracking_Allocator,
	) {
		spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)
		tracking_allocator := new(back.Tracking_Allocator, allocator = allocator, loc = loc)
		back.tracking_allocator_init(tracking_allocator, context.allocator)
		return back.tracking_allocator(tracking_allocator), tracking_allocator
	}

	@(cold)
	tracking_allocator_finalise :: proc(tracking_allocator: ^back.Tracking_Allocator) {
		spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)
		back.tracking_allocator_print_results(&track)
		back.tracking_allocator_destroy(tracking_allocator)
	}
}

@(cold)
@(require_results)
make_logging_context :: proc() -> log.Logger {
	spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)
	return log.create_console_logger(lowest = .Info)
}

@(cold)
destroy_logging_context :: proc() {
	spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)
	log.destroy_console_logger(context.logger)
}

@(cold)
log_program_duration :: proc(start_time: time.Time) {
	spall.SCOPED_EVENT(&global_spall_ctx, &g_spall_buffer, #procedure)
	run_time := time.since(start_time)
	log.info("Program duration before any profiler or memory tracking shutdown:", run_time)
}
