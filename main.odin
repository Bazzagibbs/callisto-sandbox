package callisto_sandbox

import "core:log"
import "core:time"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "core:os"
import cal "callisto"
import "callisto/input"
import cg "callisto/graphics"
import "callisto/config"
import "callisto/asset"
import "callisto/debug"

// Temp frame timer
frame_stopwatch: time.Stopwatch = {}
delta_time: f32 = {}
delta_time_f64: f64 = {}
// ================

engine: cal.Engine

main :: proc(){
    
    when ODIN_DEBUG {
        context.logger = debug.create_logger()
        defer debug.destroy_logger(context.logger)

        track := debug.create_tracking_allocator()
        context.allocator = mem.tracking_allocator(&track)
        defer debug.destroy_tracking_allocator(&track)
    }

    when config.DEBUG_PROFILER_ENABLED {
        debug.create_profiler()
        defer debug.destroy_profiler()
    }
    
    run_app()
}

run_app :: proc() -> (res: cg.Result) {
    debug.profile_scope()
  
    // Create engine
    // /////////////
    renderer_create_info := cal.Renderer_Create_Info {
        // resolution?
        // vsync?
        // anti-aliasing? 
        // these can be changed without rebuilding the entire renderer though
        // Maybe loaded from persistent user storage? Appdata, etc.
    }

    engine_create_info := cal.Engine_Create_Info {
        renderer_create_info = &renderer_create_info, // submit nil for headless?
        // tick callback proc pointer?
    }

    engine = cal.create(&engine_create_info) or_return
    defer cal.destroy(&engine)
    cal.run(&engine)
    // /////////////

    return .Ok
}

spin: f32

loop :: proc() {
    debug.profile_scope()
    
    // log.infof("{:2.6f} : {:i}fps", delta_time, int(1 / delta_time))
    // log.info(input.get_key(.Space))

}

