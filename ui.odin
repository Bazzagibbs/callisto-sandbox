package callisto_sandbox

import "core:log"
import "core:math"

import sdl "vendor:sdl3"

import "callisto/fonts"
import im "callisto/imgui"
import im_sdl "callisto/imgui/imgui_impl_sdl3"
import im_sdlgpu "callisto/imgui/imgui_impl_sdlgpu3"



ui_init :: proc(device: ^sdl.GPUDevice, window: ^sdl.Window) -> (ctx: ^im.Context, ok: bool) {
        im.CHECKVERSION()

        ctx = im.CreateContext()
        io := im.GetIO()
        io.ConfigFlags += {
                .NavEnableKeyboard, 
                .NavEnableGamepad,
                .DockingEnable,
        }

        ui_load_font(fonts.roboto_regular, 16, window)

        im.StyleColorsDark()

        ok = im_sdl.InitForSDLGPU(window)
        
        init_info := im_sdlgpu.InitInfo {
                Device            = device,
                ColorTargetFormat = sdl.GetGPUSwapchainTextureFormat(device, window),
                MSAASamples       = ._1,
        }

        ok = im_sdlgpu.Init(&init_info)


        return
}



// Window is used to calculate DPI scaling
ui_load_font :: proc(data: []u8, font_size: f32, window: ^sdl.Window) -> ^im.Font {
        font_factor := sdl.GetWindowDisplayScale(window)

        io := im.GetIO()
        font := im.FontAtlas_AddFontFromMemoryTTF(io.Fonts, raw_data(data), i32(len(data)), math.floor(font_size * font_factor))
        im.FontAtlas_Build(io.Fonts)

        return font
}



ui_begin :: proc(ctx: ^im.Context) {
        im.SetCurrentContext(ctx)
        im_sdlgpu.NewFrame()
        im_sdl.NewFrame()
        im.NewFrame()
}



// Add UI render pass to the provided command buffer. The command buffer must still be submitted.
ui_end :: proc(cb: ^sdl.GPUCommandBuffer, render_target: ^sdl.GPUTexture) {
        im.Render()
        ui_data := im.GetDrawData()
        im_sdlgpu.PrepareDrawData(ui_data, cb)
                
        target_info := sdl.GPUColorTargetInfo {
                texture               = render_target,
                mip_level             = 0,
                layer_or_depth_plane  = 0,
                clear_color           = {0.2, 0.2, 0.2, 1},
                load_op               = .CLEAR,
                store_op              = .STORE,
                resolve_texture       = nil,
                resolve_mip_level     = 0,
                resolve_layer         = 0,
                cycle                 = false,
                cycle_resolve_texture = false,
        }
        ui_pass := sdl.BeginGPURenderPass(cb, &target_info, 1, nil)
        im_sdlgpu.RenderDrawData(ui_data, cb, ui_pass)
        sdl.EndGPURenderPass(ui_pass)
}



ui_destroy :: proc(ctx: ^im.Context) {
        im_sdl.Shutdown()
        im_sdlgpu.Shutdown()
        // im.DestroyContext(ctx) // ?? crashes when uncommented
}



ui_process_event :: proc(event: ^sdl.Event) -> bool {
        return im_sdl.ProcessEvent(event)
}



ui_draw :: proc(a: ^App_Data) {
        im.DockSpaceOverViewport(0, im.GetMainViewport())
        if im.BeginMainMenuBar() {
                if im.BeginMenu("File") {
                        im.EndMenu()
                }

                im.EndMainMenuBar()
        }
                
        if im.Begin("Level Hierarchy", &a.ui_hierarchy_open) {
                im.End()
        }

        if im.Begin("Inspector", &a.ui_inspector_open) {
                im.End()
        }

        im.ShowDemoWindow()
}
