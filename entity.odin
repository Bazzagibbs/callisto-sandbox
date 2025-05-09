package callisto_sandbox

import "core:log"
import "core:math"
import "core:strings"
import "core:math/linalg"

import sdl "vendor:sdl3"
import cal "callisto"

// Mesh_Renderer :: struct {
//         transform : cal.Transform,
//         mesh      : Mesh_Data,
//         material  : Material_Data,
// }
//
//
// // Contains submeshes. Each submesh is drawn with a different material slot.
// Mesh_Data :: struct {
//         material_slot_name : [dynamic]string,
//         gpu_position       : [dynamic]^sdl.GPUBuffer,
//         gpu_normal         : [dynamic]^sdl.GPUBuffer,
//         gpu_tangent        : [dynamic]^sdl.GPUBuffer,
//         gpu_tex_coord_0    : [dynamic]^sdl.GPUBuffer,
//         // color, skinning data, etc.
// }
//
//
// Material_Data :: struct {
//         pipeline : ^sdl.GPUGraphicsPipeline,
//         // attachments, uniforms
// }


// Construct :: struct {
//         root_transform : cal.Transform,
//         // mesh_renderers : [dynamic]Mesh_Renderer,
// }

