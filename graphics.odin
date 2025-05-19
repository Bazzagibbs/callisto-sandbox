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
        vb_position      : ^sdl.GPUBuffer,
        vb_tex_coord_0   : ^sdl.GPUBuffer,
        index_buffer     : ^sdl.GPUBuffer,
        index_buffer_len : u32,
      
        // MATERIAL
        vertex_shader   : ^sdl.GPUShader,
        fragment_shader : ^sdl.GPUShader,
        pipeline        : ^sdl.GPUGraphicsPipeline,

        // TEXTURE
        texture          : ^sdl.GPUTexture,
        sampler          : ^sdl.GPUSampler,

        // RENDER STATE
        render_texture   : ^sdl.GPUTexture,
        depth_texture    : ^sdl.GPUTexture,

        // STAGING
        constants_staging_buffer : ^sdl.GPUTransferBuffer,

        // CAMERA TRANSFORM
        cam_pos : [3]f32,
        cam_rot : quaternion128,
        cam_aspect : f32,
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

        // Transfer read-only data to GPU
        cb := sdl.AcquireGPUCommandBuffer(device)

        copy_pass := sdl.BeginGPUCopyPass(cb)
        

        // Meshes
        pos_data := [][3]f32 {
                // {-0.5, 0, 0.5},
                // {-0.5, 0, -0.5,},
                // {0.5, 0, -0.5},
                // {0.5, 0, 0.5},
                {-0.5, 0.5, 0},
                {-0.5, -0.5, 0},
                {0.5, -0.5, 0},
                {0.5, 0.5, 0},
        }
        pos_info := sdl.GPUBufferCreateInfo {
                usage = {.VERTEX},
                size  = u32(slice.size(pos_data)),
        }
        g.vb_position = sdl.CreateGPUBuffer(device, pos_info)

        staging_buffer_info := sdl.GPUTransferBufferCreateInfo {
                usage = .UPLOAD,
                size = u32(slice.size(pos_data)), // TODO: Figure out what to do here - should I precalculate the largest buffer? or maintain my own staging buffer list
        }
        vertex_staging_buffer := sdl.CreateGPUTransferBuffer(device, staging_buffer_info)
        defer sdl.ReleaseGPUTransferBuffer(device, vertex_staging_buffer)

        graphics_upload_buffer(device, copy_pass, pos_data, vertex_staging_buffer, g.vb_position)

       
        uv_data := [][2]f32 {
                {0, 0},
                {0, 1},
                {1, 1},
                {1, 0},
        }
        uv_info := sdl.GPUBufferCreateInfo {
                usage = {.VERTEX},
                size  = u32(slice.size(uv_data)),
        }
        g.vb_tex_coord_0 = sdl.CreateGPUBuffer(device, uv_info)
        graphics_upload_buffer(device, copy_pass, uv_data, vertex_staging_buffer, g.vb_tex_coord_0)
        

        index_data := []u16 {
                0, 2, 1,
                0, 3, 2,
        }
        index_info := sdl.GPUBufferCreateInfo {
                usage = {.INDEX},
                size  = u32(slice.size(index_data)),
        }
        g.index_buffer = sdl.CreateGPUBuffer(device, index_info)
        graphics_upload_buffer(device, copy_pass, index_data, vertex_staging_buffer, g.index_buffer)
        g.index_buffer_len = u32(len(index_data))
        

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


        texture_bin := #load("imported/textures/door.png")
        texture_image, err := image.load_from_bytes(texture_bin, {.alpha_add_if_missing})
        assert(err == {}, "Could not load image")
        defer image.destroy(texture_image)

        texture_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = .R8G8B8A8_UNORM if texture_image.depth==8 else .R16G16B16A16_UNORM,
                usage                = {.SAMPLER},
                width                = u32(texture_image.width),
                height               = u32(texture_image.height),
                layer_count_or_depth = 1,
                num_levels           = 1,
        }
        g.texture = sdl.CreateGPUTexture(device, texture_info)
        check_sdl_ptr(g.texture)

        texture_pixels := bytes.buffer_to_bytes(&texture_image.pixels)

        texture_staging_buffer_info := sdl.GPUTransferBufferCreateInfo {
                usage = .UPLOAD,
                size = u32(slice.size(texture_pixels)),
        }
        texture_staging_buffer := sdl.CreateGPUTransferBuffer(device, texture_staging_buffer_info)
        defer sdl.ReleaseGPUTransferBuffer(device, texture_staging_buffer)
        graphics_upload_texture(device, copy_pass, texture_pixels, texture_staging_buffer, g.texture, u32(texture_image.width), u32(texture_image.height))


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
        g.vertex_shader, _ = cal.asset_load_shader(g.device, "shaders/shader.vert.cal")
        check_sdl_ptr(g.vertex_shader)
        defer sdl.ReleaseGPUShader(device, g.vertex_shader)

        g.fragment_shader, _ = cal.asset_load_shader(g.device, "shaders/shader.frag.cal")
        check_sdl_ptr(g.fragment_shader)
        defer sdl.ReleaseGPUShader(device, g.fragment_shader)


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
                vertex_shader   = g.vertex_shader,
                fragment_shader = g.fragment_shader,
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


        // Constant buffers
        // constants_camera_info := sdl.GPUBufferCreateInfo {
        //         usage = {.GRAPHICS_STORAGE_READ},
        //         size  = u32(size_of(Camera_Constants)),
        // }
        // g.constants_camera = sdl.CreateGPUBuffer(device, constants_camera_info)
        // check_sdl_ptr(g.constants_camera)
        //
        //
        // constants_model_info := sdl.GPUBufferCreateInfo {
        //         usage = {.GRAPHICS_STORAGE_READ},
        //         size  = u32(size_of(Model_Constants)),
        // }
        // g.constants_model = sdl.CreateGPUBuffer(device, constants_model_info)
        // check_sdl_ptr(g.constants_model)


        // constants_staging_buffer_info := sdl.GPUTransferBufferCreateInfo {
        //         usage = .UPLOAD,
        //         size  = u32(size_of(Camera_Constants)), // Model constants are the same size, but be careful!
        // }
        // g.constants_staging_buffer = sdl.CreateGPUTransferBuffer(device, constants_staging_buffer_info)

        // Load vertex/index data from model
        // Load texture

        sdl.EndGPUCopyPass(copy_pass)
        _ = sdl.SubmitGPUCommandBuffer(cb)
}

