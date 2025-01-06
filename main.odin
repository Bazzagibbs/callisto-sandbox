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

// - samplers
// - texture views

// - Change `*_init` procs to `*_create -> *`
// - Remove `Maybe()` from window create info

// at this point it should be possible to do engine stuff
// - mesh asset
// - render passes / compositor


App_Memory :: struct {
        engine            : cal.Engine,
        window            : cal.Window,

        // GPU (will likely be abstracted by engine)
        device            : gpu.Device,
        swapchain         : gpu.Swapchain,
        // render_target  : gpu.Texture,
        vertex_shader     : gpu.Vertex_Shader,
        fragment_shader   : gpu.Fragment_Shader,
        camera_cbuffer    : gpu.Buffer,
        // sprite_tex     : gpu.Texture,
        //
        quad_mesh_pos     : gpu.Buffer,
        quad_mesh_uv      : gpu.Buffer,
        quad_mesh_indices : gpu.Buffer,

        // Application
        stopwatch         : time.Stopwatch,
        frame_count       : int,
        tick_begin        : time.Tick,
        elapsed           : f32,
        resized           : bool,
}


Camera_Constants :: struct #align(16) #min_field_align(16) {
        view : matrix[4,4]f32,
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

        // Constant buffers
        {
                initial_data := Camera_Constants{}

                camera_buffer_create_info := gpu.Buffer_Create_Info {
                        size         = size_of(Camera_Constants),
                        stride       = size_of(Camera_Constants),
                        initial_data = &initial_data,
                        access       = .Host_To_Device, // Dynamic per-frame constant buffer
                        usage        = {.Constant},
                }
                app.camera_cbuffer, _ = gpu.buffer_create(d, &camera_buffer_create_info)
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

                pos_info := gpu.Buffer_Create_Info {
                        size         = slice.size(pos_data),
                        stride       = size_of(f32) * 3,
                        initial_data = raw_data(pos_data),
                        access       = .Device_Immutable,
                        usage        = {.Vertex},
                }
                app.quad_mesh_pos, _ = gpu.buffer_create(d, &pos_info)
                
               
                uv_data := [][2]f16 {
                        {0, 0},
                        {0, 1},
                        {1, 1},
                        {1, 0},
                }

                uv_info := gpu.Buffer_Create_Info {
                        size         = slice.size(uv_data),
                        stride       = size_of(f16) * 2,
                        initial_data = raw_data(uv_data),
                        access       = .Device_Immutable,
                        usage        = {.Vertex},
                }
                app.quad_mesh_uv, _ = gpu.buffer_create(d, &uv_info)


                index_data := []u16 {
                        0, 2, 1,
                        0, 3, 2,
                }

                index_info := gpu.Buffer_Create_Info {
                        size         = slice.size(index_data),
                        stride       = size_of(f16) * 1,
                        initial_data = raw_data(index_data),
                        access       = .Device_Immutable,
                        usage        = {.Index},
                }
                app.quad_mesh_indices, _ = gpu.buffer_create(d, &index_info)

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

        gpu.buffer_destroy(d, &app.camera_cbuffer)

        gpu.buffer_destroy(d, &app.quad_mesh_pos)
        gpu.buffer_destroy(d, &app.quad_mesh_uv)
        gpu.buffer_destroy(d, &app.quad_mesh_indices)

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
                case cal.Window_Resized:
                        app.resized = true
                }
        }

        return false
}


@(export)
callisto_loop :: proc (app_memory: rawptr) {
        mem.free_all(context.temp_allocator)


        app : ^App_Memory = (^App_Memory)(app_memory)
        d  := &app.device
        sc := &app.swapchain

        if app.resized {
                gpu.swapchain_resize(d, sc, {0, 0})
                app.resized = false
        }
        
        app.elapsed = f32(time.duration_seconds(time.tick_since(app.tick_begin)))

        // rt := &app.render_target
        rt := &sc.render_target_view

        cb := &d.immediate_command_buffer
       
        gpu.command_buffer_begin(d, cb)
        viewports := []gpu.Viewport_Info {{
                rect = {0, 0, sc.resolution.x, sc.resolution.y},
                min_depth = 0,
                max_depth = 1,
        }}

        gpu.cmd_clear_render_target(cb, rt, {0, 0.4, 0.4, 1})

        gpu.cmd_set_viewports(cb, viewports)

        gpu.cmd_set_vertex_shader(cb, &app.vertex_shader)
        gpu.cmd_set_fragment_shader(cb, &app.fragment_shader)

        gpu.cmd_set_vertex_buffers(cb, {&app.quad_mesh_pos, &app.quad_mesh_uv})
        gpu.cmd_set_index_buffer(cb, &app.quad_mesh_indices)


        camera_data := Camera_Constants {
                view = linalg.matrix4_translate_f32({0, math.sin(app.elapsed) * 0.2, 0})
        }

        gpu.cmd_update_constant_buffer(cb, &app.camera_cbuffer, &camera_data)

        gpu.cmd_set_constant_buffers(cb, {.Vertex}, 0, {&app.camera_cbuffer})

        gpu.cmd_set_render_targets(cb, {&sc.render_target_view}, nil)
        gpu.cmd_draw(cb)


        gpu.command_buffer_end(d, cb)
        gpu.command_buffer_submit(d, cb)

        gpu.swapchain_present(d, sc)

        // cal.exit()
        app.frame_count += 1
}

// ==================================


