package callisto_sandbox

import "core:log"
import sdl "vendor:sdl3"
import "core:fmt"


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
