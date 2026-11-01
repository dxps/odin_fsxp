package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import finance "../shared/finance"

DEV_MODE :: #config(DEV_MODE, false)
FRONTEND_BUILD :: #config(FRONTEND_BUILD, "manual")
foreign import browser "browser"
@(default_calling_convention="c")
foreign browser {
    viewport_width :: proc() -> f64 ---
    viewport_height :: proc() -> f64 ---
    begin :: proc(width, height: f64) ---
    rect :: proc(x, y, w, h: f64, color: rawptr, length: i32) ---
    text :: proc(x, y, size: f64, value: rawptr, length: i32, color: rawptr, color_length: i32) ---
    line :: proc(x1, y1, x2, y2, width: f64, color: rawptr, length: i32) ---
    circle :: proc(x, y, radius: f64, color: rawptr, length: i32) ---
    fetch_text :: proc(kind: i32, url: rawptr, length: i32) ---
    label :: proc(value: rawptr, length: i32) ---
    reload :: proc() ---
    set_pointer_cursor :: proc(active: i32) ---
}
BG :: "#0c1420"
PANEL :: "#142132"
INK :: "#edf3f8"
MUTED :: "#93a7bb"
GRID :: "#27374a"
GREEN :: "#76e0bb"
RED :: "#ff9b92"
Observation :: finance.Observation
Price_Response :: finance.Price_Response
Box :: struct { x, y, w, h: f64 }
prices: [128]Observation
// Dates are copied out of the temporary JSON allocator before it is reset.
dates: [128][16]u8
count, selected: int
returns_mode, loading, online: bool
error_message: string
backend_build: [64]u8
backend_build_length: int
response_bytes: [65536]u8
poll_elapsed: f64
pending: [3]bool
pending_age: [3]f64
focus: int = -1
refresh_box, price_box, return_box, chart_box: Box
dirty := true

fill :: proc(b: Box, color: string) { rect(b.x, b.y, b.w, b.h, raw_data(color), i32(len(color))) }
write :: proc(x, y, size: f64, value: string, color := INK) { text(x, y, size, raw_data(value), i32(len(value)), raw_data(color), i32(len(color))) }
stroke :: proc(x1, y1, x2, y2: f64, color := GRID, width: f64 = 1) { line(x1, y1, x2, y2, width, raw_data(color), i32(len(color))) }
dot :: proc(x, y, radius: f64, color: string) { circle(x, y, radius, raw_data(color), i32(len(color))) }
inside :: proc(b: Box, x, y: f64) -> bool { return x >= b.x && x <= b.x+b.w && y >= b.y && y <= b.y+b.h }
request :: proc(kind: int, url: string) {
    if pending[kind] { return }
    pending[kind] = true
    pending_age[kind] = 0
    fetch_text(i32(kind), raw_data(url), i32(len(url)))
}
refresh :: proc() {
    loading = true
    error_message = ""
    request(0, "/api/prices")
    request(1, "/api/health")
    dirty = true
}
main :: proc() { refresh() }
@(export)
response_buffer :: proc "c" () -> rawptr { return &response_bytes[0] }
@(export)
response_capacity :: proc "c" () -> i32 { return i32(len(response_bytes)) }
@(export)
receive :: proc "c" (kind, status, length: i32) {
    context = runtime.default_context()
    if kind < 0 || kind >= i32(len(pending)) || length < 0 || length > i32(len(response_bytes)) { return }
    pending[kind] = false
    dirty = true
    data := response_bytes[:int(length)]
    if kind == 0 {
        loading = false
        if status != 200 { error_message = "Price API unavailable. Start backend and Retry."; return }
        result: Price_Response
        if json.unmarshal(data, &result, allocator=context.temp_allocator) != nil || len(result.observations) < 2 || len(result.observations) > len(prices) {
            error_message = "The API returned an invalid price dataset."
            return
        }
        for item in result.observations {
            if _, valid := finance.simple_return(item.close, item.close); !valid || len(item.date) > len(dates[0]) {
                error_message = "The API returned invalid prices or dates."
                return
            }
        }
        count = len(result.observations)
        for item, i in result.observations {
            copy(dates[i][:], item.date)
            prices[i] = item
            prices[i].date = string(dates[i][:len(item.date)])
            if i > 0 { prices[i].daily_return, prices[i].has_return = finance.simple_return(prices[i-1].close, item.close) }
            else { prices[i].has_return = false }
        }
        selected = min(selected, count-1)
        error_message = ""
        summary := fmt.tprintf("Odin research lab. Synthetic DEMO dataset. %d observations. Latest close %.2f. Tab selects controls, Enter activates, arrow keys inspect prices.", count, prices[count-1].close)
        label(raw_data(summary), i32(len(summary)))
    } else if kind == 1 {
        health: struct { status, build: string }
        online = status == 200 && json.unmarshal(data, &health, allocator=context.temp_allocator) == nil && health.status == "ok"
        if online {
            changed := string(backend_build[:backend_build_length]) != health.build
            backend_build_length = copy(backend_build[:], health.build)
            if changed && !pending[0] { request(0, "/api/prices") }
        }
    } else if kind == 2 && DEV_MODE && status == 200 {
        version: struct { frontend: string }
        if json.unmarshal(data, &version, allocator=context.temp_allocator) == nil && version.frontend != "" && version.frontend != FRONTEND_BUILD { reload() }
    }
}
@(export)
pointer :: proc "c" (x, y: f64, down: i32) {
    context = runtime.default_context()
    set_pointer_cursor(1 if inside(refresh_box, x, y) else 0)
    if down != 0 {
        // Pointer input does not retain the keyboard focus indicator.
        focus = -1
        if inside(refresh_box, x, y) { refresh() }
        if inside(price_box, x, y) { returns_mode = false }
        if inside(return_box, x, y) { returns_mode = true }
    }
    if count > 1 && inside(chart_box, x, y) { selected = clamp(int(math.round((x-chart_box.x)/chart_box.w*f64(count-1))), 0, count-1) }
    dirty = true
}
@(export)
key :: proc "c" (code, shift: i32) -> i32 {
    context = runtime.default_context()
    switch code {
    case 1: selected = max(0, selected-1)
    case 2: selected = min(max(0, count-1), selected+1)
    case 3:
        if shift != 0 {
            if focus <= 0 { focus = -1; dirty = true; return 0 }
            focus -= 1
        } else {
            if focus == 2 { focus = -1; dirty = true; return 0 }
            focus += 1
        }
    case 4:
        if focus == 0 { refresh() }
        if focus == 1 { returns_mode = false }
        if focus == 2 { returns_mode = true }
    case: return 0
    }
    dirty = true
    return 1
}
button :: proc(b: Box, title: string, active: bool, index: int) {
    if focus == index { fill({b.x-2, b.y-2, b.w+4, b.h+4}, GREEN) }
    fill(b, GRID if active else PANEL)
    write(b.x+14, b.y+25, 13, title, GREEN if active else INK)
}

