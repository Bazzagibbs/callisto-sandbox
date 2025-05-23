package callisto_sandbox

import "base:runtime"
import "core:os"
import "core:c"
import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import "core:math/linalg"
import cal "callisto"
import circle "callisto/circular_buffer"
import "callisto/config"

import sdl "vendor:sdl3"

import im "callisto/imgui"

import "callisto/editor/ufbx"


App_Data :: struct {
        window        : ^sdl.Window,
        device        : ^sdl.GPUDevice,
        shader        : ^sdl.GPUShader,
        ui_context    : ^im.Context,

        tick_begin    : time.Tick,
        tick_frame    : time.Tick,
        delta         : f32, // Seconds
        time_accumulated: f32,

        graphics_data : Graphics_Data,
        ui_data       : UI_Data,

        scene         : cal.Scene,

        camera_yaw_pitch             : [2]f32,
        has_camera_control           : bool,
        mouse_delta                  : [2]f32,
        mouse_pos_pre_camera_control : [2]f32,
        directional_input            : bit_set[Direction],
        camera_boost : bool,
}

Direction :: enum {
        Forward,
        Backward,
        Left,
        Right,
        Up,
        Down,
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
        sdl.SetHint(sdl.HINT_MAIN_CALLBACK_RATE, "waitevent")


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

        
        // Load UFBX hierarchy only
        fbx_data := #load("res/meshes/PineTree_Autumn_3.fbx")
        fbx_err : ufbx.Error
        opts := ufbx.Load_Opts {
                ignore_all_content = true,
                target_unit_meters = 1,
        }
        fbx_scene := ufbx.load_memory(raw_data(fbx_data), len(fbx_data), nil, &fbx_err)
        assert(fbx_err.type == .NONE)
        defer ufbx.free_scene(fbx_scene)

        add_ufbx_node_recursive(s, fbx_scene.root_node)

        add_ufbx_node_recursive :: proc(s: ^cal.Scene, unode: ^ufbx.Node, parent := cal.TRANSFORM_NONE) {
                transform := cal.transform_create(s, unode.element.name, parent)
                
                tl := unode.local_transform.translation
                ro := unode.local_transform.rotation
                sc := unode.local_transform.scale

                quat : quaternion128
                quat.x = f32(ro.x)
                quat.y = f32(ro.y)
                quat.z = f32(ro.z)
                quat.w = f32(ro.w)

                cal.transform_set_local_position(s, transform, {f32(tl.x), f32(tl.y), f32(tl.z)})
                cal.transform_set_local_rotation(s, transform, quat)
                cal.transform_set_local_scale(s, transform, {f32(sc.x), f32(sc.y), f32(sc.z)})

                for child in unode.children {
                        add_ufbx_node_recursive(s, child, transform)
                }
        }
        

        g.camera.position = {0, 0, -5}

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
        
        if ui_process_event(&a.ui_data, event) {
                return .CONTINUE
        }
        // ui_process_event(&a.ui_data, event)


        #partial switch event.type {
        case .WINDOW_RESIZED:
                if a.device != nil {
                        graphics_resize(&a.graphics_data, a.device, a.window)
                        log.info("Window resized")
                }

        case .QUIT:
                sdl.Quit()
                return .SUCCESS

        case .MOUSE_BUTTON_DOWN:
                // Capture for editor window
                e := &event.button
                if a.ui_data.scene_view_hovered && e.button == sdl.BUTTON_RIGHT {
                        a.has_camera_control = true
                        a.ui_data.force_no_consume_event = true
                        // _ = sdl.SetWindowMouseGrab(a.window, true)
                        _ = sdl.SetWindowRelativeMouseMode(a.window, true)
                        _ = sdl.GetMouseState(&a.mouse_pos_pre_camera_control.x, &a.mouse_pos_pre_camera_control.y)
                }

        case .MOUSE_BUTTON_UP:
                e := &event.button
                if a.has_camera_control && e.button == sdl.BUTTON_RIGHT {
                        a.has_camera_control = false
                        a.ui_data.force_no_consume_event = false
                        sdl.WarpMouseInWindow(a.window, a.mouse_pos_pre_camera_control.x, a.mouse_pos_pre_camera_control.y)
                        _ = sdl.SetWindowRelativeMouseMode(a.window, false)
                        // _ = sdl.SetWindowMouseGrab(a.window, false)
                }

        case .MOUSE_MOTION:
                // e := event.motion
                // a.mouse_delta = {e.xrel, e.yrel} // Use sdl.GetRelativeMouseState() instead
                

        case .KEY_DOWN:
                e := event.key
                switch e.key {
                case sdl.K_W:
                        a.directional_input += {.Forward}
                case sdl.K_S:
                        a.directional_input += {.Backward}
                case sdl.K_A:
                        a.directional_input += {.Left}
                case sdl.K_D:
                        a.directional_input += {.Right}
                case sdl.K_Q:
                        a.directional_input += {.Down}
                case sdl.K_E:
                        a.directional_input += {.Up}

                case sdl.K_LSHIFT:
                        a.camera_boost = true
                }
        
        case .KEY_UP:
                e := event.key
                switch e.key {
                case sdl.K_W:
                        a.directional_input -= {.Forward}
                case sdl.K_S:
                        a.directional_input -= {.Backward}
                case sdl.K_A:
                        a.directional_input -= {.Left}
                case sdl.K_D:
                        a.directional_input -= {.Right}
                case sdl.K_Q:
                        a.directional_input -= {.Down}
                case sdl.K_E:
                        a.directional_input -= {.Up}
                
                case sdl.K_LSHIFT:
                        a.camera_boost = false
                }

        }



        return .CONTINUE
}



