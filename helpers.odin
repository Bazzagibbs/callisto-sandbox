package callisto_sandbox

import "base:runtime"
import "base:intrinsics"
import "core:log"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:math"
import "callisto/config"


// For SDL types, use `check_sdl()` instead for descriptive error messages.
check :: proc {
        check_ok,
        check_ptr,
        check_err,
}

check_ok :: proc (val: bool, loc := #caller_location, expr := #caller_expression) -> (ok: bool) {
        if val {
                return true
        }

        log.error(expr, location = loc)
        when config.BREAKPOINT_ON_CHECK {
                runtime.debug_trap()
        }
        return false
}

// For SDL pointers, use `check_sdl()` instead for descriptive error messages.
check_ptr :: proc (val: ^$T, loc := #caller_location, expr := #caller_expression) -> (ptr: ^T, ok: bool) #optional_ok {
        if val != nil {
                return val, true
        }

        log.error(expr, location = loc)
        when config.BREAKPOINT_ON_CHECK {
                runtime.debug_trap()
        }
        return nil, false
}

check_err :: proc(val: $T, loc := #caller_location, expr := #caller_expression) -> (ok: bool) where intrinsics.type_is_enum(T) || intrinsics.type_is_union(T) {
        if val == {} {
                return true
        }

        log.error("%v -> %v", expr, val, location = loc)
        when config.BREAKPOINT_ON_CHECK {
                runtime.debug_trap()
        }
        return false
}

check_sdl :: proc {
        check_sdl_ok,
        check_sdl_ptr,
}

check_sdl_ok :: proc (val: bool, loc := #caller_location, expr := #caller_expression) -> (ok: bool) { 
        if val {
                return true
        }

        log.errorf("%v: %v", expr, sdl.GetError(), location = loc)
        when config.BREAKPOINT_ON_CHECK {
                runtime.debug_trap()
        }
        return false

}

check_sdl_ptr :: proc (val: ^$T, loc := #caller_location, expr := #caller_expression) -> (ptr: ^T, ok: bool) #optional_ok { 
        if val != nil {
                return val, true
        }

        log.errorf("%v: %v", expr, sdl.GetError(), location = loc)
        when config.BREAKPOINT_ON_CHECK {
                runtime.debug_trap()
        }
        return nil, false
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
