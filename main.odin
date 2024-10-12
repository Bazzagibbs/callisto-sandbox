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
        frame_count: int,
}

g_mem: ^Game_Memory // global pointer to game memory, managed by Runner executable

@(export)
callisto_runner_callbacks :: proc() -> cal.Runner_Callbacks {
        return cal.Runner_Callbacks {
                memory_init     = cal_memory_init,
                memory_load     = cal_memory_load,
                memory_reset    = cal_memory_reset,
                memory_shutdown = cal_memory_shutdown,
                game_init       = cal_game_init,
                game_render     = cal_game_render,
        }
}

// ==================================

cal_memory_init :: proc() -> (game_mem: rawptr, ctx: runtime.Context) {
        g_mem = new(Game_Memory)
        return g_mem, {}
}

cal_memory_load :: proc(game_mem: rawptr) {
        g_mem = (^Game_Memory)(game_mem)
}

cal_memory_reset :: proc(old_mem: rawptr) -> (new_mem: rawptr) {
        // modify the existing allocation and return it...
        temp_mem := (^Game_Memory)(old_mem)
        temp_mem.frame_count = 0
        return temp_mem

        // ... or keep only the persistent data and alloc new memory
        // renderer_temp := old_mem.renderer
        // free(old_mem)
        // new_mem = new(Game_Memory)
        // new_mem.renderer = renderer_temp
        // return new_mem
}

cal_memory_shutdown :: proc(game_mem: rawptr) {
        free(game_mem)
}

cal_game_init :: proc() {
        // load_level()
        // spawn_player()
}

cal_game_render :: proc() -> cal.Runner_Control {
        // poll_input()
        // simulate()
        // draw()

        // Change this to test hot reloading
        if g_mem.frame_count % 60 == 0 {
                fmt.println(g_mem.frame_count)
        }

        g_mem.frame_count += 1
        time.accurate_sleep(time.Second / 240)


        // Can shut down or reset game by returning .Shutdown, .Reset_Soft, .Reset_Hard
        return .Ok
}

// ==================================