graphics_upload_buffer :: proc(device: ^sdl.GPUDevice, pass: ^sdl.GPUCopyPass, data: $T/[]$E, staging_buffer: ^sdl.GPUTransferBuffer, dest_buffer: ^sdl.GPUBuffer) {

        mapped := sdl.MapGPUTransferBuffer(device, staging_buffer, cycle = true)
        mem.copy(mapped, raw_data(data), slice.size(data))
        sdl.UnmapGPUTransferBuffer(device, staging_buffer)
        
        sdl.UploadToGPUBuffer(pass, {staging_buffer, 0},  {dest_buffer, 0, u32(slice.size(data))}, cycle = false)

}

graphics_upload_texture :: proc(device: ^sdl.GPUDevice, pass: ^sdl.GPUCopyPass, data: $T/[]$E, staging_buffer: ^sdl.GPUTransferBuffer, dest_texture: ^sdl.GPUTexture, width, height: u32) {

        mapped := sdl.MapGPUTransferBuffer(device, staging_buffer, false)
        mem.copy(mapped, raw_data(data), slice.size(data))
        sdl.UnmapGPUTransferBuffer(device, staging_buffer)
       

        transfer_info := sdl.GPUTextureTransferInfo {
                transfer_buffer = staging_buffer,
                offset          = 0,
                pixels_per_row  = width,
                rows_per_layer  = height,
        } 

        texture_region := sdl.GPUTextureRegion {
                texture   = dest_texture,
                mip_level = 0,
                layer     = 0,
                x         = 0,
                y         = 0,
                z         = 0,
                w         = width,
                h         = height,
                d         = 1,
        }
        sdl.UploadToGPUTexture(pass, transfer_info, texture_region, false)
}


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

        g.cam_aspect = f32(dimensions.x) / f32(dimensions.y)
}



