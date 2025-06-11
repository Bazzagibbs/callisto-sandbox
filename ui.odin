package callisto_sandbox

import "base:intrinsics"
import "base:runtime"
import "core:reflect"
import "core:log"
import "core:math"
import "core:strings"
import "core:math/linalg"
import "core:fmt"
import "core:strconv"
import "core:mem"
import "core:c"

import sdl "vendor:sdl3"
import sa "core:container/small_array"

import cal "callisto"
import config "callisto/config"

import "callisto/fonts"
import im "callisto/imgui"
import im_sdl "callisto/imgui/imgui_impl_sdl3"
import im_sdlgpu "callisto/imgui/imgui_impl_sdlgpu3"

USER_EVENT_REDRAW :: 128

bit_set_bool :: #force_inline proc(set: ^$T/bit_set[$E], element: E, value: bool) {
        if value {
                set^ += {element}
        } else {
                set^ -= {element}
        }
}

UI_Window :: enum {
        Content,
        Hierarchy,
        Inspector,
        Scene,
        Dear_Imgui_Demo,
}

UI_Window_State :: struct {
        open: bool,
        // position, dock, etc.
}


ui_inspectors : map[typeid]UI_Inspector_Proc

UI_Inspector_Proc :: #type proc (field_name: string, val: any, tags: UI_Field_Tags) -> (changed: bool)


UI_Data :: struct {
        device                 : ^sdl.GPUDevice, // < Not owned by this struct
        sampler                : ^sdl.GPUSampler,

        window_states          : [UI_Window]UI_Window_State,

        force_no_consume_event : bool,
        scene_view_hovered     : bool,
        scene_view_open        : bool,
        scene_view_dimensions  : [2]f32,
        scene_view_texture     : ^sdl.GPUTexture, // < Not owned by this struct
        scene_view_textureid   : sdl.GPUTextureSamplerBinding,
        event_counter          : int,

        content_browser_state : UI_Content_Browser_State,
}



UI_Field_Flags :: bit_set[UI_Field_Flag]
UI_Field_Flag :: enum {
        ignore,         // (Any) Don't draw an editor. Alias tag: "-"
        read_only,      // (Any) Disallow modification from the editor, including any child fields
        promote_fields, // (Structs) Flatten this field's children into this struct's scope
        no_resize,      // (Dynamic, Small_Array) Disallow modification of the "len" field
        color,          // ([3]f32, [4]f32) Draw a color picker instead of a vector editor
}

UI_Field_Reset_Values :: bit_set[UI_Field_Reset_Value]
UI_Field_Reset_Value :: enum {
        zero,           // Zero value for the type. Implicit if not specified.
        one,            // All fields 1
        identity,       // (quaternion, matrix) Identity value for the type
        black,          // (color) {0, 0, 0, 1} if alpha is available
        white,          // (color) {1, 1, 1, 1}, same as .one 
        normal,         // (color) {0.5, 0.5, 1, 1}, zero in tangent-space normal maps

        none,           // Don't allow a reset button
}

// Entity struct fields can be annotated with tags that modify how they are drawn in the editor: `cal_edit:"read_only,color"`
// See UI_Field_Flag
UI_Field_Tags :: struct {
        flags   : UI_Field_Flags,
        min     : UI_Field_Limit,
        max     : UI_Field_Limit,
        reset   : UI_Field_Reset_Value,
}

UI_Field_Limit :: union {struct{}, f64, int}


UI_Reset_Action :: enum {
        None,
        Reset,
}

ui_reset_button :: proc(tags: UI_Field_Tags, allowed_values: UI_Field_Reset_Values = {.zero}) -> (action: UI_Reset_Action) {
        // FIXME: Make a reset_any?
        // TODO: Align the reset button to the rhs of the window
        if tags.reset == .none || tags.reset not_in allowed_values || .read_only in tags.flags {
                return .None
        }
        im.SameLine(im.GetWindowWidth() - 20)
        if im.Button(":") {
                im.OpenPopup("reset menu")
        }

        if im.BeginPopupContextItem("reset menu") {
                defer im.EndPopup()
                if im.Selectable("Reset") {
                        return .Reset
                }
        }

        return .None
}


