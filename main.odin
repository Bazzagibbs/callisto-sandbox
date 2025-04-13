package callisto_sandbox

import "base:runtime"
import "core:os"
import "core:c"
import "core:fmt"
import "core:log"
import "core:time"
import cal "callisto"
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

        scene         : cal.Scene,
}



@(export)
callisto_init :: proc(app_data: ^rawptr) -> sdl.AppResult {
        app_data^ = new(App_Data)
        a : ^App_Data = cast(^App_Data)(app_data^)
        u := &a.ui_data
        g := &a.graphics_data
       

        subsystems := sdl.InitFlags {
                .VIDEO,
                .GAMEPAD,
                // .AUDIO,
        }

        ok := sdl.Init(subsystems)
        assert_sdl(ok)

        sdl.SetHint(sdl.HINT_GPU_DRIVER, "vulkan")


        // WINDOW
        window_flags := sdl.WindowFlags {
                .HIGH_PIXEL_DENSITY,
                .RESIZABLE,
        }
        a.window = sdl.CreateWindow("Hello, World", 1920, 1080, window_flags)
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
        a.ui_context, ok = ui_init(u, a.device, a.window)
        assert(ok)

        // TIME
        a.tick_begin = time.tick_now()
        a.tick_frame = a.tick_begin

        // SCENE
        a.scene = cal.scene_create()
        s := &a.scene

        player_rig := cal.transform_create(s, "player rig")
        cam        := cal.transform_create(s, "camera", player_rig)
        cam2       := cal.transform_create(s, "camera", player_rig)
        door       := cal.transform_create(s, "door")
        door_data := cal.transform_get_data(s, door)
        door_data.editor_state.use_hierarchy_color = true
        door_data.editor_state.hierarchy_color = {0.6, 0.2, 0.2, 1}


        return .CONTINUE
}



@(export)
callisto_quit :: proc(app_data: rawptr, result: sdl.AppResult) {
        a : ^App_Data = (^App_Data)(app_data)
        u := &a.ui_data
        g := &a.graphics_data

        _ = sdl.WaitForGPUIdle(a.device)
       
        cal.scene_destroy(&a.scene)

        ui_destroy(u, a.ui_context)

        graphics_destroy(g, a.device)

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
        framebuffer : ^sdl.GPUTexture
        width, height: u32
        _ = sdl.WaitAndAcquireGPUSwapchainTexture(cb, a.window, &framebuffer, &width, &height)

        if framebuffer != nil {
                g := &a.graphics_data
                u := &a.ui_data

                // GRAPHICS
                if a.ui_data.scene_view_open {
                        graphics_draw(g, cb, g.render_texture)
                }

                u.scene_view_texture = g.render_texture

                scene_view_dimensions_old := u.scene_view_dimensions
                
                // UI
                ui_begin(u, a.ui_context)
                ui_draw(a, u)
                ui_end(u, cb, framebuffer)

                // Check if UI scene view window has changed size, rebuild render texture
                if a.ui_data.scene_view_open && scene_view_dimensions_old != a.ui_data.scene_view_dimensions {
                        dims := a.ui_data.scene_view_dimensions
                        graphics_scene_view_resize(g, a.device, {u32(dims.x), u32(dims.y)})
                }


                _ = sdl.SubmitGPUCommandBuffer(cb)
        }
        // END GPU
        return .CONTINUE
}
