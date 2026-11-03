package main

import "base:runtime"
import "core:math"

activate_control :: proc(index: int) {
    if index >= 1 && index <= 5 && loading { return }
    switch index {
    case 0: refresh()
    case 1: instrument = (instrument+1)%2; refresh()
    case 2: frequency = (frequency+1)%3; refresh()
    case 3: range_choice = (range_choice+1)%3; refresh()
    case 4: join_policy = (join_policy+1)%3; refresh()
    case 5: window_choice = (window_choice+1)%3; refresh()
    case 6: chart_mode = (chart_mode+1)%5
    case 7: ledger_page = max(0,ledger_page-1)
    case 8: ledger_page = min(max(0,(count-1)/PAGE_SIZE),ledger_page+1)
    }
    dirty = true
}
@(export)
pointer :: proc "c" (x,y: f64, down: i32) {
    context = runtime.default_context()
    hovered_row = -1
    for box, i in row_boxes[:count] { if box.w > 0 && inside(box,x,y) { hovered_row = i; break } }
    over := hovered_row >= 0
    for box, i in controls { if inside(box,x,y) { over = true; if down != 0 { focus = -1; activate_control(i) } } }
    set_pointer_cursor(1 if over else 0)
    if down != 0 && hovered_row >= 0 { selected = hovered_row; focus = -1 }
    chart_hovered = count > 0 && chart_box.w > 0 && inside(chart_box,x,y)
    chart_keyboard = false
    chart_pointer_y = y
    if chart_hovered {
        selected = clamp(int(math.round((x-chart_box.x)/chart_box.w*f64(count-1))),0,count-1)
    }
    dirty = true
}
@(export)
key :: proc "c" (code, shift: i32) -> i32 {
    context = runtime.default_context()
    switch code {
    case 1: chart_keyboard = true; selected = max(0,selected-1); ledger_page = selected/PAGE_SIZE
    case 2: chart_keyboard = true; selected = min(max(0,count-1),selected+1); ledger_page = selected/PAGE_SIZE
    case 3:
        chart_keyboard = false
        if shift != 0 { if focus <= 0 { focus = -1; dirty = true; return 0 }; focus -= 1 } else {
            if focus == CONTROL_COUNT-1 { focus = -1; dirty = true; return 0 }; focus += 1
        }
    case 4: activate_control(focus)
    case: return 0
    }
    dirty = true
    return 1
}