ui_parse_field_tags :: proc(ti: ^runtime.Type_Info_Struct, field_index: int) -> (tags: UI_Field_Tags, ok: bool) {
        ok = true
        if ti.usings[field_index] {
                tags.flags += {.promote_fields}
        }

        tag_str, exist := reflect.struct_tag_lookup(reflect.Struct_Tag(ti.tags[field_index]), "cal_edit")
        if !exist {
                return
        }

        parse_type :: proc(field_ti: ^runtime.Type_Info, val_str: string) -> (limit: UI_Field_Limit, ok: bool) {
                #partial switch v in field_ti.variant {
                case runtime.Type_Info_Integer:
                        val := strconv.parse_int(val_str) or_return
                        return val, true
                case runtime.Type_Info_Float:
                        val := strconv.parse_f64(val_str) or_return
                        return val, true
                }

                return {}, false
        }

        for entry in strings.split_multi_iterate(&tag_str, {",", "="}) {
                switch entry {
                case "ignore", "-": 
                        tags.flags += {.ignore}
                case "read_only": 
                        tags.flags += {.read_only}
                case "promote_fields": 
                        tags.flags += {.promote_fields}
                case "no_resize": 
                        tags.flags += {.no_resize}
                case "color":
                        tags.flags += {.color}
                case "min":
                        val_str, _ := strings.split_iterator(&tag_str, ",")
                        ok1: bool
                        tags.min, ok1 = parse_type(runtime.type_info_base(ti.types[field_index]), val_str)
                        ok &= ok1
                case "max":
                        val_str, _ := strings.split_iterator(&tag_str, ",")
                        ok1: bool
                        tags.max, ok1 = parse_type(runtime.type_info_base(ti.types[field_index]), val_str)
                        ok &= ok1
                case "reset":
                        reset_kind, _ := strings.split_iterator(&tag_str, ",")
                        switch reset_kind {
                        case "zero"     : tags.reset = .zero // implicit
                        case "one"      : tags.reset = .one
                        case "identity" : tags.reset = .identity
                        case "normal"   : tags.reset = .normal

                        case "none"     : tags.reset = .none
                        }
                }
        }

        return
}


ui_init :: proc(u: ^UI_Data, device: ^sdl.GPUDevice, window: ^sdl.Window) -> (ctx: ^im.Context, ok: bool) {
        u.device = device
        for &window_state in u.window_states {
                window_state.open = true
        }

        ui_content_browser_init(&u.content_browser_state)
        
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

        check_sdl(im_sdl.InitForSDLGPU(window))
        
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
        ui_content_browser_destroy(&u.content_browser_state)
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

                if im.BeginMenu("Window") {
                        window_names := reflect.enum_field_names(UI_Window)
                        for &window_state, i in u.window_states {
                                im.MenuItemBoolPtr(strings.unsafe_string_to_cstring(window_names[i]), nil, &window_state.open)
                        }
                        im.EndMenu()
                }

                im.EndMainMenuBar()
        }
       

        open : ^bool

        // Content browser
        open = &u.window_states[.Content].open
        if open^ {
                if im.Begin("Content", open) {
                        ui_draw_content_browser(&u.content_browser_state)
                }
                im.End()

        }

        // Hierarchy
        open = &u.window_states[.Hierarchy].open
        if open^ {
                hierarchy_window_flags : im.WindowFlags
                if a.scene.editor_state.dirty {
                        hierarchy_window_flags += {.UnsavedDocument}
                }

                if im.Begin("Hierarchy", open, hierarchy_window_flags) {
                        ui_draw_entities(&a.entities, &a.entity_selected)
                }
                im.End()
        }


        // Inspector
        open = &u.window_states[.Inspector].open 
        if open^ {
                if im.Begin("Inspector", open) {
                        ui_draw_inspector(&a.entities, &a.entity_selected)
                }
                im.End()
        }


        // Scene view window
        open = &u.window_states[.Scene].open 
        if open^ {
                u.scene_view_hovered = false
                im.SetNextWindowSizeConstraints({200, 200}, {max(f32), max(f32)})
                im.PushStyleVarImVec2(.WindowPadding, {0, 0})
                im.PushStyleVar(.WindowBorderSize, 0)
                if im.Begin("Scene", open, {}) {
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
                }
                im.End()
                im.PopStyleVar(2)
        }


        // Demo window
        open = &u.window_states[.Dear_Imgui_Demo].open
        if open^ {
                im.ShowDemoWindow(open)
        }

}