graphics_destroy :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice) {
        sdl.ReleaseGPUGraphicsPipeline(device, g.pipeline)

        sdl.ReleaseGPUSampler(device, g.sampler)
        sdl.ReleaseGPUTexture(device, g.texture)
        sdl.ReleaseGPUTexture(device, g.depth_texture)

        sdl.ReleaseGPUTransferBuffer(device, g.constants_staging_buffer)
        sdl.ReleaseGPUBuffer(device, g.vb_position)
        sdl.ReleaseGPUBuffer(device, g.vb_tex_coord_0)
        sdl.ReleaseGPUBuffer(device, g.index_buffer)
        _ = sdl.WaitForGPUIdle(device)

}



graphics_draw :: proc(g: ^Graphics_Data, cb: ^sdl.GPUCommandBuffer, rt: ^sdl.GPUTexture) {
        // g.cam_pos = {0, 0, -3}

        cam_transform := linalg.matrix4_translate_f32(g.cam_pos) * linalg.matrix4_from_quaternion_f32(g.cam_rot)
        // cam_transform := linalg.matrix4_from_quaternion_f32(g.cam_rot) * linalg.matrix4_translate_f32(g.cam_pos)

        view := linalg.matrix4_inverse_transpose_f32(cam_transform)
        // view := linalg.MATRIX4F32_IDENTITY

        
        proj := cal.projection_perspective(60, g.cam_aspect, 0.01, 10_000)
        // proj := linalg.MATRIX4F32_IDENTITY

        cam_constants := Camera_Constants {
                view     = view,
                proj     = proj,
                viewproj = view * proj,
        }

        model_constants := Model_Constants {
                model     = linalg.matrix4_translate_f32({-0.6, 0, 0}),
        }

        model_constants_2 := Model_Constants {
                model     = linalg.matrix4_translate_f32({0, 0, 100}),
        }


        // Draw pass
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

        pass := sdl.BeginGPURenderPass(
                command_buffer            = cb,
                color_target_infos        = &rt_info,
                num_color_targets         = 1,
                depth_stencil_target_info = &dt_info
        )

        sdl.BindGPUGraphicsPipeline(pass, g.pipeline)


        vert_buffer_bindings := []sdl.GPUBufferBinding {
                {g.vb_position, 0},
                {g.vb_tex_coord_0, 0},
        }
        sdl.BindGPUVertexBuffers(pass, 0, raw_data(vert_buffer_bindings), u32(len(vert_buffer_bindings)))


        texture_sampler_bindings := []sdl.GPUTextureSamplerBinding {
                {g.texture, g.sampler},
        }
        sdl.BindGPUFragmentSamplers(pass, 0, raw_data(texture_sampler_bindings), u32(len(texture_sampler_bindings)))

        index_buffer_binding := sdl.GPUBufferBinding {g.index_buffer, 0}        
        sdl.BindGPUIndexBuffer(pass, index_buffer_binding, ._16BIT)


        // Push camera uniforms
        sdl.PushGPUVertexUniformData(cb, 0, &cam_constants, size_of(cam_constants))

        // Push model uniforms
        sdl.PushGPUVertexUniformData(cb, 1, &model_constants, size_of(model_constants))

        // storage_buffers := []^sdl.GPUBuffer {
        //         g.constants_camera,
        //         g.constants_model,
        // }
        // sdl.BindGPUVertexStorageBuffers(pass, 0, raw_data(storage_buffers), u32(len(storage_buffers)))

        sdl.DrawGPUIndexedPrimitives(pass, g.index_buffer_len, 1, 0, 0, 0)

        sdl.PushGPUVertexUniformData(cb, 1, &model_constants_2, size_of(model_constants_2))
        sdl.DrawGPUIndexedPrimitives(pass, g.index_buffer_len, 1, 0, 0, 0)

        sdl.EndGPURenderPass(pass)

}


graphics_pass_begin :: proc(cb: ^sdl.GPUCommandBuffer, camera: ^cal.Camera) {
        // Push camera constants to slot 0
        uniform_data := cal.camera_get_uniform_data(camera)
        sdl.PushGPUVertexUniformData(cb, 0, &uniform_data, size_of(uniform_data))
}

// graphics_draw_meshes :: proc(cb: ^sdl.GPUCommandBuffer, mesh_renderers: []cal.Mesh_Render_Info) {
        // Push material constants to slot 1
        // Push mesh constants to slot 2
        // sdl.PushGPUVertexUniformData(cb, 2, )
        // mesh_data := linalg.matrix4_from_trs_f32()
// }

graphics_pass_end :: proc() {
}
