package callisto_sandbox

import im "callisto/imgui"
import cal "callisto"
import "core:path/filepath"
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


UI_Content_Browser_State :: struct {
        intern : strings.Intern,
        cwd    : string,
        filter : im.TextFilter,
}

ui_content_browser_init :: proc(cbs: ^UI_Content_Browser_State) -> (ok: bool) {
        check(strings.intern_init(&cbs.intern)) or_return
        return true
}

ui_content_browser_destroy :: proc(cbs: ^UI_Content_Browser_State) {
        strings.intern_destroy(&cbs.intern)
}


ui_content_browser_reload :: proc(cbs: ^UI_Content_Browser_State) {
}


ui_draw_content_browser :: proc(cbs: ^UI_Content_Browser_State) {
        if im.BeginChild("##tree", {300, 0}, {.ResizeX, .Borders, .NavFlattened}) {
                im.SetNextItemWidth(-math.F32_MIN)
                if im.InputTextWithHint("##filter", "Filter: incl, -excl", cstring(&cbs.filter.InputBuf[0]), len(cbs.filter.InputBuf), {.EscapeClearsAll}) {
                        im.TextFilter_Build(&cbs.filter)
                }
                im.Text("TREE")
                im.EndChild()
        }
        // Get current relative directory
}
