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

App_Memory :: struct {
        engine            : cal.Engine,
        window            : cal.Window,

        // GPU (will likely be abstracted by engine)
        device            : gpu.Device,
        swapchain         : gpu.Swapchain,
        // render_target     : gpu.Texture,
        vertex_shader     : gpu.Vertex_Shader,
        fragment_shader   : gpu.Fragment_Shader,
        // material_cbuffer  : gpu.Buffer,
        // sprite_tex        : gpu.Texture,
        //
        // quad_mesh_pos     : gpu.Buffer,
        // quad_mesh_uv      : gpu.Buffer,
        // quad_mesh_indices : gpu.Buffer,

        // Application
        stopwatch         : time.Stopwatch,
        frame_count       : int,
}


Material_Constants :: struct #align(16) #min_field_align(16) {
        tint : [4]f32,
        // diffuse : gpu.Texture_Reference,
}


// ==================================
// Implement these in every project

@(export)
callisto_init :: proc (runner: ^cal.Runner) {
        app := new(App_Memory)

        time.stopwatch_start(&app.stopwatch)

        // ENGINE
        {
                engine_init_info := cal.Engine_Init_Info {
                        runner          = runner,
                        app_memory      = app,
                        icon            = nil,
                        event_behaviour = .Before_Loop,
                }

                _ = cal.engine_init(&app.engine, &engine_init_info)
        }


        // WINDOW
        {
                window_init_info := cal.Window_Init_Info {
                        name     = "Callisto Sandbox - Main Window",
                        style    = cal.Window_Style_Flags_DEFAULT,
                        position = nil,
                        size     = nil,
                }

                _ = cal.window_init(&app.engine, &app.window, &window_init_info)
        }


        // GPU
        d  : ^gpu.Device
        sc : ^gpu.Swapchain
        {
                device_create_info := gpu.Device_Create_Info {
                        runner            = runner,
                }
                app.device, _ = gpu.device_create(&device_create_info)
                d = &app.device


                swapchain_create_info := gpu.Swapchain_Create_Info {
                        window  = &app.window,
                        vsync   = true,
                        scaling = .Stretch,
                }
                app.swapchain, _ = gpu.swapchain_create(&app.device, &swapchain_create_info)
                sc = &app.swapchain
        }



        // Shaders
        {
                // Vertex
                vs_info := gpu.Vertex_Shader_Create_Info {
                        code = #load("resources/shaders/mesh.vertex.dxbc"),
                        vertex_attributes = {.Position, .Tex_Coord_0},
                }
                app.vertex_shader, _ = gpu.vertex_shader_create(d, &vs_info)

                // Fragment
                fs_info := gpu.Fragment_Shader_Create_Info {
                        code = #load("resources/shaders/mesh.fragment.dxbc"),
                }
                app.fragment_shader, _ = gpu.fragment_shader_create(d, &fs_info)
        }



        // Upload read-only resources
        {
                // Meshes
                pos_data := [][3]f32 {
                        {-0.5, 0.5, 0},
                        {-0.5, -0.5, 0},
                        {0.5, -0.5, 0},
                        {0.5, 0.5, 0},
                }

                
                uv_data := [][2]f16 {
                        {0, 0},
                        {0, 1},
                        {1, 1},
                        {1, 0},
                }

                index_data := []u16 {
                        0, 1, 2,
                        1, 3, 2,
                }

                // Textures
                sprite_filename := cal.get_asset_path("images/sprite.png", context.temp_allocator)

                // Load image data from disk
                sprite_image, _ := image.load_from_file(sprite_filename, {.alpha_add_if_missing}, context.temp_allocator)
                pixels := bytes.buffer_to_bytes(&sprite_image.pixels)
        }
}


@(export)
callisto_destroy :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)
        d := &app.device
        
        // gpu.texture_destroy(d, &app.render_target)
        gpu.vertex_shader_destroy(d, &app.vertex_shader)
        gpu.fragment_shader_destroy(d, &app.fragment_shader)
        gpu.swapchain_destroy(d, &app.swapchain)
        gpu.device_destroy(d)

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
        mem.free_all(context.temp_allocator)

        app : ^App_Memory = (^App_Memory)(app_memory)
        d  := &app.device
        // sc := &app.swapchain
        // rt := &app.render_target


        // cal.exit()
        app.frame_count += 1
}

// ==================================


