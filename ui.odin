package callisto_sandbox

import "core:log"
import "core:math"
import "core:strings"
import "core:math/linalg"

import sdl "vendor:sdl3"

import cal "callisto"
import "callisto/fonts"
import im "callisto/imgui"
import im_sdl "callisto/imgui/imgui_impl_sdl3"
import im_sdlgpu "callisto/imgui/imgui_impl_sdlgpu3"

USER_EVENT_REDRAW :: 128


UI_Data :: struct {
        device                : ^sdl.GPUDevice, // < Not owned by this struct
        sampler               : ^sdl.GPUSampler,

        force_no_consume_event : bool,
        scene_view_hovered    : bool,
        scene_view_open       : bool,
        scene_view_dimensions : [2]f32,
        scene_view_texture    : ^sdl.GPUTexture, // < Not owned by this struct
        scene_view_textureid  : sdl.GPUTextureSamplerBinding,
        event_counter         : int,
}


ui_init :: proc(u: ^UI_Data, device: ^sdl.GPUDevice, window: ^sdl.Window) -> (ctx: ^im.Context, ok: bool) {
        u.device = device
        
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


        sampler_info := sdl.GPUSamplerCreateInfo {
                min_filter        = .LINEAR,
                mag_filter        = .LINEAR,
                mipmap_mode       = .LINEAR,
                address_mode_u    = .CLAMP_TO_EDGE,
                address_mode_v    = .CLAMP_TO_EDGE,
                address_mode_w    = .CLAMP_TO_EDGE,
                mip_lod_bias      = 0,
                max_anisotropy    = 1,
                min_lod           = 0,
                max_lod           = max(f32),
                enable_anisotropy = false,
                enable_compare    = false,
        }
        u.sampler = sdl.CreateGPUSampler(device, sampler_info)


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



ui_begin :: proc(u: ^UI_Data, ctx: ^im.Context) {
        im.SetCurrentContext(ctx)
        im_sdlgpu.NewFrame()
        im_sdl.NewFrame()
        im.NewFrame()
}



// Add UI render pass to the provided command buffer. The command buffer must still be submitted.
ui_end :: proc(u: ^UI_Data, cb: ^sdl.GPUCommandBuffer, render_target: ^sdl.GPUTexture) {
        im.Render()
        ui_data := im.GetDrawData()
        im_sdlgpu.PrepareDrawData(ui_data, cb)
                
        target_info := sdl.GPUColorTargetInfo {
                texture               = render_target,
                mip_level             = 0,
                layer_or_depth_plane  = 0,
                // clear_color           = {0.2, 0.2, 0.2, 1},
                load_op               = .LOAD,
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

        if u.event_counter > 0 {
                u.event_counter -= 1

                event := sdl.Event {
                        user = {
                                type = .USER,
                                code = USER_EVENT_REDRAW,
                        }
                }
                _ = sdl.PushEvent(&event)
        }
}



ui_destroy :: proc(u: ^UI_Data, ctx: ^im.Context) {
        sdl.ReleaseGPUSampler(u.device, u.sampler)
        im_sdl.Shutdown()
        im_sdlgpu.Shutdown()
        // im.DestroyContext(ctx) // ?? crashes when uncommented
}



ui_process_event :: proc(u: ^UI_Data, event: ^sdl.Event) -> (consumed: bool) {
        // USER redraw events are used to make sure animations are finished before waiting on the queue.
        // Also don't decrement user event counter if scene view is being used.
        if event.type != .USER || event.user.code != USER_EVENT_REDRAW || u.force_no_consume_event {
                u.event_counter = 3
        }

        im_sdl.ProcessEvent(event)

        if u.force_no_consume_event {
                return false
        }

        #partial switch event.type {
        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP, .MOUSE_MOTION, .MOUSE_WHEEL:
                return im.GetIO().WantCaptureMouse

        case .KEY_DOWN, .KEY_UP, .TEXT_INPUT:
                return im.GetIO().WantCaptureKeyboard
        }

        return false
}



ui_draw :: proc(a: ^App_Data, u: ^UI_Data) {
        im.DockSpaceOverViewport(0, im.GetMainViewport(), {})
        if im.BeginMainMenuBar() {
                if im.BeginMenu("File") {
                        // Add open/save etc.
                        im.EndMenu()
                }

                im.EndMainMenuBar()
        }
       

        open: bool

        hierarchy_window_flags : im.WindowFlags
        if a.scene.editor_state.dirty {
                hierarchy_window_flags += {.UnsavedDocument}
        }
        if im.Begin("Hierarchy", &open, hierarchy_window_flags) {
                ui_draw_scene_hierarchy(&a.scene)
        }
        im.End()


        if im.Begin("Inspector", &open) {
                ui_draw_inspector(&a.scene)
        }
        im.End()


        // Scene view window
        u.scene_view_hovered = false
        im.SetNextWindowSizeConstraints({200, 200}, {max(f32), max(f32)})
        im.PushStyleVarImVec2(.WindowPadding, {0, 0})
        im.PushStyleVar(.WindowBorderSize, 0)
        if im.Begin("Scene", &open, {}) {
                if im.IsWindowHovered() {
                        u.scene_view_hovered = true
                        im.SetNextFrameWantCaptureMouse(false)
                        im.SetNextFrameWantCaptureKeyboard(false)
                }

                u.scene_view_open = true
                // Get dimensions of scene window to pass to scene next frame
                min := im.GetWindowContentRegionMin()
                max := im.GetWindowContentRegionMax()
                u.scene_view_dimensions = max - min

                // This pointer must still be valid in ui_end(), store it in app data
                u.scene_view_textureid = sdl.GPUTextureSamplerBinding {
                        texture = u.scene_view_texture,
                        sampler = u.sampler,
                }
                im.Image(im.TextureID(uintptr(&u.scene_view_textureid)), u.scene_view_dimensions)

        }  else {
                u.scene_view_open = false
        }


        im.End()
        im.PopStyleVar(2)

        // im.ShowDemoWindow()


}



ui_draw_scene_hierarchy :: proc(s: ^cal.Scene) {
        for root_node in s.transform_roots {
                draw_transform_node(s, root_node)
        }

        draw_transform_node :: proc(s: ^cal.Scene, transform: cal.Transform) {
                data := cal.transform_get_data(s, transform)
                flags : im.TreeNodeFlags = { .OpenOnArrow, .OpenOnDoubleClick, .NavLeftJumpsBackHere, .SpanFullWidth }

                im.PushIDInt(i32(transform))

                if len(data.children) == 0 {
                        flags += {.Leaf }
                }
                
                if s.editor_state.transform_selected_latest == transform {
                        flags += {.Selected}
                }

                if data.editor_state.use_hierarchy_color {
                        im.PushStyleColorImVec4(im.Col.Button, data.editor_state.hierarchy_color)
                }

                node_open := im.TreeNodeExStr("", flags, "%s", strings.unsafe_string_to_cstring(data.name))

                if data.editor_state.use_hierarchy_color {
                        im.PopStyleColor()
                }

                // Only select hierarchy node if the toggle arrow wasn't pressed
                if im.IsItemFocused() {
                        s.editor_state.transform_selected_latest = transform
                }


                if node_open {
                        for child in data.children {
                                draw_transform_node(s, child)
                        }


                        im.TreePop()
                }

                im.PopID()

        }
}


ui_draw_inspector :: proc(s: ^cal.Scene) {
        if s.editor_state.transform_selected_latest == cal.TRANSFORM_NONE {
                return
        }
        
        // im.TextUnformatted(strings.unsafe_string_to_cstring(cal.transform_get_name(s, s.editor_state.transform_selected_latest)))
        ui_draw_inspector_name(s, s.editor_state.transform_selected_latest)
        ui_draw_inspector_transform(s, s.editor_state.transform_selected_latest)
        // Add inspector panels here
}


ui_draw_inspector_name :: proc(s: ^cal.Scene, t: cal.Transform) {
        // TODO wrap this for string builder
        buf : [128]u8
        copy(buf[:], cal.transform_get_name(s, t))
        buf[127] = 0

        input_result := im.InputText("Name", cstring(&buf[0]), len(buf) - 1, {.EnterReturnsTrue}) 

        if im.IsItemDeactivatedAfterEdit() {
                if input_result {
                        log.info("Set name:", cstring(&buf[0]))
                        cal.transform_set_name(s, t, string(buf[:]))
                }
        }
}

ui_draw_inspector_transform :: proc(s: ^cal.Scene, t: cal.Transform) {
        if im.TreeNodeEx("Transform", {.DefaultOpen, .SpanFullWidth}) {

                // POSITION 
                {
                        temp_pos := cal.transform_get_local_position(s, t)
                        if im.DragFloat3("Position", &temp_pos, v_speed = 0.1, flags = {}) {
                                cal.transform_set_local_position(s, t, temp_pos)
                        }

                        if im.IsItemDeactivatedAfterEdit() {
                                log.info("Set local position:", cal.transform_get_name(s, t), ":", temp_pos)
                                cal.scene_set_dirty(s)
                                // TODO: commit to undo history
                        }
                }


                // ROTATION - Inspector is in euler degrees
                {
                        temp_rot_quat := cal.transform_get_local_rotation(s, t)
                        temp_rot_eul : [3]f32
                        temp_rot_eul.x, temp_rot_eul.y, temp_rot_eul.z = linalg.euler_angles_from_quaternion_f32(temp_rot_quat, .XYZ) // Euler order might need to change when I decide on forward/up axes
                        temp_rot_eul *= linalg.DEG_PER_RAD
                        if im.DragFloat3("Rotation", &temp_rot_eul, v_speed = 0.1, flags = {}) {
                                temp_rot_eul *= linalg.RAD_PER_DEG
                                temp_rot_quat = linalg.quaternion_from_euler_angles_f32(expand_values(temp_rot_eul), .XYZ)
                                cal.transform_set_local_rotation(s, t, temp_rot_quat)
                        }

                        if im.IsItemDeactivatedAfterEdit() {
                                log.info("Set local rotation:", cal.transform_get_name(s, t), ":", temp_rot_eul)
                                cal.scene_set_dirty(s)
                                // TODO: commit to undo history
                        }
                }

                // SCALE
                {
                        temp_scale := cal.transform_get_local_scale(s, t)
                        if im.DragFloat3("Scale", &temp_scale, v_speed = 0.1, flags = {}) {
                                cal.transform_set_local_scale(s, t, temp_scale)
                        }

                        if im.IsItemDeactivatedAfterEdit() {
                                log.info("Set local scale:", cal.transform_get_name(s, t), ":", temp_scale)
                                cal.scene_set_dirty(s)
                                // TODO: commit to undo history
                        }
                }


                im.TreePop()
        }
}


