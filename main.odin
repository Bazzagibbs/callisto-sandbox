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
        engine                  : cal.Engine,
        window                  : cal.Window,

        // GPU (will likely be abstracted by engine)
        device                  : gpu.Device,
        swapchain               : gpu.Swapchain,

        // Application
        stopwatch               : time.Stopwatch,
        frame_count             : int,
}


// ==================================
// Implement these in every project

@(export)
callisto_init :: proc (runner: ^cal.Runner) {
        app := new(App_Memory)

        time.stopwatch_start(&app.stopwatch)

        // ENGINE
        engine_init_info := cal.Engine_Init_Info {
                runner     = runner,
                app_memory = app, 
                icon       = nil,
                event_behaviour = .Before_Loop,
        }

        _ = cal.engine_init(&app.engine, &engine_init_info)


        // WINDOW
        window_init_info := cal.Window_Init_Info {
                name     = "Callisto Sandbox - Main Window",
                style    = cal.window_style_default(),
                position = nil,
                size     = nil,
        }

        _ = cal.window_init(&app.engine, &app.window, &window_init_info)


        // GPU
        device_init_info := gpu.Device_Init_Info {
                runner            = runner,
                required_features = {},
        }

        _ = gpu.device_init(&app.device, &device_init_info)


        swapchain_init_info := gpu.Swapchain_Init_Info {
                window = app.window,
                vsync  = .Double_Buffered,
        }

        _ = gpu.swapchain_init(&app.device, &app.swapchain, &swapchain_init_info)
}


@(export)
callisto_destroy :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)

        cal.window_destroy(&app.engine, &app.window)
        cal.engine_destroy(&app.engine)

        gpu.swapchain_destroy(&app.device, &app.swapchain)
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
        case cal.Runner_Event: 
                log.info(e)
        case cal.Input_Event:
                #partial switch ie in e.event {
                case cal.Input_Button:
                        log.info(ie)

                        if ie.source == .Esc {
                                cal.exit(.Ok)
                        }

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
        d  := &app.device
        sc := &app.swapchain

        gpu.swapchain_wait_for_next_frame(d, sc)

        cb : ^gpu.Command_Buffer
        gpu.swapchain_acquire_command_buffer(d, sc, &cb)
        
        render_target : ^gpu.Texture
        gpu.swapchain_acquire_texture(d, &app.swapchain, &render_target)

        // Record command buffer
        //  final_color_target := gpu.Color_Target_Info {
        //         texture  = &swapchain_texture,
        //         load_op  = .Dont_Care,
        //         store_op = .Store,
        // }

        gpu.command_buffer_begin(d, cb)
        // gpu.cmd_begin_render_pass(d, cb, &final_color_target, &depth_target)
        // gpu.cmd_bind_vertex_shader(d, cb, app.vertex_shader)
        // gpu.cmd_bind_fragment_shader(d, cb, app.fragment_shader)
        // gpu.cmd_transfer_uniforms(d, cb, app.uniforms)
        // gpu.cmd_draw(d, cb, mesh.verts, mesh.indices)
        // gpu.cmd_end_render_pass(d, cb)

        // Make the render target read/writeable
        transition_to_general := gpu.Texture_Transition_Info {
                texture_aspect    = {.Color},
                after_src_stages  = {.End},
                before_dst_stages = {.Begin},
                src_layout        = .Undefined,
                dst_layout        = .General,
                src_access        = {.Memory_Write},
                dst_access        = {.Memory_Read, .Memory_Write},
        }
        gpu.cmd_transition_texture(d, cb, render_target, &transition_to_general)

        gpu.cmd_clear_color_texture(d, cb, render_target, {0, 0, 1, 1})

        // Make the render target presentable
        transition_to_present := gpu.Texture_Transition_Info {
                texture_aspect    = {.Color},
                after_src_stages  = {.End},
                before_dst_stages = {.Begin},
                src_layout        = .General,
                dst_layout        = .Present,
                src_access        = {.Memory_Write},
                dst_access        = {.Memory_Read, .Memory_Write},
        }
        gpu.cmd_transition_texture(d, cb, render_target, &transition_to_present)

        gpu.command_buffer_end(d, cb)

        // Submit work to GPU
        gpu.command_buffer_submit(d, cb)
        gpu.swapchain_present(d, sc)
}

// ==================================

