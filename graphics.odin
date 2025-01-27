package callisto_sandbox

import "core:image"
import "core:image/png"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:bytes"
import "core:log"

import cal "callisto"
import "callisto/gpu"

Graphics_Memory :: struct {
        device            : gpu.Device,
        swapchain         : gpu.Swapchain,
        
        blend_opaque      : gpu.Blend_State,
        blend_transparent : gpu.Blend_State,

        depth_state       : gpu.Depth_Stencil_State,
        depth_texture     : gpu.Texture2D,
        depth_view        : gpu.Depth_Stencil_View,

        // render_target  : gpu.Texture,
        vertex_shader     : gpu.Vertex_Shader,
        fragment_shader   : gpu.Fragment_Shader,

        camera_cbuffer    : gpu.Buffer,
        model_cbuffers    : [3]gpu.Buffer,

        sprite_tex        : gpu.Texture2D,
        sprite_tex_view   : gpu.Texture_View,
        sampler           : gpu.Sampler,
        
        quad_mesh_pos     : gpu.Buffer,
        quad_mesh_uv      : gpu.Buffer,
        quad_mesh_indices : gpu.Buffer,
}



Model_Constants :: struct #align(16) #min_field_align(16) {
        model     : matrix[4,4]f32,
        modelview : matrix[4,4]f32,
        mvp       : matrix[4,4]f32,
}

graphics_init :: proc(app: ^App_Memory) {
        gmem := &app.graphics_memory

        d  : ^gpu.Device
        sc : ^gpu.Swapchain
        {
                device_create_info := gpu.Device_Create_Info {}

                gmem.device, _ = gpu.device_create(&device_create_info)
                d = &gmem.device


                swapchain_create_info := gpu.Swapchain_Create_Info {
                        window  = &app.window,
                        vsync   = true,
                        scaling = .Stretch,
                }
                gmem.swapchain, _ = gpu.swapchain_create(d, &swapchain_create_info)
                sc = &gmem.swapchain


                depth_create_info := gpu.Texture2D_Create_Info {
                        resolution = gmem.swapchain.resolution,
                        mip_levels = 1,
                        format     = .D32_FLOAT,
                        access     = .Device_General,
                        usage      = {.Depth_Stencil_Target},
                }
                gmem.depth_texture, _ = gpu.texture2d_create(d, &depth_create_info)

                depth_view_info := gpu.Depth_Stencil_View_Create_Info {
                        format      = .D32_FLOAT,
                        mip_level   = 0,
                        multisample = false,
                        array       = false,
                }
                gmem.depth_view, _    = gpu.depth_stencil_view_create(d, &gmem.depth_texture, &depth_view_info)
        }



        // Shaders
        {
                // Vertex
                vs_info := gpu.Vertex_Shader_Create_Info {
                        code = #load("resources_imported/shaders/mesh.vert.dxbc"),
                        vertex_attributes = {.Position, .Tex_Coord_0},
                }
                gmem.vertex_shader, _ = gpu.vertex_shader_create(d, &vs_info)

                // Fragment
                fs_info := gpu.Fragment_Shader_Create_Info {
                        code = #load("resources_imported/shaders/mesh.frag.dxbc"),
                }
                gmem.fragment_shader, _ = gpu.fragment_shader_create(d, &fs_info)
        }

        // Constant buffers
        {
                camera_initial_data := Camera_Constants{
                        view     = linalg.identity(matrix[4,4]f32),
                        proj     = linalg.identity(matrix[4,4]f32),
                        viewproj = linalg.identity(matrix[4,4]f32),
                }

                camera_buffer_create_info := gpu.Buffer_Create_Info {
                        size         = size_of(Camera_Constants),
                        stride       = size_of(Camera_Constants),
                        initial_data = &camera_initial_data,
                        access       = .Host_To_Device, // Dynamic per-frame constant buffer
                        usage        = {.Constant},
                }
                gmem.camera_cbuffer, _ = gpu.buffer_create(d, &camera_buffer_create_info)
                

                model_initial_data := Model_Constants{
                        model     = linalg.identity(matrix[4,4]f32),
                        modelview = linalg.identity(matrix[4,4]f32),
                        mvp       = linalg.identity(matrix[4,4]f32),
                }

                model_buffer_create_info := gpu.Buffer_Create_Info {
                        size         = size_of(Model_Constants),
                        stride       = size_of(Model_Constants),
                        initial_data = &model_initial_data,
                        access       = .Host_To_Device, // Dynamic per-frame constant buffer
                        usage        = {.Constant},
                }

                for i in 0..<len(gmem.model_cbuffers) {
                        gmem.model_cbuffers[i], _ = gpu.buffer_create(d, &model_buffer_create_info)
                }
        }

        // Dynamic state
        {
                sampler_info := gpu.Sampler_Create_Info {
                        min_filter     = .Linear,
                        mag_filter     = .Linear,
                        mip_filter     = .Linear,
                        max_anisotropy = .None,
                        min_lod        = gpu.min_lod_UNCLAMPED,
                        max_lod        = gpu.max_lod_UNCLAMPED,
                        lod_bias       = 0,
                        address_mode   = .Border,
                        border_color   = .Black_Opaque,
                }

                gmem.sampler, _ = gpu.sampler_create(d, &sampler_info)


                depth_info := gpu.Depth_Stencil_State_Create_Info {
                        depth_enable       = true,
                        depth_compare_op   = .Greater,
                        depth_write_enable = true,
                        // no stencil
                }

                gmem.depth_state, _ = gpu.depth_stencil_state_create(d, &depth_info)

                opaque_info := gpu.Blend_State_Create_Info {
                        independent_blends = false,
                        render_target_blends = {{
                                blend_enable = false,
                                color_write_mask = gpu.Color_Component_Flags_ALL,
                        }}
                }

                gmem.blend_opaque, _ = gpu.blend_state_create(d, &opaque_info)


                transparent_info := gpu.Blend_State_Create_Info {
                        independent_blends = false,
                        render_target_blends = {{
                                blend_enable           = true,
                                src_color_blend_factor = .Src_Alpha,
                                dst_color_blend_factor = .One_Minus_Src_Alpha,
                                color_blend_op         = .Add,
                                src_alpha_blend_factor = .Src_Alpha,
                                dst_alpha_blend_factor = .Dst_Alpha,
                                alpha_blend_op         = .Add,
                                color_write_mask       = gpu.Color_Component_Flags_ALL,
                        }}
                }

                gmem.blend_transparent, _ = gpu.blend_state_create(d, &transparent_info)
        }


        // Upload read-only resources
        {
                // Meshes
                pos_data := [][3]f32 {
                        {-0.5, 0, 0.5},
                        {-0.5, 0, -0.5,},
                        {0.5, 0, -0.5},
                        {0.5, 0, 0.5},
                }

                pos_info := gpu.Buffer_Create_Info {
                        size         = slice.size(pos_data),
                        stride       = size_of(f32) * 3,
                        initial_data = raw_data(pos_data),
                        access       = .Device_Immutable,
                        usage        = {.Vertex},
                }
                gmem.quad_mesh_pos, _ = gpu.buffer_create(d, &pos_info)
                
               
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
                gmem.quad_mesh_uv, _ = gpu.buffer_create(d, &uv_info)


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
                gmem.quad_mesh_indices, _ = gpu.buffer_create(d, &index_info)

                // Textures
                sprite_filename := cal.get_asset_path("textures/sprite.png", context.temp_allocator)

                // Load image data from disk
                sprite_image, err := image.load_from_file(sprite_filename, {.alpha_add_if_missing}, context.temp_allocator)
                assert(err == nil, "Failed to load image")
                pixels            := bytes.buffer_to_bytes(&sprite_image.pixels)

                sprite_info := gpu.Texture2D_Create_Info {
                        resolution            = {sprite_image.width, sprite_image.height},
                        mip_levels            = 1,
                        multisample           = .None,
                        format                = .R8G8B8A8_UNORM,
                        access                = .Device_Immutable,
                        usage                 = {.Shader_Resource},
                        allow_generate_mips   = false,
                        initial_data = {{
                                data = pixels, 
                                row_size = sprite_image.width * (sprite_image.depth / 8 * 4),
                        }},
                }
                gmem.sprite_tex, _ = gpu.texture2d_create(d, &sprite_info)

                // pass nil info to create a view of the full texture
                gmem.sprite_tex_view, _ = gpu.texture_view_create(d, &gmem.sprite_tex, nil)
        }

}


