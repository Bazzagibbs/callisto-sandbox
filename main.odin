package callisto_sandbox

import "base:runtime"
import "core:log"
import "core:time"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "core:os"
import "core:fmt"
import cal "callisto"

Game_Memory :: struct {
        profiler: cal.Profiler,
        engine: cal.Engine,
        window: cal.Window,
        frame_count: int,
}

// ==================================
// Implement these in every project

@(export)
callisto_callbacks :: proc() -> cal.Callbacks {
        return cal.Callbacks {
                memory_manager         = memory_manager,
                init                   = init,
                loop                   = loop,
                shutdown               = shutdown,
        }
}


// Entry point for standalone build. Not used in hot-reload builds.
when ODIN_BUILD_MODE == .Executable {
        main :: proc() {
                cal.run_main(callisto_callbacks())
        }
}

// ==================================

memory_manager :: proc(mem_command: cal.Memory_Command, game_mem: ^rawptr) {
        switch mem_command {
        case .Allocate:
                game_mem^ = new(Game_Memory)
        case .Reset:
                // modify the existing allocation and return it...
                temp_mem := (^Game_Memory)(game_mem^)
                temp_mem.frame_count = 0
                // or free and allocate
                // free(game_mem^)
                // game_mem^ = new(Game_Memory)
        case .Free:
                free(game_mem^)
        }
}

init :: proc(game_mem_raw: rawptr) {
        g := (^Game_Memory)(game_mem_raw)
        g.frame_count = 0
        cal.profiler_init(&g.profiler)
        cal.init(&g.engine)

        window_create_info := cal.Window_Create_Info {
                name     = "Callisto Sandbox",
                style    = cal.window_style_default(),
                position = nil,
                size     = nil,
                
        }
        cal.window_create(&g.engine, &window_create_info, &g.window)
}


loop :: proc(game_mem_raw: rawptr) -> cal.Loop_Result {
        g := (^Game_Memory)(game_mem_raw)
        cal.profile_scope(&g.profiler)

        cal.poll_input(g.window)
        // poll_input()
        // simulate()
        // draw()


        // Change this to test hot reloading
        if g.frame_count % 60 == 0 {
                log.info(g.frame_count)
        }

        g.frame_count += 1
        time.accurate_sleep(time.Second / 240)

        if g.frame_count >= 3000 {
                log.info("Exiting at frame", g.frame_count)
                return .Shutdown
        }

        // Can shut down or reset game by returning .Shutdown, .Reset_Soft, .Reset_Hard
        return .Ok
}


shutdown :: proc(game_mem_raw: rawptr) {
        g := (^Game_Memory)(game_mem_raw)
        cal.destroy(&g.engine)
        cal.profiler_destroy(&g.profiler)
}

// ==================================


