package callisto_sandbox

import sdl "vendor:sdl3"
import "core:slice"
import "core:mem"
import "core:log"
import "core:image"
import "core:image/png"
import "core:bytes"
import "core:math/linalg"
import "core:encoding/cbor"
import "core:strings"
import sa "core:container/small_array"
import "core:math"


import cal "callisto"
import "callisto/editor/ufbx"

check_sdl_ptr :: proc(ptr: rawptr, exp := #caller_expression(ptr), loc := #caller_location) -> bool {
        if ptr != nil {
                return true
        }

        log.error(exp, "== nil", "->", sdl.GetError())
        return false
}


Graphics_Data :: struct {
        device: ^sdl.GPUDevice, // NOTE: not owned by this struct
        window: ^sdl.Window,    // NOTE: not owned by this struct

        // MODEL
        quad_mesh : cal.Mesh,
      
        // MATERIAL
        material : cal.Material,
        pipeline : ^sdl.GPUGraphicsPipeline,

        // TEXTURE
        // texture     : ^sdl.GPUTexture,
        texture        : cal.Texture,
        sampler        : ^sdl.GPUSampler,

        // RENDER STATE
        render_texture : ^sdl.GPUTexture,
        depth_texture  : ^sdl.GPUTexture,
        mesh_cb        : cal.Mesh_Render_Command_Buffer,

        // STAGING
        constants_staging_buffer : ^sdl.GPUTransferBuffer,

        // CAMERA TRANSFORM
        camera : cal.Camera,
}


Camera_Constants :: struct {
        view     : matrix[4,4]f32,
        proj     : matrix[4,4]f32,
        viewproj : matrix[4,4]f32,
}

Model_Constants :: struct {
        model     : matrix[4,4]f32,
}


