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

App_Memory :: struct {
        engine      : cal.Engine,
        profiler    : cal.Profiler,
        window      : cal.Window,
        frame_count : int,
}

// ==================================
// Implement these in every project


@(export)
callisto_init :: proc (runner: ^cal.Runner) {
        app := new(App_Memory)
        
        cal.profiler_init(&app.profiler)

        engine_init_info := cal.Engine_Init_Info {
                runner     = runner,
                app_memory = app, 
                icon       = nil,
                event_behaviour = .Before_Loop_Wait,
        }

        _ = cal.engine_init(&app.engine, &engine_init_info)


        window_create_info := cal.Window_Create_Info {
                name     = "Callisto Sandbox - Main Window",
                style    = cal.window_style_default(),
                position = nil,
                size     = nil,
        }

        _ = cal.window_create(&app.engine, &window_create_info, &app.window)
}


@(export)
callisto_destroy :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)

        cal.window_destroy(&app.engine, &app.window)
        cal.engine_destroy(&app.engine)
        cal.profiler_destroy(&app.profiler)

        free(app)
}

@(export)
callisto_event :: proc (event: cal.Event, app_memory: rawptr) -> (handled: bool) {
        app := (^App_Memory)(app_memory)

        switch e in event {
        case cal.Input_Event:
                log.info(e.event)
                // Can be redirected to Callisto's input handler, or intercepted beforehand.
                // cal.input_event_handler(&app.engine, e)
        case cal.Window_Event:
                // Handle these
                log.info(e.event)
                #partial switch we in e.event {
                case cal.Window_Closed:
                        // cal.exit()
                        // return true
                }
        }

        return false
}


@(export)
callisto_loop :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)

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
        time.accurate_sleep(time.Second / 240)

        // if app.frame_count >= 1000 {
        //         log.info("Exiting at frame", app.frame_count)
        //         cal.exit(&app.engine)
        // }
}

// ==================================

