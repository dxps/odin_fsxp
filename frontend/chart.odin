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
    names := [5]string{"Close + moving average", "Period returns (%)", "Rolling sample volatility (%)", "Wealth index (base 100)", "Calendar comparison"}
    write(margin+16,top+30,16,names[chart_mode])
    write(margin+16,top+53,10,"Green: primary / blue: average or benchmark",THEME.colors.muted)
    write(margin+16,top+70,10,"Gaps = unavailable. Comparison uses raw prices.",THEME.colors.muted)
    chart_box = {margin+58,top+85,content-80,200}
    lo,hi: f64
    found := false
    overlays := chart_mode == 0 || chart_mode == 4
    for i in 0..<count { for layer in 0..<2 {
        if layer == 1 && !overlays { continue }
        v := chart_value(i,layer==1)
        if !v.valid { continue }
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
        r := research_rows[selected]; v := chart_value(selected)
        write(margin+16,top+333,12,fmt.tprintf("%s | %s%s",r.date,fmt.tprintf("%.3f",v.value) if v.valid else "Unavailable", " | Partial period" if r.incomplete else ""))
        write(margin+16,top+359,11,fmt.tprintf("Excess return %s | Lagged return %s",fmt.tprintf("%+.2f%%",r.excess_return.value*100) if r.excess_return.valid else "--",fmt.tprintf("%+.2f%%",r.lagged_return.value*100) if r.lagged_return.valid else "--"),THEME.colors.muted)
    }
}
