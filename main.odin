package callisto_sandbox

import "base:runtime"
import "core:os"
import "core:c"
import "core:fmt"
import "core:log"
import "core:time"
import "callisto/config"

import sdl "vendor:sdl3"

import im "callisto/imgui"


App_Data :: struct {
        window        : ^sdl.Window,
        device        : ^sdl.GPUDevice,
        shader        : ^sdl.GPUShader,
        ui_context    : ^im.Context,

        tick_begin    : time.Tick,
        tick_frame    : time.Tick,
        delta         : f32, // Seconds

        graphics_data : Graphics_Data,
        ui_data       : UI_Data,
}



@(export)
callisto_init :: proc(app_data: ^rawptr) -> sdl.AppResult {
        app_data^ = new(App_Data)
        a : ^App_Data = cast(^App_Data)(app_data^)
       

        subsystems := sdl.InitFlags {
                .VIDEO,
                .GAMEPAD,
                // .AUDIO,
        }

        ok := sdl.Init(subsystems)
        assert_sdl(ok)

        sdl.SetHint(sdl.HINT_GPU_DRIVER, "vulkan")


        // WINDOW
        a.window = sdl.CreateWindow("Hello, World", 1920, 1080, {.HIGH_PIXEL_DENSITY})
        assert_sdl(a.window)


        // GPU
        a.device = sdl.CreateGPUDevice({.SPIRV, .MSL, .DXIL}, ODIN_DEBUG, "")
        assert_sdl(a.device)

        ok = sdl.ClaimWindowForGPUDevice(a.device, a.window)
        assert_sdl(ok)

        ok = sdl.SetGPUSwapchainParameters(a.device, a.window, .SDR, .MAILBOX)
        assert_sdl(ok)


        graphics_init(&a.graphics_data, a.device, a.window)

        
        // UI
        a.ui_context, ok = ui_init(a.device, a.window)
        assert(ok)

        // TIME
        a.tick_begin = time.tick_now()
        a.tick_frame = a.tick_begin

        return .CONTINUE
}



@(export)
callisto_quit :: proc(app_data: rawptr, result: sdl.AppResult) {
        a : ^App_Data = (^App_Data)(app_data)

        _ = sdl.WaitForGPUIdle(a.device)
        
        ui_destroy(a.ui_context)

        graphics_destroy(&a.graphics_data, a.device)

        sdl.ReleaseWindowFromGPUDevice(a.device, a.window)
        sdl.DestroyWindow(a.window)
        // sdl.DestroyGPUDevice(a.device) // I don't know where all these leaked resources are coming from

        free(a)
}



@(export)
callisto_event :: proc(app_data: rawptr, event: ^sdl.Event) -> sdl.AppResult {
        a : ^App_Data = cast(^App_Data)app_data

        if ui_process_event(event) {
                return .CONTINUE
        }


        #partial switch event.type {
        case .WINDOW_RESIZED:
                if a.device != nil {
                        graphics_resize(&a.graphics_data, a.device, a.window)
                        log.info("Window resized")
                }

        case .QUIT:
                sdl.Quit()
                return .SUCCESS
        }


        return .CONTINUE
}



@(export)
callisto_loop :: proc(app_data: rawptr) -> sdl.AppResult {
        a : ^App_Data = cast(^App_Data)app_data
        
        // TIME
        tick_now := time.tick_now()
        a.delta = f32(time.duration_seconds(time.tick_diff(a.tick_frame, tick_now)))
        a.tick_frame = tick_now

        // BEGIN GPU
        cb := sdl.AcquireGPUCommandBuffer(a.device)
        rt : ^sdl.GPUTexture
        _ = sdl.WaitAndAcquireGPUSwapchainTexture(cb, a.window, &rt, nil, nil)

        if rt != nil {
                // GRAPHICS
                graphics_draw(&a.graphics_data, cb, rt)

                // UI
                ui_begin(a.ui_context)
                ui_draw(&a.ui_data)
                ui_end(cb, rt)


                _ = sdl.SubmitGPUCommandBuffer(cb)
        }
        // END GPU
        return .CONTINUE
}