graphics_destroy :: proc(app: ^App_Memory) {
        gmem := &app.graphics_memory
        d := &gmem.device

        gpu.buffer_destroy(d, &gmem.camera_cbuffer)

        for &buf in gmem.model_cbuffers {
                gpu.buffer_destroy(d, &buf)
        }

        gpu.texture_view_destroy(d, &gmem.sprite_tex_view)
        gpu.texture2d_destroy(d, &gmem.sprite_tex)
        gpu.buffer_destroy(d, &gmem.quad_mesh_pos)
        gpu.buffer_destroy(d, &gmem.quad_mesh_uv)
        gpu.buffer_destroy(d, &gmem.quad_mesh_indices)

        gpu.vertex_shader_destroy(d, &gmem.vertex_shader)
        gpu.fragment_shader_destroy(d, &gmem.fragment_shader)

        gpu.depth_stencil_view_destroy(d, &gmem.depth_view)
        gpu.texture2d_destroy(d, &gmem.depth_texture)
        gpu.blend_state_destroy(d, &gmem.blend_opaque)
        gpu.blend_state_destroy(d, &gmem.blend_transparent)
        gpu.depth_stencil_state_destroy(d, &gmem.depth_state)
        gpu.sampler_destroy(d, &gmem.sampler)
        gpu.swapchain_destroy(d, &gmem.swapchain)
        gpu.device_destroy(d)
}