// Set selected_id = -1 to deselect everything
// Multi-select will need a new implementation. Maybe copy blender's selected (multi) + active (single)?
ui_draw_entities :: proc(entities: ^$T/[dynamic]$E, selected_id: ^int) where intrinsics.type_is_subtype_of(E, cal.Entity_Base) {
        for &e, i in entities {
                flags : im.TreeNodeFlags = { .OpenOnArrow, .OpenOnDoubleClick, .NavLeftJumpsBackHere, .SpanFullWidth, .Leaf }
                
                if selected_id^ == i {
                        flags += {.Selected}
                }

                im.PushIDInt(i32(i))
                name := strings.unsafe_string_to_cstring(e.name) if e.name != "" else "Entity"
                node_open := im.TreeNodeExStr("", flags, "%s", strings.unsafe_string_to_cstring(e.name))
                
                if im.IsItemFocused() {
                        selected_id^ = i
                }

                if node_open {
                        im.TreePop()
                }
                im.PopID()
                
                
        }
}


ui_draw_inspector :: proc(entities: ^$T/[dynamic]$E, selected_id: ^int) where intrinsics.type_is_subtype_of(E, cal.Entity_Base) {
        if selected_id^ <= -1 {
                return
        }

        selected := &entities[selected_id^]

        ti := runtime.type_info_base(type_info_of(E)).variant.(runtime.Type_Info_Struct)
        for i in 0..<ti.field_count {
                field_any := any {
                        data = rawptr(uintptr(selected) + ti.offsets[i]),
                        id = ti.types[i].id,
                }
                tags, ok := ui_parse_field_tags(&ti, int(i))
                if !ok {
                        ui_error_text("Invalid field tags:", ti.names[i])
                }

                im.PushIDInt(i)
                ui_draw_any(ti.names[i], field_any, tags)
                im.PopID()
        }
}

_type_info_int_to_im_datatype :: proc(ti: ^runtime.Type_Info) -> (type: im.DataType, ok: bool) {
        ok = true

        tvar := ti.variant.(runtime.Type_Info_Integer) or_return

        switch ti.size {
        case 1:
                type = .S8 if tvar.signed else .U8
                return
        case 2:
                type = .S16 if tvar.signed else .U16
                return
        case 4:
                type = .S32 if tvar.signed else .U32
                return
        case 8:
                type = .S64 if tvar.signed else .U64
                return
        }


        return {}, false
}

_type_info_float_to_im_datatype :: proc(ti: ^runtime.Type_Info) -> (type: im.DataType, ok: bool) {
        ok = true
        _ = ti.variant.(runtime.Type_Info_Float) or_return

        switch ti.size {
        case 4:
                type = .Float
                return
        case 8:
                type = .Double
                return
        }

        return {}, false
}

ui_error_text :: proc (fmt: cstring, str: string) {
        im.PushStyleColorImVec4(.Text, {0.8, 0, 0, 1})
        im.PushStyleColorImVec4(.TextDisabled, {0.6, 0, 0, 1})
        im.Text(fmt, str)
        im.PopStyleColor(2)
}


