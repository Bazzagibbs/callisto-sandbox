package cal_sandbox

import "core:log"
import "core:time"
import "core:mem"
import cal "callisto"
import cg "callisto/graphics"
import cr "callisto/renderer"

// Temp frame timer
frame_stopwatch: time.Stopwatch = {}
delta_time: f64 = {}
// ================


Color_Vertex :: struct #align 4 {
    position:   [3]f32,
    color:      [3]f32,
}

// UV_Vertex :: struct #align 4 {
//     position:   [3]f32,
//     uv:         [2]f32,
// }

// triangle_vert_buffer :: []UV_Vertex {
//     {{0,     -0.5,   0},     {0.5,   1}},
//     {{0.5,   0.5,    0},     {1,     0}},
//     {{-0.5,  0.5,    0},     {0,     0}},
// }
triangle_verts := []Color_Vertex {
    {{0,     -0.5,   0},     {1, 0, 0}},
    {{0.5,   0.5,    0},     {0, 1, 0}},
    {{-0.5,  0.5,    0},     {0, 0, 1}},
}

color_shader: cg.Shader
triangle_vert_buffer: cg.Vertex_Buffer

main :: proc(){
    // Memory leak detection
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    defer mem.tracking_allocator_destroy(&track)
    context.allocator = mem.tracking_allocator(&track)
    // =====================

    ok := cal.init(); if !ok do return
    defer cal.shutdown()
    context.logger = cal.logger

    color_shader_desc := cg.Shader_Description {
        vertex_shader_path = "callisto/assets/shaders/vert_color.vert.spv",
        fragment_shader_path = "callisto/assets/shaders/vert_color.frag.spv",
        vertex_typeid = typeid_of(Color_Vertex),
    }
    
    ok = cr.create_shader(&color_shader_desc, &color_shader); if !ok do return
    defer cr.destroy_shader(&color_shader)
    ok = cr.create_vertex_buffer(triangle_verts, &triangle_vert_buffer); if !ok do return
    defer cr.destroy_vertex_buffer(&triangle_vert_buffer)

    for cal.should_loop() {
        // Temp frame timer
        delta_time = time.duration_seconds(time.stopwatch_duration(frame_stopwatch))
        time.stopwatch_reset(&frame_stopwatch)
        time.stopwatch_start(&frame_stopwatch)
        // ================

        loop()
        break
    }
    
    // Memory leak detection
    for _, leak in track.allocation_map {
        log.errorf("%v leaked %v bytes\n", leak.location, leak.size)
    }
    for bad_free in track.bad_free_array {
        log.errorf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
    }
    // =====================
}


loop :: proc() {
    // gameplay code here
    cr.cmd_record()

    cr.cmd_present()
    // log.infof("{:2.6f} : {:i}fps", delta_time, int(1 / delta_time))

}
