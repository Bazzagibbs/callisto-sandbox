package callisto_sandbox

import "core:log"
import "core:time"
import "core:mem"
import "core:math/linalg"
import "core:math"
import "core:os"
import cal "callisto"
import "callisto/input"
import cg "callisto/graphics"
import "callisto/config"
import "callisto/asset"
import "callisto/debug"

// Temp frame timer
frame_stopwatch: time.Stopwatch = {}
delta_time: f32 = {}
delta_time_f64: f64 = {}
// ================

render_pass_uniform_data : cg.Render_Pass_Uniforms = {
    view        = cal.MAT4_IDENTITY,
    proj        = cal.MAT4_IDENTITY,
    viewproj    = cal.MAT4_IDENTITY,
}

engine              : cal.Engine_Context

geo_meshes          : []cg.Mesh
// matcap_shader       : cg.Shader
// matcap_material     : cg.Material
// matcap_texture      : cg.Texture
opaque_shader       :cg.Shader

main :: proc(){
    
    when ODIN_DEBUG {
        context.logger = debug.create_logger()
        defer debug.destroy_logger(context.logger)

        track := debug.create_tracking_allocator()
        context.allocator = mem.tracking_allocator(&track)
        defer debug.destroy_tracking_allocator(&track)
    }

    when config.DEBUG_PROFILER_ENABLED {
        debug.create_profiler()
        defer debug.destroy_profiler()
    }
    
    run_app()
}