ui_draw_any :: proc(field_label: union{string, int}, val: any, tags: UI_Field_Tags) -> (changed: bool) {
        field_name: string


        number_buffer: [64]u8
        b := strings.builder_from_bytes(number_buffer[:])

        switch label in field_label {
        case int:
                field_name = fmt.sbprintf(&b, "[%d]", label)
                number_buffer[len(number_buffer) - 1] = 0 // enforce cstring safety
        case string:
                field_name = label
        }
        

        im.BeginDisabled(.read_only in tags.flags)
        defer im.EndDisabled()

        custom_inspector, exists := ui_inspectors[val.id]
        if exists {
                changed = custom_inspector(field_name, val, tags)
                return
        }

        ti_base := runtime.type_info_base(type_info_of(val.id))

        switch &ti in ti_base.variant {
        case runtime.Type_Info_Integer:
                type, ok := _type_info_int_to_im_datatype(ti_base)
                if !ok {
                        ui_error_text("%s: Unsupported integer size", field_name)
                        return
                }
                changed = im.DragScalar(strings.unsafe_string_to_cstring(field_name), type, val.data)
                if ui_reset_button(tags, {.zero, .one}) == .Reset {
                        #partial switch tags.reset {
                        case .zero:
                                mem.set(val.data, 0, ti_base.size)
                        case .one:
                                mem.set(val.data, 0, ti_base.size)
                                mem.set(val.data, 1, 1)
                        }

                }

        case runtime.Type_Info_Float:
                type, ok := _type_info_float_to_im_datatype(ti_base)
                if !ok {
                        ui_error_text("%s: Unsupported float size", field_name)
                        return
                }
                changed = im.DragScalar(strings.unsafe_string_to_cstring(field_name), type, val.data, v_speed = 0.1)
                if ui_reset_button(tags, {.zero, .one}) == .Reset {
                        if type == .Float {
                                val_float := (^f32)(val.data)
                                #partial switch tags.reset {
                                case .zero:
                                        val_float^ = 0
                                case .one:
                                        val_float^ = 1
                                }
                        } else {
                                val_float := (^f64)(val.data)
                                #partial switch tags.reset {
                                case .zero:
                                        val_float^ = 0
                                case .one:
                                        val_float^ = 1
                                }
                        }
                }
                
        case runtime.Type_Info_Array:
                is_scalar: bool
                type: im.DataType
                // TODO: color picker?
                #partial switch e_ti in ti.elem.variant {
                case runtime.Type_Info_Integer:
                        ok: bool
                        type, ok = _type_info_int_to_im_datatype(ti.elem)
                        if !ok {
                                ui_error_text("%s: Array of integers, element size unsupported", field_name)
                                return
                        }
                        is_scalar = true

                case runtime.Type_Info_Float:
                        ok: bool
                        type, ok = _type_info_float_to_im_datatype(ti.elem)
                        if !ok {
                                ui_error_text("%s: Array of floats, element size unsupported: %ld", field_name)
                                return
                        }
                        is_scalar = true
                case:
                        ui_error_text("%s: Array element type unsupported", field_name)                
                        return
                        
                }

                if .color in tags.flags {
                        // Returns early if valid, otherwise fall back to vector
                        if type == .Float && (ti.count == 3 || ti.count == 4) {
                                if ti.count == 3 {
                                        if im.ColorEdit3(strings.unsafe_string_to_cstring(field_name), (^[3]f32)(val.data), {}) {
                                        }
                                        if ui_reset_button(tags, {.zero, .one, .black, .white, .normal}) != .None {
                                                color_val := (^[3]f32)(val.data)
                                                #partial switch tags.reset {
                                                case .zero, .black:
                                                        color_val^ = {}
                                                case .one, .white:
                                                        color_val^ = {1, 1, 1}
                                                case .normal:
                                                        color_val^ = {0.5, 0.5, 1}
                                                }
                                        }
                                        return
                                } else {
                                        if im.ColorEdit4(strings.unsafe_string_to_cstring(field_name), (^[4]f32)(val.data), {}) {
                                        }
                                        if ui_reset_button(tags, {.zero, .one, .black, .white, .normal}) != .None {
                                                color_val := (^[4]f32)(val.data)
                                                #partial switch tags.reset {
                                                case .zero:
                                                        color_val^ = {}
                                                case .black:
                                                        color_val^ = {0, 0, 0, 1}
                                                case .one, .white:
                                                        color_val^ = {1, 1, 1, 1}
                                                case .normal:
                                                        color_val^ = {0.5, 0.5, 1, 1}
                                                }
                                        }
                                        return
                                }

                        } else {
                                ui_error_text("Invalid color tag on field:", field_name)
                        }
                }

                switch ti.count {
                case 2, 3, 4:
                        changed = im.DragScalarN(strings.unsafe_string_to_cstring(field_name), type, val.data, i32(ti.count), v_speed = 0.1)
                        if ui_reset_button(tags, {.zero, .one, .black, .white, .normal}) != .None {
                                color_val := (^[3]f32)(val.data)
                                #partial switch tags.reset {
                                case .zero:
                                        color_val^ = {}
                                case .one:
                                        color_val^ = {1, 1, 1}
                                case .normal:
                                        color_val^ = {0.5, 0.5, 1}
                                }
                        }
                        return
                case:
                        ui_error_text("%s: Unimplemented [N]Array", field_name)                
                        return
                }

        case runtime.Type_Info_Struct:
                scoped := .promote_fields not_in tags.flags
                if scoped {
                        im.SeparatorText(strings.unsafe_string_to_cstring(field_name))
                }
               
                for i in 0..<ti.field_count {
                        field_any := any {
                                data = rawptr(uintptr(val.data) + ti.offsets[i]),
                                id = ti.types[i].id,
                        }
                        next_tags, ok := ui_parse_field_tags(&ti, int(i))
                        if !ok {
                                ui_error_text("Invalid struct tags on field:", ti.names[i])
                        }
                        im.PushIDInt(i)
                        changed |= ui_draw_any(ti.names[i], field_any, next_tags)
                        im.PopID()
                }

                if scoped {
                        im.Separator()
                }
                return
        
        case runtime.Type_Info_String:
                // TODO: Semi-implemented, need to handle reallocations

                // Check if null terminated
                cstr    : cstring
                is_safe : bool

                if ti.is_cstring {
                        is_safe = true
                        cstr = cstring(val.data)
                }
                else {
                        str := (^string)(val.data)
                        cstr = strings.unsafe_string_to_cstring(str^)
                        // is_safe = (^u8)(rawptr(uintptr(rawptr(cstr)) + uintptr(len(str))))^ == 0 // Check if the next byte after the string is 0
                        is_safe = true
                }

                if !is_safe {
                        cstr = "Non-cstring"
                }

                im.Text("%s : %s (TI_String)", strings.unsafe_string_to_cstring(field_name), cstr)
        
        case runtime.Type_Info_Bit_Set:
                ti_enum_def := ti.elem.variant.(runtime.Type_Info_Named)
                ti_enum := ti_enum_def.base.variant.(runtime.Type_Info_Enum)

                if im.BeginCombo(strings.unsafe_string_to_cstring(field_name), strings.unsafe_string_to_cstring(ti_enum_def.name)) {
                        selectable_flags := im.SelectableFlags {.NoAutoClosePopups}

                        bit_set_data: u64

                        // Make a copy of data into u64
                        switch ti_base.size {
                        case 1:
                                bit_set_data = u64((^u8)(val.data)^)
                        case 2:
                                bit_set_data = u64((^u16)(val.data)^)
                        case 4:
                                bit_set_data = u64((^u32)(val.data)^)
                        case 8:
                                bit_set_data = u64((^u64)(val.data)^)
                        case:
                                ui_error_text("%s: Unsupported bit set size", field_name)
                                return false
                        }

                        for enum_name, i in ti_enum.names {
                                lsh_val := ti_enum.values[i]
                                mask := u64(1 << u64(lsh_val))
                                selected : bool = bit_set_data & mask != 0
                                new_selected := im.SelectableBoolPtr(strings.unsafe_string_to_cstring(enum_name), &selected, selectable_flags)
                                if new_selected {
                                        if selected {
                                                bit_set_data |= mask
                                        } else {
                                                bit_set_data &= ~mask
                                        }
                                }
                        }

                        switch ti_base.size {
                        case 1:
                                ((^u8)(val.data))^ = u8(bit_set_data)
                        case 2:
                                ((^u16)(val.data))^ = u16(bit_set_data)
                        case 3:
                                ((^u32)(val.data))^ = u32(bit_set_data)
                        case 4:
                                ((^u64)(val.data))^ = u64(bit_set_data)
                        }

                        im.EndCombo()
                }

        // Unimplemented
        // =============
        case runtime.Type_Info_Named:
                ui_error_text("%s: Unimplemented (TI_Named)", field_name)
        case runtime.Type_Info_Rune:
                ui_error_text("%s: Unimplemented (TI_Rune)", field_name)
        case runtime.Type_Info_Complex:
                ui_error_text("%s: Unimplemented (TI_Complex)", field_name)
        case runtime.Type_Info_Boolean:
                ui_error_text("%s: Unimplemented (TI_Boolean)", field_name)
        case runtime.Type_Info_Any:
                ui_error_text("%s: Unimplemented (TI_Any)", field_name)
        case runtime.Type_Info_Type_Id:
                ui_error_text("%s: Unimplemented (TI_Type_ID)", field_name)
        case runtime.Type_Info_Pointer:
                ui_error_text("%s: Unimplemented (TI_Pointer)", field_name)
        case runtime.Type_Info_Multi_Pointer:
                ui_error_text("%s: Unimplemented (TI_Multi_Pointer)", field_name)
        case runtime.Type_Info_Procedure:
                ui_error_text("%s: Unimplemented (TI_Procedure)", field_name)
        case runtime.Type_Info_Enumerated_Array:
                ui_error_text("%s: Unimplemented (TI_Enumerated_Array)", field_name)
        case runtime.Type_Info_Dynamic_Array:
                ui_error_text("%s: Unimplemented (TI_Dynamic_Array)", field_name)
        case runtime.Type_Info_Slice:
                ui_error_text("%s: Unimplemented (TI_Slice)", field_name)
        case runtime.Type_Info_Parameters:
                ui_error_text("%s: Unimplemented (TI_Parameters)", field_name)
        case runtime.Type_Info_Union:
                ui_error_text("%s: Unimplemented (TI_Union)", field_name)
        case runtime.Type_Info_Enum:
                ui_error_text("%s: Unimplemented (TI_Enum)", field_name)
        case runtime.Type_Info_Map:
                ui_error_text("%s: Unimplemented (TI_Map)", field_name)
        case runtime.Type_Info_Simd_Vector:
                ui_error_text("%s: Unimplemented (TI_SIMD_Vector)", field_name)
        case runtime.Type_Info_Matrix:
                ui_error_text("%s: Unimplemented (TI_Matrix)", field_name)
        case runtime.Type_Info_Soa_Pointer:
                ui_error_text("%s: Unimplemented (TI_Soa_Pointer)", field_name)
        case runtime.Type_Info_Bit_Field:
                ui_error_text("%s: Unimplemented (TI_Bit_Field)", field_name)

        // Custom inspector
        // ================
        case runtime.Type_Info_Quaternion:
                ui_error_text("%s: Raw quaternion - use cal.Rotation instead", field_name)
        }


        return false
}



