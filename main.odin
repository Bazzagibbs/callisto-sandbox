package callisto_sandbox

import "base:runtime"
import "core:log"
import "core:time"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "core:os"
import "core:fmt"

import "core:image"
import "core:image/png"
import "core:bytes"

import cal "callisto"
import "callisto/gpu"

App_Memory :: struct {
        engine               : cal.Engine,
        window               : cal.Window,

        // GPU (will likely be abstracted by engine)
        device               : gpu.Device,
        swapchain            : gpu.Swapchain,
        render_target        : gpu.Texture,
        compute_shader       : gpu.Shader,
        compute_draw_cbuffer : gpu.Buffer,
        sprite_tex           : gpu.Texture,

        // Application
        stopwatch            : time.Stopwatch,
        frame_count          : int,
}


Compute_Draw_Constants :: struct #align(16) #min_field_align(16) {
        color  : [4]f32,
        sprite : gpu.Texture_Reference,
        target : gpu.Texture_Reference,
}

Vertex :: struct #packed {
        position  : [3]f32,
        tex_coord : [2]f16,
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
                        runner     = runner,
                        app_memory = app, 
                        icon       = nil,
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
        d: ^gpu.Device
        {
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
                d = &app.device
        }

        // Create intermediate HDR render textures with the same size as the swapchain
        {
                extent := gpu.swapchain_get_extent(&app.device, &app.swapchain)

                render_target_init_info := gpu.Texture_Init_Info {
                        format      = .R16G16B16A16_SFLOAT,
                        usage       = {.Transfer_Src, .Transfer_Dst, .Color_Target, .Storage},
                        dimensions  = ._2D,
                        extent      = {extent.x, extent.y, 1},
                        mip_count   = 1,
                        layer_count = 1,
                }

                gpu.texture_init(d, &app.render_target, &render_target_init_info)
        }

        // Create test shader
        {
                shader_init_info := gpu.Shader_Init_Info {
                        code  = #load("resources/shaders/compute_draw.spv"),
                        stage = .Compute,
                }


                gpu.shader_init(d, &app.compute_shader, &shader_init_info)
        }

        // Create constant buffer
        {
                cbufs_init_info := gpu.Buffer_Init_Info {
                        size = size_of(Compute_Draw_Constants),
                        usage = {.Storage, .Transfer_Dst, .Addressable},
                }
                
                gpu.buffer_init(d, &app.compute_draw_cbuffer, &cbufs_init_info)
        }


        // Upload read-only resources
        {
                sprite_filename := cal.get_asset_path("images/sprite.png", context.temp_allocator)

                // Load image data from disk
                sprite_image, _ := image.load_from_file(sprite_filename, {.alpha_add_if_missing}, context.temp_allocator)
                pixels := bytes.buffer_to_bytes(&sprite_image.pixels)

                // Create texture GPU resource
                sprite_info := gpu.Texture_Init_Info {
                        format             = .R8G8B8A8_UNORM,
                        usage              = {.Sampled, .Transfer_Dst},
                        queue_usage        = {.Graphics, .Compute_Sync},
                        memory_access_type = .Device_Read_Only,
                        dimensions         = ._2D,
                        extent             = {u32(sprite_image.width), u32(sprite_image.height), 1},
                        mip_count          = 1,
                        layer_count        = 1,
                        multisample        = .None,
                        sampler_info       = gpu.Sampler_Info_DEFAULT,
                }
                gpu.texture_init(d, &app.sprite_tex, &sprite_info)


                // Prepare staging buffer
                staging : gpu.Buffer
                staging_info := gpu.Buffer_Init_Info {
                        size               = u64(len(pixels)),
                        usage              = {.Storage, .Transfer_Src},
                        queue_usage        = {.Graphics, .Compute_Sync},
                        memory_access_type = .Staging,
                }
                gpu.buffer_init(d, &staging, &staging_info)


                upload_buffer : ^gpu.Command_Buffer
                gpu.immediate_command_buffer_get(d, &upload_buffer)
                gpu.command_buffer_begin(d, upload_buffer)

                upload_info := gpu.Texture_Upload_Info {
                        size = u64(len(pixels)),
                        data = raw_data(pixels),
                }
               

                // Prepare texture for upload
                tex_dst_info := gpu.Texture_Transition_Info {
                        texture_aspect    = {.Color},
                        after_src_stages  = {},
                        before_dst_stages = {.Transfer},
                        src_layout        = .Undefined,
                        dst_layout        = .Transfer_Dst,
                        src_access        = {},
                        dst_access        = {.Transfer_Write}
                }
                gpu.cmd_transition_texture(d, upload_buffer, &app.sprite_tex, &tex_dst_info)
               
                // Upload
                gpu.cmd_upload_color_texture(d, upload_buffer, &staging, &app.sprite_tex, &upload_info)
                
                // Make texture read-only
                tex_read_info := gpu.Texture_Transition_Info {
                        texture_aspect    = {.Color},
                        after_src_stages  = {.Transfer},
                        before_dst_stages = {.All_Graphics},
                        src_layout        = .Transfer_Dst,
                        dst_layout        = .Read_Only,
                        src_access        = {.Transfer_Write},
                        dst_access        = {.Texture_Read}
                }
                gpu.cmd_transition_texture(d, upload_buffer, &app.sprite_tex, &tex_read_info)



                gpu.command_buffer_end(d, upload_buffer)
                gpu.immediate_command_buffer_submit(d, upload_buffer)

                gpu.buffer_destroy(d, &staging)
        }
}