run_app :: proc() -> (ok: bool) {
    debug.profile_scope()
    
    cal.init(&engine) or_return
    defer cal.shutdown(&engine)


    // Load mesh assets
    // ////////////////
    mesh_paths := []string {
        "resources/test/Suzanne.gali",
        // "resources/test/LanternPole_Body.gali",
        // "resources/test/LanternPole_Chain.gali",
        // "resources/test/LanternPole_Lantern.gali",
    }

    mesh_assets := make([]asset.Mesh, len(mesh_paths))
    defer delete(mesh_assets)

    for mesh_path, i in mesh_paths {
        mesh_assets[i] = asset.load(asset.Mesh, mesh_path)
        // asset.load(asset.Mesh, mesh_uuid)
    }

    defer {
        for _, i in mesh_assets {
            mesh_asset := &mesh_assets[i]
            asset.delete_mesh(mesh_asset)
        }
    }
    // ////////////////

    
    // Create renderable meshes
    ////////////////////////
    geo_meshes = make([]cg.Mesh, len(mesh_assets))
    defer delete(geo_meshes)

    for _, i in mesh_assets {
        mesh_asset := &mesh_assets[i]
        geo_meshes[i] = cg.create_static_mesh(mesh_asset) or_return
    }
    defer {
        for geo_mesh in geo_meshes {
            cg.destroy_static_mesh(geo_mesh)
        }
    }
    // ////////////////////////


    // Create material resources
    // /////////////////////////
    // matcap_shader_desc := cg.Shader_Description { // auto generate at shader compile time?
        // material_buffer_typeid   = typeid_of(Uniform_Buffer_Object),
        // cull_mode               = .NONE,
    // }
    // vertex_shader_path      = "callisto/resources/shaders/opaque.vert.spv",
    // fragment_shader_path    = "callisto/resources/shaders/opaque.frag.spv",

    // matcap_shader_desc.vertex_shader_data, _   = os.read_entire_file_from_filename("callisto/resources/shaders/opaque.vert.spv")
    // matcap_shader_desc.fragment_shader_data, _ = os.read_entire_file_from_filename("callisto/resources/shaders/opaque.frag.spv")
    // matcap_shader_desc.vertex_shader_data, _   = os.read_entire_file_from_filename("callisto/resources/shaders/matcap.vert.spv")
    // matcap_shader_desc.fragment_shader_data, _ = os.read_entire_file_from_filename("callisto/resources/shaders/matcap.frag.spv")
    // defer delete(matcap_shader_desc.vertex_shader_data)
    // defer delete(matcap_shader_desc.fragment_shader_data)

    // matcap_shader = cg.create_shader(&matcap_shader_desc) or_return
    // defer cg.destroy_shader(matcap_shader)
    //
    // matcap_material = cg.create_material(matcap_shader) or_return
    // defer cg.destroy_material(matcap_material)
    //
    // matcap_texture_desc := cg.Texture_Description {
    //     image_path = "callisto/resources/textures/matcap/png/basic_1.png",
    //     // image_path = "callisto/resources/textures/matcap/png/check_normal+y.png",
    //     color_space = .SRGB,
    // }
    // matcap_texture = cg.create_texture(&matcap_texture_desc) or_return
    // defer cg.destroy_texture(matcap_texture)

    // cg.set_material_texture(matcap_material, matcap_texture, 1)
    

    // tri_shader_desc := cg.Shader_Description {
    //     vertex_shader_data = #load("callisto/resources/shaders/triangle.vert.spv"),
    //     fragment_shader_data = #load("callisto/resources/shaders/triangle.frag.spv"),
    //     // cull_mode = .NONE,
    // }
    // tri_shader = cg.create_shader(&tri_shader_desc) or_return
    // defer {
    //     cg.wait_until_idle()
    //     cg.destroy_shader(tri_shader)
    // }

    opaque_shader_desc := cg.Shader_Description {
        // material_uniforms_typeid    = typeid_of(Uniform_Buffer_Object),
        vertex_shader_data          = #load("callisto/resources/shaders/opaque.vert.spv"),
        fragment_shader_data        = #load("callisto/resources/shaders/opaque.frag.spv"),
        // cull_mode                   = .NONE,
    }
    opaque_shader = cg.create_shader(&opaque_shader_desc) or_return
    defer {
        cg.wait_until_idle()
        cg.destroy_shader(opaque_shader)
    }

    // /////////////////////////


    // Create camera
    // /////////////
    camera_transform := linalg.matrix4_translate_f32({0, 0, -10})

    aspect_ratio := f32(config.WINDOW_WIDTH) / f32(config.WINDOW_HEIGHT)
    render_pass_uniform_data.view = linalg.matrix4_inverse_f32(camera_transform)
    render_pass_uniform_data.proj = linalg.matrix4_perspective_f32(linalg.to_radians(f32(50)), aspect_ratio, 0.1, 10000, false)
    render_pass_uniform_data.viewproj = render_pass_uniform_data.view * render_pass_uniform_data.proj
    // /////////////


    // GAME LOOP
    // /////////
    for cal.should_loop() {
        // Frame timer
        delta_time_f64 = time.duration_seconds(time.stopwatch_duration(frame_stopwatch))
        delta_time = f32(delta_time_f64)
        time.stopwatch_reset(&frame_stopwatch)
        time.stopwatch_start(&frame_stopwatch)

        loop()
    }
    // /////////

    return true
}

blue : f32 = 0

loop :: proc() {
    debug.profile_scope()
    
    // Blue pulse over time
    blue += 0.5 * delta_time
    blue = math.wrap(blue, 1)
    cg.set_clear_color({0, 0, blue, 1})
    // ////////////////////
    
    // geo_uniform_data.model *= linalg.matrix4_rotate_f32(delta_time, linalg.VECTOR3F32_Y_AXIS)

    // cg.upload_uniforms_material(matcap_material, &geo_uniform_data)

    cg.upload_uniforms_render_pass(/*render_pass,*/ &render_pass_uniform_data)

    cg.cmd_begin_graphics()
    cg.cmd_bind_uniforms_render_pass(/*render_pass*/)
    cg.cmd_begin_render_pass()
    
        // cg.cmd_bind_uniforms_material()
        cg.cmd_bind_shader(opaque_shader)

        for mesh in geo_meshes {
            // cg.cmd_bind_uniforms_instance() // Should only be called internally once models/mats are implemented
            cg.cmd_draw_mesh(mesh)
        }

    cg.cmd_end_render_pass()
    cg.cmd_end_graphics()

    cg.cmd_submit_graphics()

    cg.cmd_present()

    // 
    // log.infof("{:2.6f} : {:i}fps", delta_time, int(1 / delta_time))
    // log.info(input.get_key(.Space))

}