@(export)
callisto_loop :: proc(app_data: rawptr) -> sdl.AppResult {
        a : ^App_Data = cast(^App_Data)app_data
        g := &a.graphics_data

        _ = sdl.GetRelativeMouseState(&a.mouse_delta.x, &a.mouse_delta.y)
        
        // TIME
        tick_now := time.tick_now()
        a.delta = f32(time.duration_seconds(time.tick_diff(a.tick_frame, tick_now)))
        a.delta = min(0.016, a.delta)
        a.tick_frame = tick_now

        a.time_accumulated += a.delta

        if a.has_camera_control {
                CAMERA_SPEED :: 4
                CAMERA_SPEED_BOOST :: 30
                CAMERA_SENS :: 0.005

                a.camera_yaw_pitch += a.mouse_delta * CAMERA_SENS
                a.camera_yaw_pitch.x = math.wrap(a.camera_yaw_pitch.x, math.TAU)
                a.camera_yaw_pitch.y = math.clamp(a.camera_yaw_pitch.y, math.PI * -0.5 + 0.01, math.PI * 0.5 - 0.01)
                q_pitch := linalg.quaternion_from_euler_angle_x_f32(a.camera_yaw_pitch.y)
                q_yaw := linalg.quaternion_from_euler_angle_y_f32(a.camera_yaw_pitch.x)
                g.camera.rotation = q_yaw * q_pitch


                wish_move: [3]f32
                if .Forward in a.directional_input {
                        wish_move.z -= 1
                }
                if .Backward in a.directional_input {
                        wish_move.z += 1
                }
                if .Left in a.directional_input {
                        wish_move.x -= 1
                }
                if .Right in a.directional_input {
                        wish_move.x += 1
                }
                if .Up in a.directional_input {
                        wish_move.y += 1
                }
                if .Down in a.directional_input {
                        wish_move.y -= 1
                }

                // .xz movement is relative to camera, .y is relative to world up
                cam_forward := linalg.quaternion_mul_vector3(g.camera.rotation, cal.FORWARD)
                cam_right := linalg.quaternion_mul_vector3(g.camera.rotation, cal.RIGHT)
                world_move := cam_forward * wish_move.z + cam_right * wish_move.x + cal.UP * wish_move.y
                world_move = linalg.clamp_length(world_move, 1)
               
                speed : f32 = CAMERA_SPEED_BOOST if a.camera_boost else CAMERA_SPEED
                g.camera.position += world_move * (speed * a.delta)
        }


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

        a.mouse_delta = {0, 0}


        return .CONTINUE
}
