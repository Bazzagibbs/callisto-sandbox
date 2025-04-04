package callisto_sandbox

import sdl "vendor:sdl3"
import "core:slice"
import "core:mem"

Graphics_Data :: struct {
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
        texture          : ^sdl.GPUTexture, // TODO
        sampler          : ^sdl.GPUSampler,

        // TRANSFER
        upload_buffer    : ^sdl.GPUTransferBuffer,

        // RENDER STATE
        depth_texture    : ^sdl.GPUTexture,
}


graphics_init :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice, resolution: [2]u32) {
        // Transfer read-only data to GPU
        cb := sdl.AcquireGPUCommandBuffer(device)

        copy_pass := sdl.BeginGPUCopyPass(cb)

        // Meshes
        pos_data := [][3]f32 {
                {-0.5, 0, 0.5},
                {-0.5, 0, -0.5,},
                {0.5, 0, -0.5},
                {0.5, 0, 0.5},
        }
        pos_info := sdl.GPUBufferCreateInfo {
                usage = {.VERTEX},
                size  = u32(slice.size(pos_data)),
        }
        g.vb_position = sdl.CreateGPUBuffer(device, pos_info)
        graphics_upload(device, copy_pass, pos_data, g.vb_position)

       
        uv_data := [][2]f16 {
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
        graphics_upload(device, copy_pass, uv_data, g.vb_tex_coord_0)
        

        index_data := []u16 {
                0, 2, 1,
                0, 3, 2,
        }
        index_info := sdl.GPUBufferCreateInfo {
                usage = {.INDEX},
                size  = u32(slice.size(index_data)),
        }
        g.index_buffer = sdl.CreateGPUBuffer(device, index_info)
        graphics_upload(device, copy_pass, index_data, g.index_buffer)
        g.index_buffer_len = u32(len(index_data))



        sampler_info := sdl.GPUSamplerCreateInfo {
                min_filter        = .LINEAR,
                mag_filter        = .LINEAR,
                mipmap_mode       = .LINEAR,
                address_mode_u    = .CLAMP_TO_EDGE,
                address_mode_v    = .CLAMP_TO_EDGE,
                address_mode_w    = .CLAMP_TO_EDGE,
                mip_lod_bias      = 0,
                max_anisotropy    = max(f32),
                min_lod           = 0,
                max_lod           = max(f32),
                enable_anisotropy = true,
                enable_compare    = false,

        }
        g.sampler = sdl.CreateGPUSampler(device, sampler_info)


        depth_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = .D32_FLOAT,
                usage                = {.DEPTH_STENCIL_TARGET},
                width                = resolution.x,
                height               = resolution.y,
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = ._1, // MSAA?
        }
        g.depth_texture = sdl.CreateGPUTexture(device, depth_info)
        

        // Create shaders
        // sdl.CreateGPUShader(

        // Create pipeline
        // pipeline_info := sdl.GPUGraphicsPipelineCreateInfo {
        //         vertex_shader   = g.vertex_shader,
        //         fragment_shader = g.fragment_shader,
        // }
        // g.pipeline = sdl.CreateGPUGraphicsPipeline(device, pipeline_info)

        // Load vertex/index data from model
        // Load texture

}

graphics_upload :: proc(device: ^sdl.GPUDevice, pass: ^sdl.GPUCopyPass, data: $T/[]$E, dest_buffer: ^sdl.GPUBuffer) {
        staging_buffer_info := sdl.GPUTransferBufferCreateInfo {
                usage = .UPLOAD,
                size = u32(slice.size(data)),
        }
        staging_buffer := sdl.CreateGPUTransferBuffer(device, staging_buffer_info)

        mapped := sdl.MapGPUTransferBuffer(device, staging_buffer, false)
        mem.copy(mapped, raw_data(data), slice.size(data))
        sdl.UnmapGPUTransferBuffer(device, staging_buffer)
        
        sdl.UploadToGPUBuffer(pass, {staging_buffer, 0},  {dest_buffer, 0, u32(slice.size(data))}, false)

        sdl.ReleaseGPUTransferBuffer(device, staging_buffer) // This might need to be called after ending copy pass
}


graphics_resize :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice, resolution: [2]u32) {
        _ = sdl.WaitForGPUIdle(device)
        sdl.ReleaseGPUTexture(device, g.depth_texture)
        depth_info := sdl.GPUTextureCreateInfo {
                type                 = .D2,
                format               = .D32_FLOAT,
                usage                = {.DEPTH_STENCIL_TARGET},
                width                = resolution.x,
                height               = resolution.y,
                layer_count_or_depth = 1,
                num_levels           = 1,
                sample_count         = ._1, // MSAA?
        }
        g.depth_texture = sdl.CreateGPUTexture(device, depth_info)
}



graphics_destroy :: proc(g: ^Graphics_Data, device: ^sdl.GPUDevice) {
        sdl.ReleaseGPUSampler(device, g.sampler)
        sdl.ReleaseGPUTexture(device, g.depth_texture)

        sdl.ReleaseGPUBuffer(device, g.vb_position)
        sdl.ReleaseGPUBuffer(device, g.vb_tex_coord_0)
        sdl.ReleaseGPUBuffer(device, g.index_buffer)
}



graphics_draw :: proc(g: ^Graphics_Data, cb: ^sdl.GPUCommandBuffer, rt: ^sdl.GPUTexture) {
        rt_info := sdl.GPUColorTargetInfo {
                texture              = rt,
                mip_level            = 0,
                layer_or_depth_plane = 0,
                clear_color          = {0.3, 0.3, 0.3, 1},
                load_op              = .CLEAR,
                store_op             = .STORE,
                cycle                = true, // Maybe don't cycle the swapchain texture
        }

        dt_info := sdl.GPUDepthStencilTargetInfo {
                texture          = g.depth_texture,
                clear_depth      = 1,
                load_op          = .CLEAR,
                store_op         = .STORE,
                stencil_load_op  = .DONT_CARE,
                stencil_store_op = .DONT_CARE,
                cycle            = true,
                clear_stencil    = 0,
        }

        // pass := sdl.BeginGPURenderPass(
        //         command_buffer            = cb,
        //         color_target_infos        = &rt_info,
        //         num_color_targets         = 1,
        //         depth_stencil_target_info = &dt_info
        // )
        //
        // sdl.BindGPUGraphicsPipeline(pass, g.pipeline)
        //
        //
        // vert_buffer_bindings := []sdl.GPUBufferBinding {
        //         {g.vb_position, 0},
        //         {g.vb_tex_coord_0, 0},
        // }
        // sdl.BindGPUVertexBuffers(pass, 0, raw_data(vert_buffer_bindings), u32(len(vert_buffer_bindings)))
        //
        //
        // texture_sampler_bindings := []sdl.GPUTextureSamplerBinding {
        //         {g.texture, g.sampler},
        // }
        // sdl.BindGPUFragmentSamplers(pass, 0, raw_data(texture_sampler_bindings), u32(len(texture_sampler_bindings)))
        //
        // index_buffer_binding := sdl.GPUBufferBinding {g.index_buffer, 0}        
        // sdl.BindGPUIndexBuffer(pass, index_buffer_binding, ._16BIT)
        //
        //
        // // Push camera uniforms
        // // sdl.PushGPUVertexUniformData
        // // Push model uniforms
        //
        // sdl.DrawGPUIndexedPrimitives(pass, g.index_buffer_len, 1, 0, 0, 0)
        //
        // sdl.EndGPURenderPass(pass)

}



