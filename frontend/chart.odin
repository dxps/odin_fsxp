package main

import "core:fmt"
import ts "../shared/timeseries"

chart_value :: proc(index: int, overlay := false) -> ts.Value {
    r := research_rows[index]
    if overlay { if chart_mode == 0 { return r.moving_average }; return r.benchmark }
    switch chart_mode {
    case 0,4: return r.close
    case 1: v := r.period_return; v.value *= 100; return v
    case 2: v := r.volatility; v.value *= 100; return v
    case 3: return r.wealth
    }
    return {}
}
render_chart :: proc(layout: Layout) {
    margin, content, top := layout.margin, layout.content, layout.chart_y
    fill({margin,top,content,390},THEME.colors.panel)
    names := [5]string{"Close + moving average", "Period returns (%)", "Rolling sample volatility (%)", "Wealth index (base 100)", "Calendar comparison (raw prices)"}
    write(margin+16,top+30,16,names[chart_mode])
    chart_box = {margin+58,top+85,content-80,200}
    lo,hi: f64
    found := false
    overlays := chart_mode == 0 || chart_mode == 4
    for i in 0..<count { for layer in 0..<2 {
        if layer == 1 && !overlays { continue }
        v := chart_value(i,layer==1)
        if !v.valid { continue }
        series_names := [5]string{"Close", "Period return", "Volatility", "Wealth", "Primary close"}
    legend_x, legend_y := margin+20, top+343
    dot(legend_x, legend_y-4, 3, THEME.colors.positive)
    write(legend_x+10, legend_y, 11, series_names[chart_mode])
    if overlays {
        dot(legend_x+110, legend_y-4, 3, "#87bfff")
        write(legend_x+120, legend_y, 11, "Moving average" if chart_mode == 0 else "Benchmark close")
    }
    write(legend_x, legend_y+22, 10, "Gaps indicate unavailable values.", THEME.colors.muted)
    if !found { lo = v.value; hi = v.value; found = true }
        lo = min(lo,v.value); hi = max(hi,v.value)
    } }
    if !found { write(margin+18,top+150,13,"No values: choose a smaller window or wider range.",THEME.colors.muted); return }
    padding := max((hi-lo)*0.15,0.1); lo -= padding; hi += padding
    for j in 0..<5 {
        y := chart_box.y+f64(j)*chart_box.h/4
        stroke(chart_box.x,y,chart_box.x+chart_box.w,y)
        write(margin+6,y+4,10,fmt.tprintf("%.1f",hi-f64(j)*(hi-lo)/4),THEME.colors.muted)
    }
    for layer in 0..<2 {
        if layer == 1 && !overlays { continue }
        px,py: f64; previous_valid := false
        color := THEME.colors.positive if layer == 0 else "#87bfff"
        for i in 0..<count {
            v := chart_value(i,layer==1)
            if !v.valid { previous_valid = false; continue }
            x := chart_box.x+f64(i)*chart_box.w/f64(max(1,count-1))
            y := chart_box.y+(hi-v.value)/(hi-lo)*chart_box.h
            if previous_valid { stroke(px,py,x,y,color,2) }
            if count < 40 { dot(x,y,2,color) }
            if i == selected { dot(x,y,4,THEME.colors.text) }
            px = x; py = y; previous_valid = true
        }
    }
    if count > 0 {
        x := chart_box.x+f64(selected)*chart_box.w/f64(max(1,count-1))
        stroke(x,chart_box.y,x,chart_box.y+chart_box.h,THEME.colors.muted)
        write(chart_box.x,top+306,10,research_rows[0].period,THEME.colors.muted)
        write(chart_box.x+chart_box.w-70,top+306,10,research_rows[count-1].period,THEME.colors.muted)
        if chart_hovered || chart_keyboard {
            render_chart_tooltip(x, overlays)
        }
    }
}

render_chart_tooltip :: proc(anchor_x: f64, overlays: bool) {
    row := research_rows[selected]
    width: f64 = 184
    height: f64 = 88 if overlays else 72
    right := chart_box.x + chart_box.w
    x := anchor_x + 10
    if x + width > right { x = anchor_x - width - 10 }
    x = clamp(x, chart_box.x, right - width)
    y := chart_box.y + 8
    if chart_hovered {
        y = clamp(chart_pointer_y - height - 10, chart_box.y, chart_box.y + chart_box.h - height)
    }
    fill({x, y, width, height}, THEME.colors.background)
    write(x+10, y+17, 11, fmt.tprintf("%s%s", row.date, " | Partial period" if row.incomplete else ""))
    names := [5]string{"Close", "Period return", "Volatility", "Wealth", "Primary close"}
    unit := "%" if chart_mode == 1 || chart_mode == 2 else ""
    tooltip_value(x, y+33, names[chart_mode], chart_value(selected), unit, THEME.colors.positive)
    detail_y := y+49
    if overlays {
        tooltip_value(x, detail_y, "Moving average" if chart_mode == 0 else "Benchmark close", chart_value(selected, true), "", "#87bfff")
        detail_y += 16
    }
    excess, lagged := row.excess_return, row.lagged_return
    excess.value *= 100
    lagged.value *= 100
    tooltip_value(x, detail_y, "Excess return", excess, "%", THEME.colors.muted)
    tooltip_value(x, detail_y+16, "Lagged return", lagged, "%", THEME.colors.muted)
}

tooltip_value :: proc(x, y: f64, name: string, value: ts.Value, unit, color: string) {
    dot(x+12, y-4, 3, color)
    number := fmt.tprintf("%.2f%s", value.value, unit) if value.valid else "--"
    write(x+22, y, 11, fmt.tprintf("%s: %s", name, number))
}
