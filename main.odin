package callisto_sandbox

import "base:runtime"
import "core:log"
import "core:time"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "core:os"
import "core:fmt"
import "core:slice"

import "core:image"
import "core:image/png"
import "core:bytes"

import cal "callisto"
import "callisto/gpu"


// TODO:

// - Remove `Maybe()` from window create info

// at this point it should be possible to do engine stuff
// - mesh asset
// - render passes / compositor


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
        
        lmb_held               : bool,

        camera_pixels_to_world : f32,
        camera_pos             : [3]f32,
        cursor_pos             : [2]f32,
        lmb_down_camera_pos    : [2]f32,
        lmb_down_cursor_pos    : [2]f32,
}


Camera_Constants :: struct #align(16) #min_field_align(16) {
        view     : matrix[4,4]f32,
        proj     : matrix[4,4]f32,
        viewproj : matrix[4,4]f32,
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
                        position = nil,
                        size     = nil,
                }

                app.window, _ = cal.window_create(&app.engine, &window_info)
        }


        app.camera_pos = {5, 3, 5}

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
callisto_event :: proc (event: cal.Event, app_memory: rawptr) -> (handled: bool) {
        app := (^App_Memory)(app_memory)

        switch e in event {
        case cal.Runner_Event: 
                log.info(e)
        case cal.Input_Event:
                #partial switch ie in e.event {
                case cal.Input_Button:
                        if ie.motion == .Down {
                                #partial switch ie.source {
                                case .Esc: cal.exit(.Ok)
                                case .Mouse_Left: on_lmb_down(app, ie)
                                }
                        } else if ie.motion == .Up {
                                #partial switch ie.source {
                                case .Mouse_Left: on_lmb_up(app, ie)
                                }

                        }

                        return true

                case cal.Input_Vector2:
                        if ie.source == .Mouse_Position_Cursor {
                                on_cursor_moved(app, ie)
                        }
                }
        case cal.Window_Event:
                // Handle these
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

        graphics_render(app)

        // cal.exit() // exit after one frame
}

// ==================================

on_cursor_moved :: proc(app: ^App_Memory, event: cal.Input_Vector2) {
        // cursor moved event holds the absolute position of the mouse cursor on the screen.
        app.cursor_pos = event.value
        if app.lmb_held {
                delta_pixels  := app.cursor_pos - app.lmb_down_cursor_pos
                delta_world   := delta_pixels / (f32(app.graphics_memory.swapchain.resolution.y) * 0.5)
                delta_world.y *= -1

                app.camera_pos.xy  =  app.lmb_down_camera_pos + delta_world
        }
}

on_lmb_down :: proc(app: ^App_Memory, event: cal.Input_Button) {
        app.lmb_down_cursor_pos = app.cursor_pos
        app.lmb_down_camera_pos = app.camera_pos.xy
        app.lmb_held = true
}

on_lmb_up :: proc(app: ^App_Memory, event: cal.Input_Button) {
        app.lmb_held = false
}
