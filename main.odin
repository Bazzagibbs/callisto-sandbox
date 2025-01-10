package callisto_sandbox

import "core:log"
import "core:time"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "core:math/linalg/glsl"

import cal "callisto"


// TODO:

// at this point it should be possible to do engine stuff
// - mesh asset
// - render passes / compositor


Input_Actions :: bit_set[Input_Action]
Input_Action :: enum {
        Forward,
        Backward,
        Left,
        Right,
        Up,
        Down,
}

App_Memory :: struct {
        engine                 : cal.Engine,
        window                 : cal.Window,

        // GPU (will likely be abstracted by engine)
        graphics_memory        : Graphics_Memory,

        // Application
        stopwatch              : time.Stopwatch,
        tick_begin             : time.Tick,
        elapsed                : f32,
        resized                : bool,
        
        rmb_held               : bool,

        camera_pixels_to_world : f32,
        camera_yaw             : f32,
        camera_pitch           : f32,
        camera_pos             : [3]f32,
        cursor_pos             : [2]f32,

        actions                : Input_Actions,
}


// ==================================
// Implement these in every project

@(export)
callisto_init :: proc (runner: ^cal.Runner) {
        app := new(App_Memory)

        time.stopwatch_start(&app.stopwatch)

        app.tick_begin = time.tick_now()

        // ENGINE
        {
                engine_info := cal.Engine_Create_Info {
                        runner          = runner,
                        app_memory      = app,
                        icon            = nil,
                        event_behaviour = .Before_Loop,
                }

                app.engine, _ = cal.engine_create(&engine_info)
        }


        // WINDOW
        {
                window_info := cal.Window_Create_Info {
                        name     = "Callisto Sandbox - Main Window",
                        style    = cal.Window_Style_Flags_DEFAULT,
                        position = cal.Window_Position_AUTO,
                        size     = cal.Window_Size_AUTO,
                }

                app.window, _ = cal.window_create(&app.engine, &window_info)
        }


        app.camera_pos = {0, -1, 1}

        // GPU
        graphics_init(app)
}


@(export)
callisto_destroy :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)

        graphics_destroy(app)

        cal.window_destroy(&app.engine, &app.window)
        cal.engine_destroy(&app.engine)

        free(app)
}


// Communication from the platform layer happens here (window, input).
// By default the event queue gets pumped automatically at the beginning of every frame.
// Alternatively, by initializing the engine with `event_behaviour = .Manual`, you may pump the
// queue just before input is required with `callisto.event_pump()` to reduce input delay.
@(export)
callisto_event :: proc (app_memory: rawptr, event: cal.Event) -> (handled: bool) {
        app := (^App_Memory)(app_memory)

        // Events may be dispatched to several layers
        // if ui_event_handler(app, event) { return }
        // if gameplay_event_handler(app, event) { return }

        switch e in event {
        case cal.Runner_Event: 
                log.info(e)

        case cal.Input_Event:
                #partial switch ie in e.event {
                case cal.Input_Button:
                        on_button(app, ie)

                        return true

                case cal.Input_Vector2:
                        if ie.source == .Mouse_Move_Raw {
                                on_mouse_raw_input(app, ie)
                        }
                }

        case cal.Window_Event:
                #partial switch we in e.event {
                case cal.Window_Resized:
                        app.resized = true
                }
        }

        return false
}


@(export)
callisto_loop :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)

        mem.free_all(context.temp_allocator)

        app.elapsed = f32(time.duration_seconds(time.tick_since(app.tick_begin)))

        update(app)
        graphics_render(app)

        // cal.exit() // exit after one frame
}

// ==================================

on_mouse_raw_input :: proc(app: ^App_Memory, event: cal.Input_Vector2) {
        sensitivity :: 0.005

        if app.rmb_held {
        app.camera_yaw   += event.value.x * sensitivity
        app.camera_pitch += event.value.y * sensitivity
        }
}


on_mouse_button :: proc(app: ^App_Memory, event: cal.Input_Button) {
        #partial switch event.motion {
        case .Down:

        case .Up:
        }
}

on_button :: proc(app: ^App_Memory, event: cal.Input_Button) {
        if event.motion == .Down {
                #partial switch event.source {
                case .W: app.actions += {.Forward}
                case .S: app.actions += {.Backward}
                case .A: app.actions += {.Left}
                case .D: app.actions += {.Right}
                case .Q: app.actions += {.Down}
                case .E: app.actions += {.Up}

                case .Mouse_Right: app.rmb_held = true
                
                case .Esc: cal.exit(.Ok)
                        
                } 
        } else {
                #partial switch event.source {
                case .W: app.actions -= {.Forward}
                case .S: app.actions -= {.Backward}
                case .A: app.actions -= {.Left}
                case .D: app.actions -= {.Right}
                case .Q: app.actions -= {.Down}
                case .E: app.actions -= {.Up}

                case .Mouse_Right: app.rmb_held = false
                }
        }
}


update :: proc(app: ^App_Memory) {
        camera_move_speed :: 1

        time.stopwatch_stop(&app.stopwatch)
        delta_time := f32(time.duration_seconds(time.stopwatch_duration(app.stopwatch)))
        time.stopwatch_reset(&app.stopwatch)
        time.stopwatch_start(&app.stopwatch)

        wish_dir: [3]f32

        if .Forward in app.actions {
                wish_dir.y += 1
        }
        if .Backward in app.actions {
                wish_dir.y -= 1
        }
        if .Left in app.actions {
                wish_dir.x -= 1
        }
        if .Right in app.actions {
                wish_dir.x += 1
        }
        if .Up in app.actions {
                wish_dir.z += 1
        }
        if .Down in app.actions {
                wish_dir.z -= 1
        }

        wish_dir = linalg.clamp_length(wish_dir, 1)
        // Transform wish dir into view space
        view := linalg.matrix4_from_euler_angles_zx(app.camera_yaw, app.camera_pitch)
        wish_dir = (view * [4]f32{wish_dir.x, wish_dir.y, wish_dir.z, 0}).xyz

        app.camera_pos += wish_dir * (camera_move_speed * delta_time)
}
