package callisto_sandbox

import "core:math"
import "core:math/linalg"
import cal "callisto"
import "callisto/gpu"


Scene_Memory :: struct {
        test_construct   : cal.Construct,

        test_mesh : cal.Mesh,
        // constructs     : [dynamic]cal.Construct,
        // meshes         : [dynamic]cal.Mesh,
        // materials      : [dynamic]cal.Material,
        // textures       : [dynamic]cal.Texture2D,
        // pipelines      : [dynamic]cal.Shader_Pipeline,
        // mesh_renderers : [dynamic]cal.Mesh_Renderer,

        // GPU (to abstract)
        camera_cbuffer   : gpu.Buffer,
}

Camera_Constants :: struct #align(16) #min_field_align(16) {
        view     : matrix[4,4]f32,
        proj     : matrix[4,4]f32,
        viewproj : matrix[4,4]f32,
}

// cal.scene_load
// cal.construct_load
// cal.mesh_load
// cal.material_load
// cal.texture2d_load

scene_init :: proc(app: ^App_Memory) {
        s := &app.scene_memory

        // construct_info := cal.asset_load(cal.Construct, "meshes/basis")
        // cal.construct_create(s, &construct_info)

        // Load construct + refcount
        // cal.scene_load() // later
        // test_construct, _ := cal.construct_load(asset_id)
}

scene_destroy :: proc(app: ^App_Memory) {
        s := &app.scene_memory

        // Destroy construct + refcount

        // delete(s.meshes)
        // delete(s.materials)
        // delete(s.textures)
        // delete(s.pipelines)
        // delete(s.mesh_renderers)
}


scene_render :: proc(app: ^App_Memory) {
        /*
        s    := &app.scene_memory
        gmem := &app.graphics_memory
        cb   := &gmem.device.immediate_command_buffer

        // Update camera constants
        cam_transform := linalg.matrix4_translate_f32(app.camera_pos) * linalg.matrix4_from_euler_angles_zx(app.camera_yaw, app.camera_pitch)
        cam_view := linalg.inverse(cam_transform)
        cam_proj := cal.matrix4_perspective(60 * math.RAD_PER_DEG, app.camera_aspect, 0.01, 10000)
        cam_viewproj := cam_proj * cam_view

        camera_data := Camera_Constants {
                view     = cam_view,
                proj     = cam_proj,
                viewproj = cam_viewproj,
        }
        gpu.cmd_update_constant_buffer(cb, &s.camera_cbuffer, &camera_data)
        gpu.cmd_set_constant_buffers(cb, {.Vertex, .Fragment}, 1, {&s.camera_cbuffer})


        // Recalculate transforms required by mesh renderers
        cal.construct_recalculate_matrices(&s.test_construct)
        
        // Bucket mesh renderers by render pass -> instanced -> shared material -> shader pipeline
        // Then sort by depth


        bound_material : cal.Reference(cal.Material)

        for &rend in s.mesh_renderers {
                mesh := cal.reference_resolve(&s.meshes, rend.mesh)
                // gpu.cmd_update_constant_buffer()
                // gpu.cmd_set_constant_buffers(cb, {.Vertex, .Fragment}, 3, {}

                for &submesh, i in mesh.submeshes {

                        // Only update gpu state if materials/shaders don't match the previous draw call
                        mat_ref := rend.materials[i]

                        if bound_material != mat_ref {
                                bound_material = mat_ref
                                mat := cal.reference_resolve(&s.materials, mat_ref)

                                pipeline := cal.reference_resolve(&s.pipelines, mat.shader_pipeline)
                                gpu.cmd_set_vertex_shader(cb, &pipeline.vertex_shader)
                                gpu.cmd_set_fragment_shader(cb, &pipeline.fragment_shader)
                                gpu.cmd_set_constant_buffers(cb, {.Vertex, .Fragment}, 2, {&mat.constants})
                        }
                        
                }
        }
        */
}