graphics_init :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice, window: ^sdl.Window) {
        g.device = device
        g.window = window

        g.camera = cal.Camera{
                aspect_ratio = 16/9,
                fov_y        = 60 * math.RAD_PER_DEG,
                near_plane   = 0.01,
                far_plane    = 10_000,
        }

        // Transfer read-only data to GPU
        r, _ := cal.resource_uploader_create(device)
        defer cal.resource_uploader_destroy(&r)

        cal.resource_upload_begin(&r)
       

        mesh_info := cal.Asset_Mesh { submesh_infos = []cal.Submesh_Info{ cal.Submesh_Info{
                index_data = {
                        0, 1, 3,
                        3, 1, 2,
                },
                position_data = {
                        {-0.5, 0.5, 0},
                        {-0.5, -0.5, 0},
                        {0.5, -0.5, 0},
                        {0.5, 0.5, 0},
                },
                tex_coord_0_data = {
                        {0, 0},
                        {0, 1},
                        {1, 1},
                        {1, 0},
                },
        }}}

        g.quad_mesh, _ = cal.mesh_create(&r, &mesh_info)
        g.texture, _   = cal.asset_load_texture(&r, "textures/door.cal")




        sampler_info := sdl.GPUSamplerCreateInfo {
                min_filter        = .LINEAR,
                mag_filter        = .LINEAR,
                mipmap_mode       = .LINEAR,
                address_mode_u    = .CLAMP_TO_EDGE,
                address_mode_v    = .CLAMP_TO_EDGE,
                address_mode_w    = .CLAMP_TO_EDGE,
                mip_lod_bias      = 0,
                max_anisotropy    = 1,
                min_lod           = 0,
                max_lod           = max(f32),
                enable_anisotropy = false,
                enable_compare    = false,

        }
        g.sampler = sdl.CreateGPUSampler(device, sampler_info)
        check_sdl_ptr(g.sampler)




        resolution_x, resolution_y : i32
        _ = sdl.GetWindowSizeInPixels(window, &resolution_x, &resolution_y)

        rt_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = sdl.GetGPUSwapchainTextureFormat(g.device, g.window),
                usage                = {.COLOR_TARGET, .SAMPLER},
                width                = u32(resolution_x),
                height               = u32(resolution_y),
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = ._1, // MSAA?
        }
        g.render_texture = sdl.CreateGPUTexture(device, rt_info)
        check_sdl_ptr(g.render_texture)


        depth_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = .D32_FLOAT,
                usage                = {.DEPTH_STENCIL_TARGET},
                width                = u32(resolution_x),
                height               = u32(resolution_y),
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = ._1, // MSAA?
        }
        g.depth_texture = sdl.CreateGPUTexture(device, depth_info)
        check_sdl_ptr(g.depth_texture)


        // Shaders
        vertex_shader, _ := cal.asset_load_shader(&r, "shaders/shader.vert.cal")
        defer cal.shader_destroy(device, &vertex_shader)

        fragment_shader, _ := cal.asset_load_shader(&r, "shaders/shader.frag.cal")
        defer cal.shader_destroy(device, &fragment_shader)


        // Create pipeline
        // Vertex: two separate vertex buffers, one each for position and uv
        pipeline_vertex_buffer_descs := []sdl.GPUVertexBufferDescription {
                {slot = 0, pitch = size_of([3]f32), input_rate = .VERTEX }, // position
                {slot = 1, pitch = size_of([2]f32), input_rate = .VERTEX }, // tex_coord_0
        }

        pipeline_vertex_attributes := []sdl.GPUVertexAttribute {
                {location = 0, buffer_slot = 0, format = .FLOAT3, offset = 0}, // position
                {location = 1, buffer_slot = 1, format = .FLOAT2, offset = 0}, // tex_coord_0
        }

        pipeline_blend_state := sdl.GPUColorTargetBlendState {
                enable_blend = false,
                src_color_blendfactor = .SRC_ALPHA,
                dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
                color_blend_op        = .ADD,
                src_alpha_blendfactor = .SRC_ALPHA,
                dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
                alpha_blend_op        = .ADD,
                color_write_mask      = {.R, .G, .B, .A},
        }

        pipeline_color_targets := []sdl.GPUColorTargetDescription {
                {format = sdl.GetGPUSwapchainTextureFormat(device, window), blend_state = pipeline_blend_state}
        }

        pipeline_info := sdl.GPUGraphicsPipelineCreateInfo {
                vertex_shader   = vertex_shader.gpu_shader,
                fragment_shader = fragment_shader.gpu_shader,
                vertex_input_state =  {
                        vertex_buffer_descriptions = raw_data(pipeline_vertex_buffer_descs),
                        num_vertex_buffers         = u32(len(pipeline_vertex_buffer_descs)),
                        vertex_attributes          = raw_data(pipeline_vertex_attributes),
                        num_vertex_attributes      = u32(len(pipeline_vertex_attributes)),
                },
                primitive_type = .TRIANGLELIST,
                rasterizer_state = {
                        fill_mode = .FILL,
                        cull_mode = .NONE,
                        // front_face = .CLOCKWISE,
                        front_face = .COUNTER_CLOCKWISE,
                },
                multisample_state = {
                        sample_count = ._1,
                },
                depth_stencil_state = {
                        compare_op         = .GREATER_OR_EQUAL,
                        enable_depth_test  = true,
                        enable_depth_write = true,
                },

                target_info = {
                        color_target_descriptions = raw_data(pipeline_color_targets),
                        num_color_targets         = u32(len(pipeline_color_targets)),
                        depth_stencil_format      = depth_info.format,
                        has_depth_stencil_target  = true,
                }
                
        }
        g.pipeline = sdl.CreateGPUGraphicsPipeline(device, pipeline_info)
        check_sdl_ptr(g.pipeline)

        g.material = cal.Material {
                vertex_input      = {.Position, .Tex_Coord_0},
                pipeline          = g.pipeline,
                textures_vertex   = {},
                textures_fragment = {},
        }
        sa.append(&g.material.textures_fragment, g.texture)


        cal.resource_upload_end_wait(&r)

        g.mesh_cb, _ = cal.mesh_render_command_buffer_create()
}

// graphics_upload_texture :: proc(device: ^sdl.GPUDevice, pass: ^sdl.GPUCopyPass, data: $T/[]$E, staging_buffer: ^sdl.GPUTransferBuffer, dest_texture: ^sdl.GPUTexture, width, height: u32) {
//         mapped := sdl.MapGPUTransferBuffer(device, staging_buffer, false)
//         mem.copy(mapped, raw_data(data), slice.size(data))
//         sdl.UnmapGPUTransferBuffer(device, staging_buffer)
//        
//
//         transfer_info := sdl.GPUTextureTransferInfo {
//                 transfer_buffer = staging_buffer,
//                 offset          = 0,
//                 pixels_per_row  = width,
//                 rows_per_layer  = height,
//         } 
//
//         texture_region := sdl.GPUTextureRegion {
//                 texture   = dest_texture,
//                 mip_level = 0,
//                 layer     = 0,
//                 x         = 0,
//                 y         = 0,
//                 z         = 0,
//                 w         = width,
//                 h         = height,
//                 d         = 1,
//         }
//         sdl.UploadToGPUTexture(pass, transfer_info, texture_region, false)
// }


