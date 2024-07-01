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

vec4 :: cal.vec4

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
    app_desc := cal.Application_Description {
        name = "Callisto Sandbox",
        company = "BazzaGibbs",
        version = {0, 0, 1},
    }

    display_desc := cal.Display_Description {
        vsync         = .Triple_Buffer,
        fullscreen    = .Windowed,
        window_extent = {1024, 768},
    }

    renderer_desc := cal.Renderer_Description {}

    engine_desc := cal.Engine_Description {
        application_description = &app_desc,
        display_description     = &display_desc,
        renderer_description    = &renderer_desc,
        update_proc             = loop,
    }

    engine = cal.create(&engine_desc) or_return
    defer cal.destroy(&engine)
    // /////////////


    // WIP: Shaders
    // ============
    r := engine.renderer

    shader_desc := cg.Gpu_Shader_Description {
        bindings = {
            {0, .Storage_Image},
        },
    }
    shader := cg.gpu_shader_create(r, &shader_desc) or_return
    defer cg.gpu_shader_destroy(r, shader)
    // ============

    cal.run(&engine) // Blocks until game is exited

    return .Ok
}


color := vec4{0, 1, 0.5, 1}

loop :: proc(ctx: ^cal.Engine) {
    debug.profile_scope()
    
    // log.infof("{:2.6f} : {:i}fps", ctx.time.delta, int(1 / ctx.time.delta))
    // log.info(input.get_key(ctx.input, .Space))
    color.g += ctx.time.delta
    if color.g > 1 {
        color.g = 0
    }
    cg.cmd_graphics_clear(ctx.renderer, color)
}

