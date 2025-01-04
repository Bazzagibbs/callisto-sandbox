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
        render_target     : gpu.Texture,
        vertex_shader     : gpu.Shader,
        fragment_shader   : gpu.Shader,
        material_cbuffer  : gpu.Buffer,
        sprite_tex        : gpu.Texture,

        quad_mesh_pos     : gpu.Buffer,
        quad_mesh_uv      : gpu.Buffer,
        quad_mesh_indices : gpu.Buffer,

        // Application
        stopwatch         : time.Stopwatch,
        frame_count       : int,
}


Material_Constants :: struct #align(16) #min_field_align(16) {
        tint : [4]f32,
        diffuse : gpu.Texture_Reference,
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
                vert_init_info := gpu.Shader_Init_Info {
                        code  = #load("resources/shaders/mesh.vertex.spv"),
                        stage = .Vertex,
                }

                gpu.shader_init(d, &app.vertex_shader, &vert_init_info)
                
                frag_init_info := gpu.Shader_Init_Info {
                        code  = #load("resources/shaders/mesh.fragment.spv"),
                        stage = .Fragment,
                }

                gpu.shader_init(d, &app.fragment_shader, &frag_init_info)

        }

        // Create constant buffer
        {
                cbufs_init_info := gpu.Buffer_Init_Info {
                        size = size_of(Material_Constants),
                        usage = {.Storage, .Transfer_Dst, .Addressable},
                }
                
                gpu.buffer_init(d, &app.material_cbuffer, &cbufs_init_info)
        }


        // Create quad mesh 
        {
                // This could be done into a single buffer, then create refs out of them
                pos_data := [][3]f32 {
                        {-0.5, 0.5, 0},
                        {-0.5, -0.5, 0},
                        {0.5, -0.5, 0},
                        {0.5, 0.5, 0},
                }

                pos_init_info := gpu.Buffer_Init_Info {
                        size               = slice.size(pos_data),
                        usage              = {.Vertex, .Transfer_Dst},
                        queue_usage        = {.Graphics},
                        memory_access_type = .Device_Read_Only,
                }

                gpu.buffer_init(d, &app.quad_mesh_pos, &pos_init_info)

                
                uv_data := [][2]f16 {
                        {0, 0},
                        {0, 1},
                        {1, 1},
                        {1, 0},
                }

                uv_init_info := gpu.Buffer_Init_Info {
                        size               = slice.size(uv_data),
                        usage              = {.Vertex, .Transfer_Dst},
                        queue_usage        = {.Graphics},
                        memory_access_type = .Device_Read_Only,
                }
                
                gpu.buffer_init(d, &app.quad_mesh_uv, &uv_init_info)


                index_data := []u16 {
                        0, 1, 2,
                        1, 3, 2,
                }
                
                index_init_info := gpu.Buffer_Init_Info {
                        size               = slice.size(index_data),
                        usage              = {.Vertex, .Transfer_Dst},
                        queue_usage        = {.Graphics},
                        memory_access_type = .Device_Read_Only,
                }
                
                gpu.buffer_init(d, &app.quad_mesh_indices, &index_init_info)

                log.warn(slice.size(pos_data))
                log.warn(slice.size(uv_data))
                log.warn(slice.size(index_data))

                staging : gpu.Buffer
                staging_info := gpu.Buffer_Init_Info {
                        size               = slice.size(pos_data) + slice.size(uv_data) + slice.size(index_data),
                        usage              = {.Storage, .Transfer_Src},
                        queue_usage        = {.Graphics, .Compute_Sync},
                        memory_access_type = .Staging,
                }
                gpu.buffer_init(d, &staging, &staging_info)

                cb: ^gpu.Command_Buffer
                gpu.immediate_command_buffer_get(d, &cb)
                gpu.command_buffer_begin(d, cb)

                pos_upload := gpu.Buffer_Upload_Info {
                        size = slice.size(pos_data),
                        src_offset = 0,
                        dst_offset = 0,
                        data = raw_data(pos_data),
                }
                gpu.cmd_upload_buffer(d, cb, &staging, &app.quad_mesh_pos, &pos_upload)

                uv_upload := gpu.Buffer_Upload_Info {
                        size = slice.size(uv_data),
                        src_offset = pos_upload.src_offset + pos_upload.size,
                        dst_offset = 0,
                        data = raw_data(uv_data),
                }
                gpu.cmd_upload_buffer(d, cb, &staging, &app.quad_mesh_uv, &uv_upload)


                index_upload := gpu.Buffer_Upload_Info {
                        size = slice.size(uv_data),
                        src_offset = uv_upload.src_offset + uv_upload.size,
                        dst_offset = 0,
                        data = raw_data(index_data),
                }
                gpu.cmd_upload_buffer(d, cb, &staging, &app.quad_mesh_indices, &index_upload)

                gpu.command_buffer_end(d, cb)
                gpu.immediate_command_buffer_submit(d, cb)

                gpu.buffer_destroy(d, &staging)
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
                        size               = len(pixels),
                        usage              = {.Storage, .Transfer_Src},
                        queue_usage        = {.Graphics, .Compute_Sync},
                        memory_access_type = .Staging,
                }
                gpu.buffer_init(d, &staging, &staging_info)


                upload_buffer : ^gpu.Command_Buffer
                gpu.immediate_command_buffer_get(d, &upload_buffer)
                gpu.command_buffer_begin(d, upload_buffer)

                upload_info := gpu.Texture_Upload_Info {
                        size = len(pixels),
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


        gpu.buffer_destroy(d, &app.quad_mesh_pos)
        gpu.buffer_destroy(d, &app.quad_mesh_uv)
        gpu.buffer_destroy(d, &app.quad_mesh_indices)

        gpu.texture_destroy(d, &app.sprite_tex)

        gpu.buffer_destroy(d, &app.material_cbuffer)
        gpu.shader_destroy(d, &app.vertex_shader)
        gpu.shader_destroy(d, &app.fragment_shader)
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
                dst_layout        = .Target,
                src_access        = {},
                dst_access        = {.Memory_Write},
        }
        gpu.cmd_transition_texture(d, cb, rt, &transition_rt_to_color_target)

        // Render to the intermediate HDR texture using compute
        // gpu.cmd_clear_color_texture(d, cb, rt, {0, 0, 0.5, 1})
        
        // Update dynamic constant buffers
        constant_data := Material_Constants {
                tint    = {(1 + math.sin(f32(app.frame_count) / 100)) / 2, 1, 1, 1},
                diffuse = gpu.texture_get_reference(d, &app.sprite_tex),
        }

        update_info := gpu.Buffer_Upload_Info {
                size       = size_of(Material_Constants),
                dst_offset = 0,
                data       = &constant_data,
        }
        gpu.cmd_update_buffer(d, cb, &app.material_cbuffer, &update_info)


        rt_attachment_info := gpu.Texture_Attachment_Info {
                texture_view   = gpu.texture_get_full_view(d, &app.render_target),
                texture_layout = .Target,
                load_op        = .Clear,
                store_op       = .Store,
                clear_value    = {color={0, 0, 0.4, 1}},
        }

        rt_extent := gpu.texture_get_extent(d, &app.render_target)
        render_info := gpu.Render_Begin_Info {
                render_area = {0, 0, rt_extent.x, rt_extent.y},
                layer_count     = 1,
                color_textures  = {},
                depth_texture   = nil,
                stencil_texture = nil,
        }
       
        gpu.cmd_begin_render(d, cb, &render_info)

        // Set constant buffer
        gpu.cmd_set_constant_buffer(d, cb, .Material, gpu.buffer_get_reference(d, &app.material_cbuffer))

        // Bind shaders
        gpu.cmd_bind_vertex_shader(d, cb, &app.vertex_shader)
        gpu.cmd_bind_fragment_shader(d, cb, &app.fragment_shader)

        // Bind mesh buffers
        vertex_buffer_bind_infos := []gpu.Vertex_Buffer_Bind_Info {
                {.Position,    gpu.buffer_get_reference(d,&app.quad_mesh_pos)},
                {.Tex_Coord_0, gpu.buffer_get_reference(d,&app.quad_mesh_uv)},
        }
        gpu.cmd_bind_vertex_buffers(d, cb, vertex_buffer_bind_infos)
        gpu.cmd_bind_index_buffer(d, cb, gpu.buffer_get_reference(d, &app.quad_mesh_indices), 6, .U16)


        gpu.cmd_draw(d, cb)

        gpu.cmd_end_render(d, cb)


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


        cal.exit()
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
