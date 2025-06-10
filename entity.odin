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
        Has_Mesh_Renderer,
}


// This struct is defined per-project
Entity :: struct {
        using base    : cal.Entity_Base,
        flags         : Entity_Flags,
        position      : [3]f32,
        rotation      : cal.Rotation,
        scale         : [3]f32 `cal_edit:"reset=one"`,
        mesh_renderer : cal.Mesh_Renderer,
        test_color    : [4]f32 `cal_edit:"color,reset=normal"`,
        test_int      : int `cal_edit:"reset=one"`,
}