graphics_resize :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice, window: ^sdl.Window) {

}


// Called when the Scene window in the editor is resized
graphics_scene_view_resize :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice, dimensions: [2]u32) {
        _ = sdl.WaitForGPUIdle(device)
        sdl.ReleaseGPUTexture(device, g.render_texture)
        sdl.ReleaseGPUTexture(device, g.depth_texture)
        
        rt_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = sdl.GetGPUSwapchainTextureFormat(g.device, g.window),
                usage                = {.COLOR_TARGET, .SAMPLER},
                width                = dimensions.x,
                height               = dimensions.y,
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = ._1, // MSAA?
        }
        g.render_texture = sdl.CreateGPUTexture(device, rt_info)


        depth_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = .D32_FLOAT,
                usage                = {.DEPTH_STENCIL_TARGET},
                width                = dimensions.x,
                height               = dimensions.y,
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = ._1, // MSAA?
        }
        g.depth_texture = sdl.CreateGPUTexture(device, depth_info)

        g.camera.aspect_ratio = f32(dimensions.x) / f32(dimensions.y)
}



graphics_destroy :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice) {
        cal.mesh_render_command_buffer_destroy(&g.mesh_cb)
        cal.mesh_destroy(device, &g.quad_mesh)
        cal.texture_destroy(device, &g.texture)

        sdl.ReleaseGPUGraphicsPipeline(device, g.pipeline)

        sdl.ReleaseGPUSampler(device, g.sampler)
        sdl.ReleaseGPUTexture(device, g.render_texture)
        sdl.ReleaseGPUTexture(device, g.depth_texture)

        sdl.ReleaseGPUTransferBuffer(device, g.constants_staging_buffer)
        _ = sdl.WaitForGPUIdle(device)

}



graphics_draw :: proc(g: ^Graphics_Data, entities: [dynamic]Entity, cb: ^sdl.GPUCommandBuffer, rt: ^sdl.GPUTexture) {
        mb := &g.mesh_cb

        rt_info := sdl.GPUColorTargetInfo {
                texture              = rt,
                mip_level            = 0,
                layer_or_depth_plane = 0,
                clear_color          = {0.3, 0.3, 0.3, 1},
                load_op              = .CLEAR,
                store_op             = .STORE,
                cycle                = true,
        }

        dt_info := sdl.GPUDepthStencilTargetInfo {
                texture          = g.depth_texture,
                clear_depth      = 0,
                load_op          = .CLEAR,
                store_op         = .STORE,
                stencil_load_op  = .DONT_CARE,
                stencil_store_op = .DONT_CARE,
                cycle            = true,
                clear_stencil    = 0,
        }

        opaque_pass_info := cal.Mesh_Render_Pass_Info {
                options              = {},
                gpu_command_buffer   = cb,
                camera               = &g.camera,
                color_targets        = {rt_info},
                depth_stencil_target = dt_info,
                sampler_anisotropic  = g.sampler,
                sampler_trilinear    = g.sampler,

        }
        cal.mesh_render_begin(mb, &opaque_pass_info)


        for &e in entities {
                if .Has_Mesh_Renderer in e.flags {
                        cal.mesh_render_trs(mb, &e.mesh_renderer, e.position, e.rotation, e.scale)
                }
        }

        cal.mesh_render_end(mb)
}


graphics_pass_begin :: proc(cb: ^sdl.GPUCommandBuffer, camera: ^cal.Camera) {
        // Push camera constants to slot 0
        // uniform_data := cal.camera_get_uniform_data(camera)
        // sdl.PushGPUVertexUniformData(cb, 0, &uniform_data, size_of(uniform_data))
}

// graphics_draw_meshes :: proc(cb: ^sdl.GPUCommandBuffer, mesh_renderers: []cal.Mesh_Render_Info) {
        // Push material constants to slot 1
        // Push mesh constants to slot 2
        // sdl.PushGPUVertexUniformData(cb, 2, )
        // mesh_data := linalg.matrix4_from_trs_f32()
// }

graphics_pass_end :: proc() {
}