graphics_render :: proc(app: ^App_Memory) {
        gmem := &app.graphics_memory
        d  := &gmem.device
        sc := &gmem.swapchain

        if app.resized {
                gpu.texture2d_destroy(d, &gmem.depth_texture)
                gpu.swapchain_resize(d, sc, {0, 0})
                
                depth_create_info := gpu.Texture2D_Create_Info {
                        resolution = gmem.swapchain.resolution,
                        mip_levels = 1,
                        format     = .D32_FLOAT,
                        access     = .Device_General,
                        usage      = {.Depth_Stencil_Target},
                }
                gmem.depth_texture, _ = gpu.texture2d_create(d, &depth_create_info)

                app.camera_aspect = f32(sc.resolution.x) / f32(sc.resolution.y)

                app.resized = false
        }

        // rt := &app.render_target
        rt := &sc.render_target_view

        cb := &d.immediate_command_buffer
       
        gpu.command_buffer_begin(d, cb)
        viewports := []gpu.Viewport_Info {{
                rect = {0, 0, sc.resolution.x, sc.resolution.y},
                min_depth = 0,
                max_depth = 1,
        }}

        gpu.cmd_set_blend_state(cb, &gmem.blend_opaque)
        gpu.cmd_set_depth_stencil_state(cb, &gmem.depth_state)
        gpu.cmd_set_samplers(cb, {.Vertex, .Fragment}, 0, {&gmem.sampler})


        gpu.cmd_clear_render_target(cb, rt, {0, 0.4, 0.4, 1})
        gpu.cmd_clear_depth_stencil(cb, &gmem.depth_view, {.Depth}, 0, 0)
        
        gpu.cmd_set_render_targets(cb, {rt}, &gmem.depth_view)

        gpu.cmd_set_viewports(cb, viewports)

        gpu.cmd_set_vertex_shader(cb, &gmem.vertex_shader)
        gpu.cmd_set_fragment_shader(cb, &gmem.fragment_shader)

        gpu.cmd_set_vertex_buffers(cb, {&gmem.quad_mesh_pos, &gmem.quad_mesh_uv})
        gpu.cmd_set_index_buffer(cb, &gmem.quad_mesh_indices)


        aspect := f32(sc.resolution.x) / f32(sc.resolution.y)

        cam_transform := linalg.matrix4_translate_f32(app.camera_pos) * linalg.matrix4_from_euler_angles_zx(app.camera_yaw, app.camera_pitch)
        cam_view := linalg.inverse(cam_transform)
        // cam_proj := cal.matrix4_orthographic(2, aspect, 0, 1000)
        cam_proj := cal.matrix4_perspective(60 * math.RAD_PER_DEG, aspect, 0.01, 10)
        cam_viewproj := cam_proj * cam_view

        camera_data := Camera_Constants {
                view     = cam_view,
                proj     = cam_proj,
                viewproj = cam_proj * cam_view,
        }
        gpu.cmd_update_constant_buffer(cb, &gmem.camera_cbuffer, &camera_data)
        gpu.cmd_set_constant_buffers(cb, {.Vertex}, 0, {&gmem.camera_cbuffer})

        gpu.cmd_set_texture_views(cb, {.Fragment}, 0, {&gmem.sprite_tex_view})

        model_data : Model_Constants
        
        // z
        model_data.model     = linalg.matrix4_from_trs_f32({0, 0, 1}, linalg.QUATERNIONF32_IDENTITY, {1, 1, 1})
        model_data.modelview = cam_view * model_data.model
        model_data.mvp       = cam_proj * model_data.modelview

        gpu.cmd_update_constant_buffer(cb, &gmem.model_cbuffers[2], &model_data)
        gpu.cmd_set_constant_buffers(cb, {.Vertex}, 1, {&gmem.model_cbuffers[2]})
        gpu.cmd_draw(cb)



        // x
        model_data.model     = linalg.matrix4_from_trs_f32({1, 0, 0}, linalg.QUATERNIONF32_IDENTITY, {1, 1, 1})
        model_data.modelview = cam_view * model_data.model
        model_data.mvp       = cam_proj * model_data.modelview

        gpu.cmd_update_constant_buffer(cb, &gmem.model_cbuffers[0], &model_data)
        gpu.cmd_set_constant_buffers(cb, {.Vertex}, 1, {&gmem.model_cbuffers[0]})
        gpu.cmd_draw(cb)
        
        // y
        model_data.model     = linalg.matrix4_from_trs_f32({0, 1, 0}, linalg.QUATERNIONF32_IDENTITY, {1, 1, 1})
        model_data.modelview = cam_view * model_data.model
        model_data.mvp       = cam_proj * model_data.modelview

        gpu.cmd_update_constant_buffer(cb, &gmem.model_cbuffers[1], &model_data)
        gpu.cmd_set_constant_buffers(cb, {.Vertex}, 1, {&gmem.model_cbuffers[1]})
        gpu.cmd_draw(cb)



        gpu.command_buffer_end(d, cb)
        gpu.command_buffer_submit(d, cb)

        gpu.swapchain_present(d, sc)
}


