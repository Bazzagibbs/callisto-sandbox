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
import "callisto/gpu"

App_Memory :: struct {
        engine      : cal.Engine,
        device      : gpu.Device,
        profiler    : cal.Profiler,
        window      : cal.Window,
        stopwatch   : time.Stopwatch,
        frame_count : int,

}


// ==================================
// Implement these in every project

@(export)
callisto_init :: proc (runner: ^cal.Runner) {
        app := new(App_Memory)
        
        cal.profiler_init(&app.profiler)
        time.stopwatch_start(&app.stopwatch)

        engine_init_info := cal.Engine_Init_Info {
                runner     = runner,
                app_memory = app, 
                icon       = nil,
                event_behaviour = .Before_Loop,
        }

        _ = cal.engine_init(&app.engine, &engine_init_info)


        window_init_info := cal.Window_Init_Info {
                name     = "Callisto Sandbox - Main Window",
                style    = cal.window_style_default(),
                position = nil,
                size     = nil,
        }

        _ = cal.window_init(&app.engine, &app.window, &window_init_info)


        device_init_info := gpu.Device_Init_Info {

        }

        _ = gpu.device_init(&app.device, &device_init_info)
}


@(export)
callisto_destroy :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)

        cal.window_destroy(&app.engine, &app.window)
        cal.engine_destroy(&app.engine)
        cal.profiler_destroy(&app.profiler)

        gpu.device_destroy(&app.device)

        free(app)
}


// Communication from the platform layer happens here (window, input).
// By default the event queue gets pumped automatically at the beginning of every frame.
// Alternatively, by initializing the engine with `event_behaviour = .Manual`, you may pump the
// queue just before input is required with `callisto.event_pump()` to reduce input delay.
@(export)
callisto_event :: proc (event: cal.Event, app_memory: rawptr) -> (handled: bool) {
        app := (^App_Memory)(app_memory)

        switch e in event {
        case cal.Input_Event:
                #partial switch ie in e.event {
                case cal.Input_Button:
                        log.info(ie)
                        return true
                }
        case cal.Window_Event:
                // Handle these
                log.info(e.event)
                #partial switch we in e.event {
                case cal.Window_Closed:
                }
        }

        return false
}


@(export)
callisto_loop :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)

        frame_time := time.stopwatch_duration(app.stopwatch)
        time.stopwatch_reset(&app.stopwatch)
        time.stopwatch_start(&app.stopwatch)
        // fmt.println(time.duration_milliseconds(frame_time))

        // cal.profile_scope(&app.profiler)

        // cal.event_pump(&app.engine)
        // simulate()
        // draw()


        // Change this to test hot reloading
        // if app.frame_count % 60 == 0 {
        //         log.info(app.frame_count)
        // }
        //
        // app.frame_count += 1
        // time.accurate_sleep(time.Second / 240)

        // if app.frame_count >= 1000 {
        //         log.info("Exiting at frame", app.frame_count)
        //         cal.exit(&app.engine)
        // }
}

// ==================================

