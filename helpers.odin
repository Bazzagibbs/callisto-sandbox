package callisto_sandbox

import "core:log"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:math"


assert_sdl :: proc {
        assert_sdl_bool,
        assert_sdl_ptr,
}

assert_sdl_bool :: proc(assertion: bool, message: string = "", expr := #caller_expression(assertion), location := #caller_location) {
        when !ODIN_DISABLE_ASSERT {
                if !assertion {
                        log.fatal(sdl.GetError(), location = location)
                        if message == "" {
                                panic(expr, location)
                        } else {
                                panic(message, location)
                        }
                }
        }
}


assert_sdl_ptr :: proc(ptr: rawptr, message: string = "", expr := #caller_expression(ptr), location := #caller_location) {
        when !ODIN_DISABLE_ASSERT {
                if ptr == nil {
                        log.fatal(sdl.GetError(), location = location)
                        if message == "" {
                                panic(fmt.tprint(expr, "is nil"), location)
                        } else {
                                panic(message, location)
                        }
                }
        }
}

quaternion_from_yaw_pitch_f32 :: proc "contextless" (yaw, pitch: f32) -> quaternion128 {
	a, b := yaw, pitch

	ca, sa := math.cos(a*0.5), math.sin(a*0.5)
	cb, sb := math.cos(b*0.5), math.sin(b*0.5)

	q: quaternion128
	q.x =  sa*cb
	q.y =  ca*sb
	q.z = -sa*sb
	q.w =  ca*cb
	return q
}

quaternion_from_pitch_yaw_f32 :: proc "contextless" (pitch, yaw: f32) -> quaternion128 {
	a, b := pitch, yaw

	ca, sa := math.cos(a*0.5), math.sin(a*0.5)
	cb, sb := math.cos(b*0.5), math.sin(b*0.5)

	q: quaternion128
	q.x =  sa*cb
	q.y =  ca*sb
	q.z = -sa*sb
	q.w =  ca*cb
	return q
}