// ui_draw_scene_hierarchy :: proc(s: ^cal.Scene) {
//         for root_node in s.transform_roots {
//                 draw_transform_node(s, root_node)
//         }
//
//         draw_transform_node :: proc(s: ^cal.Scene, transform: cal.Transform) {
//                 data := cal.transform_get_data(s, transform)
//                 flags : im.TreeNodeFlags = { .OpenOnArrow, .OpenOnDoubleClick, .NavLeftJumpsBackHere, .SpanFullWidth }
//
//                 im.PushIDInt(i32(transform))
//
//                 if len(data.children) == 0 {
//                         flags += {.Leaf }
//                 }
//                 
//                 if s.editor_state.transform_selected_latest == transform {
//                         flags += {.Selected}
//                 }
//
//                 if data.editor_state.use_hierarchy_color {
//                         im.PushStyleColorImVec4(im.Col.Button, data.editor_state.hierarchy_color)
//                 }
//
//                 node_open := im.TreeNodeExStr("", flags, "%s", strings.unsafe_string_to_cstring(data.name))
//
//                 if data.editor_state.use_hierarchy_color {
//                         im.PopStyleColor()
//                 }
//
//                 // Only select hierarchy node if the toggle arrow wasn't pressed
//                 if im.IsItemFocused() {
//                         s.editor_state.transform_selected_latest = transform
//                 }
//
//
//                 if node_open {
//                         for child in data.children {
//                                 draw_transform_node(s, child)
//                         }
//
//
//                         im.TreePop()
//                 }
//
//                 im.PopID()
//
//         }
// }


