package callisto_sandbox

import "core:log"
import "core:math"
import "core:strings"
import "core:math/linalg"

import sdl "vendor:sdl3"
import cal "callisto"

import "callisto/config"

Entity_Flags :: bit_set[Entity_Flag]
Entity_Flag :: enum {
        Enabled,
        Has_Mesh_Renderer,
}


Entity :: struct {
        flags         : Entity_Flags,
        position      : [3]f32,
        rotation      : quaternion128,
        scale         : [3]f32,
        mesh_renderer : cal.Mesh_Renderer,
}

