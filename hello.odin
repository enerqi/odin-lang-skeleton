package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:time"


main :: proc() {
    start_time := time.now()

    logger := log.create_console_logger(lowest=.Info)
    defer log.destroy_console_logger(logger)
    context.logger = logger
    defer {
        run_time := time.since(start_time)
        log.debug("program duration: ", run_time)
    }

    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, context.allocator)
    defer mem.tracking_allocator_destroy(&tracking_allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)
    defer if len(tracking_allocator.allocation_map) > 0 || len(tracking_allocator.bad_free_array) > 0 {
        for _, v in tracking_allocator.allocation_map {
            log.errorf("Memory Leak:\t%v", v)
        }
        for bad_free in tracking_allocator.bad_free_array {
            log.errorf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
        }
    }

    fmt.println("hello world")
}