// ui_draw_transform_inspector :: proc(s: ^cal.Scene) {
//         if s.editor_state.transform_selected_latest == cal.TRANSFORM_NONE {
//                 return
//         }
//         
//         // im.TextUnformatted(strings.unsafe_string_to_cstring(cal.transform_get_name(s, s.editor_state.transform_selected_latest)))
//         ui_draw_inspector_name(s, s.editor_state.transform_selected_latest)
//         ui_draw_inspector_transform(s, s.editor_state.transform_selected_latest)
//         // Add inspector panels here
// }


// ui_draw_inspector_name :: proc(s: ^cal.Scene, t: cal.Transform) {
//         // TODO wrap this for string builder
//         buf : [128]u8
//         copy(buf[:], cal.transform_get_name(s, t))
//         buf[127] = 0
//
//         input_result := im.InputText("Name", cstring(&buf[0]), len(buf) - 1, {.EnterReturnsTrue}) 
//
//         if im.IsItemDeactivatedAfterEdit() {
//                 if input_result {
//                         log.info("Set name:", cstring(&buf[0]))
//                         cal.transform_set_name(s, t, string(buf[:]))
//                 }
//         }
// }

// ui_draw_inspector_transform :: proc(s: ^cal.Scene, t: cal.Transform) {
//         if im.TreeNodeEx("Transform", {.DefaultOpen, .SpanFullWidth}) {
//
//                 // POSITION 
//                 {
//                         temp_pos := cal.transform_get_local_position(s, t)
//                         if im.DragFloat3("Position", &temp_pos, v_speed = 0.1, flags = {}) {
//                                 cal.transform_set_local_position(s, t, temp_pos)
//                         }
//
//                         if im.IsItemDeactivatedAfterEdit() {
//                                 log.info("Set local position:", cal.transform_get_name(s, t), ":", temp_pos)
//                                 cal.scene_set_dirty(s)
//                                 // TODO: commit to undo history
//                         }
//                 }
//
//
//                 // ROTATION - Inspector is in euler degrees
//                 {
//                         temp_rot_quat := cal.transform_get_local_rotation(s, t)
//                         temp_rot_eul : [3]f32
//                         temp_rot_eul.x, temp_rot_eul.y, temp_rot_eul.z = linalg.euler_angles_from_quaternion_f32(temp_rot_quat, .XYZ) // Euler order might need to change when I decide on forward/up axes
//                         temp_rot_eul *= linalg.DEG_PER_RAD
//                         if im.DragFloat3("Rotation", &temp_rot_eul, v_speed = 0.1, flags = {}) {
//                                 temp_rot_eul *= linalg.RAD_PER_DEG
//                                 temp_rot_quat = linalg.quaternion_from_euler_angles_f32(expand_values(temp_rot_eul), .XYZ)
//                                 cal.transform_set_local_rotation(s, t, temp_rot_quat)
//                         }
//
//                         if im.IsItemDeactivatedAfterEdit() {
//                                 log.info("Set local rotation:", cal.transform_get_name(s, t), ":", temp_rot_eul)
//                                 cal.scene_set_dirty(s)
//                                 // TODO: commit to undo history
//                         }
//                 }
//
//                 // SCALE
//                 {
//                         temp_scale := cal.transform_get_local_scale(s, t)
//                         if im.DragFloat3("Scale", &temp_scale, v_speed = 0.1, flags = {}) {
//                                 cal.transform_set_local_scale(s, t, temp_scale)
//                         }
//
//                         if im.IsItemDeactivatedAfterEdit() {
//                                 log.info("Set local scale:", cal.transform_get_name(s, t), ":", temp_scale)
//                                 cal.scene_set_dirty(s)
//                                 // TODO: commit to undo history
//                         }
//                 }
//
//
//                 im.TreePop()
//         }
// }