refresh_icon :: proc(b: Box) {
    if focus == 0 {
        fill({b.x-2, b.y-2, b.w+4, b.h+4}, GREEN)
        fill(b, BG)
    }
    color := MUTED if loading else RED if error_message != "" else GREEN
    cx, cy := b.x+b.w/2, b.y+b.h/2
    // Two opposing curved arrows, with arrowheads aligned to each arc's tangent.
    radius: f64 = 8.5
    for arrow in 0..<2 {
        start := (-165.0 + f64(arrow)*180) * math.PI/180
        end := start + 150*math.PI/180
        previous_x, previous_y := cx+radius*math.cos(start), cy+radius*math.sin(start)
        dot(previous_x, previous_y, 1, color)
        for i in 1..=24 {
            angle := start + f64(i)/24 * (end-start)
            x, y := cx+radius*math.cos(angle), cy+radius*math.sin(angle)
            stroke(previous_x, previous_y, x, y, color, 2)
            previous_x = x; previous_y = y
        }
        nx, ny := math.cos(end), math.sin(end)
        tx, ty := -ny, nx
        sides := [2]int{-1, 1}
        for side in sides {
            wing_x := previous_x-5*tx+f64(side)*3.5*nx
            wing_y := previous_y-5*ty+f64(side)*3.5*ny
            stroke(wing_x, wing_y, previous_x, previous_y, color, 2)
            dot(wing_x, wing_y, 1, color)
        }
        dot(previous_x, previous_y, 1, color)
    }
}
last_width, last_height: f64
@(export)
step :: proc(delta: f64) -> bool {
    poll_elapsed += delta
    for &age, i in pending_age {
        if pending[i] {
            age += delta
            if age > 8 {
                pending[i] = false
                if i == 0 { loading = false; error_message = "Price request timed out. Please Retry." }
                if i == 1 { online = false }
                dirty = true
            }
        }
    }
    if poll_elapsed >= 1.5 {
        poll_elapsed = 0
        request(1, "/api/health")
        when DEV_MODE { request(2, "/api/dev/version") }
    }
    w, h := max(360.0, viewport_width()), viewport_height()
    if w != last_width || h != last_height { dirty = true; last_width = w; last_height = h }
    if dirty { render(w, h); dirty = false }
    free_all(context.temp_allocator)
    return true
}
render :: proc(w, viewport_h: f64) {
    narrow := w < 700
    margin: f64 = 24 if narrow else 48
    content := w-2*margin
    cards_y: f64 = 216
    chart_y: f64 = 536 if narrow else 352
    table_y := chart_y+382
    height := max(viewport_h, table_y+150+f64(max(count, 2))*39)
    begin(w, height)
    fill({0, 0, w, height}, BG)
    write(margin, 40, 13, "ODIN  /  RESEARCH", GREEN)
    write(margin, 96, 34 if narrow else 42, "Market data lab")
    write(margin, 127, 14, "Read. Build. Inspect. Repeat.", MUTED)
    refresh_box = {w-margin-40, 154, 40, 40}
    refresh_icon(refresh_box)
    write(margin, 180, 12, "DEMO / SYNTHETIC", GREEN)
    if error_message != "" { write(margin, 207, 11, error_message, RED) }
    total, latest: f64
    if count > 1 { total, _ = finance.simple_return(prices[0].close, prices[count-1].close); latest = prices[count-1].close }
    titles := [3]string{"TOTAL RETURN", "LATEST CLOSE", "OBSERVATIONS"}
    values := [3]string{fmt.tprintf("%+.2f%%", total*100), fmt.tprintf("%.2f", latest), fmt.tprintf("%d", count)}
    for i in 0..<3 {
        box := Box{margin+f64(i)*(content+16)/3, cards_y, (content-32)/3, 106}
        if narrow { box = {margin, cards_y+f64(i)*94, content, 82} }
        fill(box, PANEL)
        write(box.x+18, box.y+26, 11, titles[i], MUTED)
        write(box.x+18, box.y+box.h-23, 29, values[i] if count > 0 else "--", GREEN if i == 0 else INK)
    }
    fill({margin, chart_y, content, 354}, PANEL)
    write(margin+20, chart_y+32, 18, "Daily returns" if returns_mode else "Closing prices")
    price_box = {margin+20, chart_y+49, 86, 38}
    return_box = {margin+114, chart_y+49, 96, 38}
    button(price_box, "Price", !returns_mode, 1)
    button(return_box, "Returns", returns_mode, 2)
    chart_box = {margin+60, chart_y+120, content-92, 170}
    if count < 2 { write(margin+24, chart_y+190, 14, "Waiting for the price API...", MUTED) }
    else {
        lo, hi := prices[0].close, prices[0].close
        if returns_mode { lo = 0; hi = 0 }
        for item in prices[:count] {
            v := item.daily_return*100 if returns_mode else item.close
            lo = min(lo, v); hi = max(hi, v)
        }
        padding := max((hi-lo)*0.15, 0.1)
        lo -= padding; hi += padding
        for j in 0..<5 {
            y := chart_box.y+f64(j)*chart_box.h/4
            stroke(chart_box.x, y, chart_box.x+chart_box.w, y)
            write(margin+10, y+4, 10, fmt.tprintf("%.1f", hi-f64(j)*(hi-lo)/4), MUTED)
        }
        previous_x, previous_y: f64
        for item, i in prices[:count] {
            x := chart_box.x+f64(i)*chart_box.w/f64(count-1)
            v := item.daily_return*100 if returns_mode else item.close
            y := chart_box.y+(hi-v)/(hi-lo)*chart_box.h
            if returns_mode {
                zero := chart_box.y+hi/(hi-lo)*chart_box.h
                if item.has_return { fill({x-8, min(y, zero), 16, max(2.0, abs(zero-y))}, GREEN if v >= 0 else RED) }
            } else {
                if i > 0 { stroke(previous_x, previous_y, x, y, GREEN, 2) }
                dot(x, y, 3, GREEN)
            }
            if i == selected { stroke(x, chart_box.y, x, chart_box.y+chart_box.h, MUTED); dot(x, y, 5, INK) }
            previous_x = x; previous_y = y
        }
        write(chart_box.x, chart_y+315, 11, prices[0].date, MUTED)
        write(chart_box.x+chart_box.w-78, chart_y+315, 11, prices[count-1].date, MUTED)
        item := prices[selected]
        write(margin+20, chart_y+340, 12, fmt.tprintf("%s  |  Close %.2f  |  %s", item.date, item.close, fmt.tprintf("%+.2f%%", item.daily_return*100) if item.has_return else "No prior close"))
    }
    write(margin, table_y, 18, "Observation ledger")
    write(margin, table_y+25, 11, "Chart: hover or use left / right arrow keys.", MUTED)
    fill({margin, table_y+43, content, 32}, GRID)
    write(margin+14, table_y+64, 11, "DATE", MUTED)
    write(margin+content*0.48, table_y+64, 11, "CLOSE", MUTED)
    write(margin+content*0.72, table_y+64, 11, "RETURN", MUTED)
    for item, i in prices[:count] {
        row_y := table_y+76+f64(i)*39
        if i == selected { fill({margin, row_y, content, 38}, PANEL) }
        write(margin+14, row_y+24, 12, item.date)
        write(margin+content*0.48, row_y+24, 12, fmt.tprintf("%.2f", item.close))
        write(margin+content*0.72, row_y+24, 12, fmt.tprintf("%+.2f%%", item.daily_return*100) if item.has_return else "--", GREEN if item.daily_return >= 0 else RED)
    }
    footer_y := table_y+100+f64(count)*39
    dot(margin+4, footer_y-4, 3, GREEN if online else RED)
    write(margin+16, footer_y, 11, fmt.tprintf("API %s / build %s", "online" if online else "offline", string(backend_build[:backend_build_length])), MUTED)
    write(margin, footer_y+24, 10, "Odin native + WASM / shared financial calculations", MUTED)
}
