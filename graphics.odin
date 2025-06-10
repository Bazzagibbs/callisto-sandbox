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


        gizmo_material : cal.Material,
        gizmo_pipeline : ^sdl.GPUGraphicsPipeline,

        // TEXTURE
        texture        : cal.Texture,
        sampler        : ^sdl.GPUSampler,

        // RENDER STATE
        render_texture_msaa : ^sdl.GPUTexture, // resolves into render_texture
        render_texture      : ^sdl.GPUTexture,
        depth_texture       : ^sdl.GPUTexture,
        depth_format        : sdl.GPUTextureFormat,
        msaa_count          : sdl.GPUSampleCount,
        mesh_cb             : cal.Mesh_Render_Command_Buffer,

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

        // Check which depth format is available
        if sdl.GPUTextureSupportsFormat(device, .D32_FLOAT, .D2, {.DEPTH_STENCIL_TARGET}) {
                g.depth_format = .D32_FLOAT
        } else {
                g.depth_format = .D24_UNORM
        }

        g.msaa_count = ._4


        // Transfer read-only data to GPU
        r, _ := cal.resource_uploader_create(device)
        defer cal.resource_uploader_destroy(&r)

        cal.resource_upload_begin(&r)       

        // Meshes
        {
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
        }


        // Textures + samplers
        {
                // g.texture, _   = cal.asset_load_texture(&r, "textures/door.cal")
                g.texture, _   = cal.asset_load_texture(&r, "textures/checkerboard_bw.cal")

                sampler_info := sdl.GPUSamplerCreateInfo {
                        min_filter        = .LINEAR,
                        mag_filter        = .LINEAR,
                        mipmap_mode       = .LINEAR,
                        address_mode_u    = .CLAMP_TO_EDGE,
                        address_mode_v    = .CLAMP_TO_EDGE,
                        address_mode_w    = .CLAMP_TO_EDGE,
                        mip_lod_bias      = 0,
                        max_anisotropy    = 8,
                        min_lod           = 0,
                        max_lod           = max(f32),
                        enable_anisotropy = true,
                        enable_compare    = false,

                }
                g.sampler = sdl.CreateGPUSampler(device, sampler_info)
                check_sdl_ptr(g.sampler)
        }

        // Render targets
        {
                resolution_x, resolution_y : i32
                _ = sdl.GetWindowSizeInPixels(window, &resolution_x, &resolution_y)
                graphics_create_render_targets(g, device, u32(resolution_x), u32(resolution_y))
        }


        // Shaders
        {
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
                                sample_count = g.msaa_count,
                        },
                        depth_stencil_state = {
                                compare_op         = .GREATER_OR_EQUAL,
                                enable_depth_test  = true,
                                enable_depth_write = true,
                        },

                        target_info = {
                                color_target_descriptions = raw_data(pipeline_color_targets),
                                num_color_targets         = u32(len(pipeline_color_targets)),
                                depth_stencil_format      = g.depth_format,
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
        }

        // Gizmos
        {
                gizmo_vertex_shader, _ := cal.asset_load_shader(&r, "shaders/gizmo.vert.cal")
                defer cal.shader_destroy(device, &gizmo_vertex_shader)

                gizmo_fragment_shader, _ := cal.asset_load_shader(&r, "shaders/gizmo.frag.cal")
                defer cal.shader_destroy(device, &gizmo_fragment_shader)

                gizmo_vertex_buffer_descs := []sdl.GPUVertexBufferDescription {{
                        slot       = 0,
                        pitch      = u32(size_of([3]f32)),
                        input_rate = .VERTEX,
                }}
                gizmo_vertex_attributes := []sdl.GPUVertexAttribute {{
                        location    = 0,
                        buffer_slot = 0,
                        format      = .FLOAT3,
                        offset      = 0,
                }}
                
                gizmo_vertex_state := sdl.GPUVertexInputState {
                        vertex_buffer_descriptions = raw_data(gizmo_vertex_buffer_descs),
                        num_vertex_buffers         = u32(len(gizmo_vertex_buffer_descs)),
                        vertex_attributes          = raw_data(gizmo_vertex_attributes),
                        num_vertex_attributes      = u32(len(gizmo_vertex_attributes)),
                }

                gizmo_ds_state := sdl.GPUDepthStencilState {
                        compare_op          = .GREATER_OR_EQUAL,
                        enable_depth_test   = true,
                        enable_depth_write  = true,
                        enable_stencil_test = false,
                }

                gizmo_rasterizer_state := sdl.GPURasterizerState {
                        fill_mode         = .LINE,
                        cull_mode         = .NONE,
                        enable_depth_bias = false,
                        enable_depth_clip = true,
                }

                gizmo_blend_state := sdl.GPUColorTargetBlendState {
                        enable_blend = false,
                        src_color_blendfactor = .SRC_ALPHA,
                        dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
                        color_blend_op        = .ADD,
                        src_alpha_blendfactor = .SRC_ALPHA,
                        dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
                        alpha_blend_op        = .ADD,
                        color_write_mask      = {.R, .G, .B, .A},
                }

                gizmo_color_targets := []sdl.GPUColorTargetDescription {{
                        format      = sdl.GetGPUSwapchainTextureFormat(device, window),
                        blend_state = gizmo_blend_state,
                }}
                gizmo_target_info := sdl.GPUGraphicsPipelineTargetInfo {
                        color_target_descriptions = raw_data(gizmo_color_targets),
                        num_color_targets         = u32(len(gizmo_color_targets)),
                        depth_stencil_format      = g.depth_format,
                        has_depth_stencil_target  = true,
                }

                gizmo_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo {
                        vertex_shader       = gizmo_vertex_shader.gpu_shader,
                        fragment_shader     = gizmo_fragment_shader.gpu_shader,
                        vertex_input_state  = gizmo_vertex_state,
                        primitive_type      = .LINESTRIP,
                        rasterizer_state    = gizmo_rasterizer_state,
                        multisample_state   = {sample_count=._1},
                        depth_stencil_state = gizmo_ds_state,
                        target_info         = gizmo_target_info,
                }
                g.gizmo_pipeline = sdl.CreateGPUGraphicsPipeline(device, gizmo_pipeline_info)
                check_sdl_ptr(g.gizmo_pipeline)

                g.gizmo_material = cal.Material {
                        vertex_input = {.Position},
                        pipeline     = g.gizmo_pipeline,
                }
        }



        cal.resource_upload_end_wait(&r)

        g.mesh_cb, _ = cal.mesh_render_command_buffer_create()
}