// TODO: This needs to be changed. Why is editing rotations so hard :( just understand quaternions people :(
// - The quat->euler->quat conversion does not preserve user intention
// - Storing euler->quat is better but requires additional state
ui_inspector_rotation :: proc(name: string, val: any, tags: UI_Field_Tags) -> (changed: bool) {
        rotation := (^cal.Rotation)(val.data)
       
        if im.DragFloat3(strings.unsafe_string_to_cstring(name), &rotation._degrees_editor, v_speed = 0.1) {
                rotation.quaternion = linalg.quaternion_from_euler_angles_f32(expand_values(rotation._degrees_editor * linalg.RAD_PER_DEG), .XYZ)
        }

        // Figure this out
        if im.IsItemDeactivatedAfterEdit() {
                // TODO: commit to undo history
        }

        reset_action := ui_reset_button(tags, {.zero, .identity}) 
        if reset_action == .Reset {
                rotation.quaternion      = linalg.QUATERNIONF32_IDENTITY
                rotation._degrees_editor = {}
        }


        return false
}


ui_inspector_small_array :: proc(name: string, val: any, tags: UI_Field_Tags) -> (changed: bool) {
        ti := runtime.type_info_base(type_info_of(val.id)).variant.(runtime.Type_Info_Struct)

        // Small_Array is a fixed-size array: [N]E. Need to get the element type.
        ti_data := ti.types[0].variant.(runtime.Type_Info_Array)
        len := (^int)(uintptr(val.data) + ti.offsets[1])
       
        min_cap := 0
        min_cap_override, has_min := tags.min.(int)
        if has_min {
                min_cap = max(min_cap, min_cap_override)
        }

        max_cap := ti_data.count
        max_cap_override, has_max := tags.max.(int)
        if has_max {
                max_cap = min(max_cap, max_cap_override)
        }

        if im.BeginListBox(strings.unsafe_string_to_cstring(name)) {
                im.BeginDisabled(.no_resize in tags.flags)
                im.DragScalar("len", .S64, len, p_min = &min_cap, p_max = &max_cap, flags = {.ClampOnInput})
                im.EndDisabled()

                for i in 0..<len^ {
                        elem_any := any {
                                data = rawptr(uintptr(val.data) + ti.offsets[0] + uintptr(ti_data.elem_size * i)),
                                id = ti_data.elem.id,
                        }
                        im.PushIDInt(i32(i))
                        ui_draw_any(i, elem_any, tags)
                        im.PopID()
                }
                im.EndListBox()
        }

        return false
}


ui_inspector_none :: proc(name: string, val: any, tags: UI_Field_Tags) -> (changed: bool) {
        return false
}



@(init)
register_default_ui_inspectors :: proc() {
        ui_inspectors[cal.Rotation]      = ui_inspector_rotation
        ui_inspectors[cal.Mesh_Renderer] = ui_inspector_none
        ui_inspectors[cal.Material_List] = ui_inspector_small_array
}