@(export)
callisto_destroy :: proc (app_memory: rawptr) {
        app : ^App_Memory = (^App_Memory)(app_memory)
        d := &app.device
        
        gpu.device_wait_for_idle(&app.device)

        gpu.texture_destroy(d, &app.sprite_tex)
        gpu.buffer_destroy(d, &app.compute_draw_cbuffer)
        gpu.shader_destroy(d, &app.compute_shader)
        gpu.texture_destroy(d, &app.render_target)
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
        app : ^App_Memory = (^App_Memory)(app_memory)
        d  := &app.device
        sc := &app.swapchain
        rt := &app.render_target

        gpu.swapchain_wait_for_next_frame(d, sc)

        cb : ^gpu.Command_Buffer
        gpu.swapchain_acquire_command_buffer(d, sc, &cb)
       
        swapchain_target : ^gpu.Texture
        res := gpu.swapchain_acquire_texture(d, &app.swapchain, &swapchain_target)
        if res == .Swapchain_Rebuilt {
                on_swapchain_rebuilt(d, sc, app)
        }

        gpu.command_buffer_begin(d, cb)

        // Transition RT to be color target
        transition_rt_to_color_target := gpu.Texture_Transition_Info {
                texture_aspect    = {.Color},
                after_src_stages  = {},
                before_dst_stages = {.Color_Target_Output},
                src_layout        = .Undefined,
                dst_layout        = .General,
                src_access        = {},
                dst_access        = {.Memory_Write},
        }
        gpu.cmd_transition_texture(d, cb, rt, &transition_rt_to_color_target)

        // Render to the intermediate HDR texture using compute
        gpu.cmd_clear_color_texture(d, cb, rt, {0, 0, 0.5, 1})
        
        // Update dynamic constant buffers
        constant_data := Compute_Draw_Constants {
                color  = {(1 + math.sin(f32(app.frame_count) / 100)) / 2, 1, 1, 1},
                sprite = gpu.texture_get_reference_sampled(d, &app.sprite_tex),
                target = gpu.texture_get_reference_storage(&app.device, &app.render_target),
        }

        update_info := gpu.Buffer_Upload_Info {
                size       = size_of(Compute_Draw_Constants),
                dst_offset = 0,
                data       = &constant_data,
        }
        gpu.cmd_update_buffer(d, cb, &app.compute_draw_cbuffer, &update_info)


        // Set constant buffer
        cbuf_ref := gpu.buffer_get_reference(d, &app.compute_draw_cbuffer, size_of(Compute_Draw_Constants), 0)
        gpu.cmd_set_constant_buffer_0(d, cb, &cbuf_ref)

        gpu.cmd_bind_shader(d, cb, &app.compute_shader)

        target_extent := gpu.texture_get_extent(d, &app.render_target)
        workgroups := [2]u32 {u32(math.ceil(f32(target_extent.x) / 16.0)), u32(math.ceil(f32(target_extent.y) / 16.0))}
        gpu.cmd_dispatch(d, cb, {workgroups.x, workgroups.y, 1})


        // Prepare RT -> Swapchain transfer

        // SRC TEXTURE
        transition_rt_to_transfer_src := gpu.Texture_Transition_Info {
                texture_aspect    = {.Color},
                after_src_stages  = {.Color_Target_Output},
                before_dst_stages = {.Blit},
                src_layout        = .General,
                dst_layout        = .Transfer_Src,
                src_access        = {.Memory_Write},
                dst_access        = {.Memory_Read},
        }
        gpu.cmd_transition_texture(d, cb, rt, &transition_rt_to_transfer_src)

        // DST TEXTURE
        transition_sc_to_transfer_dst := gpu.Texture_Transition_Info {
                texture_aspect    = {.Color},
                after_src_stages  = {.Blit},
                before_dst_stages = {.Transfer},
                src_layout        = .Undefined,
                dst_layout        = .Transfer_Dst,
                src_access        = {.Memory_Write},
                dst_access        = {.Memory_Read, .Memory_Write},
        }
        gpu.cmd_transition_texture(d, cb, swapchain_target, &transition_sc_to_transfer_dst)

        // Copy RT to swapchain
        gpu.cmd_blit_color_texture(d, cb, rt, swapchain_target)

        // Make the render target presentable
        transition_sc_to_present := gpu.Texture_Transition_Info {
                texture_aspect    = {.Color},
                after_src_stages  = {.Blit},
                before_dst_stages = {},
                src_layout        = .Transfer_Dst,
                dst_layout        = .Present,
                src_access        = {.Memory_Write},
                dst_access        = {.Memory_Read, .Memory_Write},
        }
        gpu.cmd_transition_texture(d, cb, swapchain_target, &transition_sc_to_present)

        gpu.command_buffer_end(d, cb)

        // Submit work to GPU
        gpu.command_buffer_submit(d, cb)
        gpu.swapchain_present(d, sc)

        app.frame_count += 1
}

// ==================================


on_swapchain_rebuilt :: proc(d: ^gpu.Device, sc: ^gpu.Swapchain, a: ^App_Memory) {
        log.info("Rebuilt swapchain")

        gpu.device_wait_for_idle(d)
        gpu.texture_destroy(d, &a.render_target)

        // Recreate intermediate render target textures with new extent
        extent := gpu.swapchain_get_extent(d, sc)

        render_target_init_info := gpu.Texture_Init_Info {
                format      = .R16G16B16A16_SFLOAT,
                usage       = {.Transfer_Src, .Transfer_Dst, .Color_Target, .Storage},
                dimensions  = ._2D,
                extent      = {extent.x, extent.y, 1},
                mip_count   = 1,
                layer_count = 1,
        }

        gpu.texture_init(d, &a.render_target, &render_target_init_info)

}