graphics_resize :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice, window: ^sdl.Window) {

}


// Called when the Scene window in the editor is resized
graphics_scene_view_resize :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice, dimensions: [2]u32) {
        _ = sdl.WaitForGPUIdle(device)
        sdl.ReleaseGPUTexture(device, g.render_texture_msaa)
        sdl.ReleaseGPUTexture(device, g.render_texture)
        sdl.ReleaseGPUTexture(device, g.depth_texture)

        graphics_create_render_targets(g, device, dimensions.x, dimensions.y)
}


graphics_create_render_targets :: proc (g: ^Graphics_Data, device: ^sdl.GPUDevice, resolution_x, resolution_y: u32) {
        rt_msaa_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = sdl.GetGPUSwapchainTextureFormat(g.device, g.window),
                usage                = {.COLOR_TARGET, /* .SAMPLER */ }, // Resolved in render pass
                width                = resolution_x,
                height               = resolution_y,
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = g.msaa_count,
        }
        g.render_texture_msaa = sdl.CreateGPUTexture(device, rt_msaa_info)
        check_sdl_ptr(g.render_texture_msaa)



        rt_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = sdl.GetGPUSwapchainTextureFormat(g.device, g.window),
                usage                = {.COLOR_TARGET, .SAMPLER},
                width                = resolution_x,
                height               = resolution_y,
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = ._1,
        }
        g.render_texture = sdl.CreateGPUTexture(device, rt_info)
        check_sdl_ptr(g.render_texture)

       
        depth_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = g.depth_format,
                usage                = {.DEPTH_STENCIL_TARGET},
                width                = u32(resolution_x),
                height               = u32(resolution_y),
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = g.msaa_count,
        }
        g.depth_texture = sdl.CreateGPUTexture(device, depth_info)
        check_sdl_ptr(g.depth_texture)

        g.depth_format = depth_info.format
        
        g.camera.aspect_ratio = f32(resolution_x) / f32(resolution_y)
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
                texture               = g.render_texture_msaa,
                mip_level             = 0,
                layer_or_depth_plane  = 0,
                clear_color           = {0.3, 0.3, 0.3, 1},
                load_op               = .CLEAR,
                store_op              = .RESOLVE,
                resolve_texture       = rt,
                resolve_mip_level     = 0,
                resolve_layer         = 0,
                cycle                 = true,
                cycle_resolve_texture = true,
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
                        cal.mesh_render_trs(mb, &e.mesh_renderer, e.position, e.rotation.quaternion, e.scale)
                }
        }


        // gizmo_set_color(mb, {0, 0, 1})
        // gizmo_draw_ray(mb, {0, 0, 3}, {0, 1, 1})

        cal.mesh_render_end(mb)
}


graphics_pass_begin :: proc(cb: ^sdl.GPUCommandBuffer, camera: ^cal.Camera) {
        // Push camera constants to slot 0
        // uniform_data := cal.camera_get_uniform_data(camera)
        // sdl.PushGPUVertexUniformData(cb, 0, &uniform_data, size_of(uniform_data))
}


graphics_pass_end :: proc() {
}


// gizmo_set_color :: proc(mb: ^cal.Mesh_Render_Command_Buffer, color: [3]f32) {
// }
//
// gizmo_draw_line :: proc(mb: ^cal.Mesh_Render_Command_Buffer, a, b: [3]f32) {
//
// }
//
// gizmo_draw_ray :: proc(mb: ^cal.Mesh_Render_Command_Buffer, origin, direction: [3]f32, length: f32 = 1) {
//         gizmo_draw_line(mb, origin, origin + linalg.normalize0(direction) * length)
// }


// gizmo_draw_wire_sphere :: proc(mb: ^cal.Mesh_Render_Command_Buffer, origin: [3]f32, radius: f32) {
// }
//
// gizmo_draw_wire_capsule :: proc(mb: ^cal.Mesh_Render_Command_Buffer, centre: [3]f32, radius, height: f32) { 
// }

