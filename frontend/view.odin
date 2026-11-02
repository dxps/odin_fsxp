package main

import "core:fmt"

Layout :: struct {
    width,height,margin,content,chart_y,table_y: f64,
    narrow: bool,
}
calculate_layout :: proc(width,viewport_height: f64) -> Layout {
    narrow := width < 700
    margin: f64 = 20 if narrow else 48
    chart_y: f64 = 445 if narrow else 345
    table_y := chart_y+425
    height := max(viewport_height,table_y+150+f64(min(count,PAGE_SIZE))*39)
    return {width,height,margin,width-2*margin,chart_y,table_y,narrow}
}
render :: proc(width,viewport_height: f64) {
    layout := calculate_layout(width,viewport_height)
    begin(layout.width,layout.height)
    fill({0,0,layout.width,layout.height},THEME.colors.background,corner_radius=0)
    render_header(layout)
    render_metrics(layout)
    render_chart(layout)
    render_ledger(layout)
    render_footer(layout)
}
render_header :: proc(layout: Layout) {
    m := layout.margin
    write(m,32,12,"ODIN / QUANTITATIVE WORKFLOW",THEME.colors.positive)
    write(m,75,30,"Research lab")
    write(m,102,12,"Synthetic data / illustrative calendars",THEME.colors.muted)
    frequencies := [3]string{"Daily", "Weekly", "Monthly"}
    ranges := [3]string{"Jan - Jun", "Jan - Mar", "Apr - Jun"}
    joins := [3]string{"Join: inner", "Join: left", "Join: outer"}
    windows := [3]int{3,10,20}
    charts := [5]string{"Chart: price", "Chart: return", "Chart: volatility", "Chart: wealth", "Chart: compare"}
    labels := [9]string{
        "Refresh", "Asset: A" if instrument == 0 else "Asset: B",
        frequencies[frequency],
        ranges[range_choice],
        joins[join_policy],
        fmt.tprintf("Window: %d",windows[window_choice]),
        charts[chart_mode],
        "Previous page", "Next page",
    }
    columns := 2 if layout.narrow else 4
    for i in 0..<7 {
        w := (layout.content-f64(columns-1)*8)/f64(columns)
        controls[i] = {m+f64(i%columns)*(w+8),120+f64(i/columns)*44,w,36}
        button(controls[i],labels[i],false,i)
    }
    bottom: f64 = 304 if layout.narrow else 216
    if loading { write(m,bottom,11,"Loading research...",THEME.colors.muted) }
    if error_message != "" { write(m,bottom,11,error_message,THEME.colors.negative) }
    write(m,bottom+21,11,fmt.tprintf("Matched %d | Discarded %d | Primary-only %d / Other-only %d",research_stats.matched,research_stats.discarded,research_stats.left_only,research_stats.right_only),THEME.colors.muted)
}
render_metrics :: proc(layout: Layout) {
    y := layout.chart_y-65
    last: f64; valid := false
    if count > 0 { last = research_rows[count-1].wealth.value; valid = research_rows[count-1].wealth.valid }
    write(layout.margin,y,12,fmt.tprintf("%d observations | Window counts periods",count),THEME.colors.muted)
    write(layout.margin,y+25,14,fmt.tprintf("Cumulative return: %s",fmt.tprintf("%+.2f%%",last-100) if valid else "unavailable (missing return)"))
}
render_ledger :: proc(layout: Layout) {
    m,c,y := layout.margin,layout.content,layout.table_y
    write(m,y,18,"Observation ledger")
    controls[7] = {m,y+14,(c-8)/2,34}; controls[8] = {m+(c+8)/2,y+14,(c-8)/2,34}
    button(controls[7],"Previous page",false,7); button(controls[8],"Next page",false,8)
    write(m,y+68,11,fmt.tprintf("Page %d / %d | * partial period",ledger_page+1,max(1,(count+PAGE_SIZE-1)/PAGE_SIZE)),THEME.colors.muted)
    fill({m,y+80,c,30},THEME.colors.grid)
    write(m+8,y+100,10,"OBSERVED DATE",THEME.colors.muted)
    write(m+c*0.48,y+100,10,"CLOSE",THEME.colors.muted)
    write(m+c*0.72,y+100,10,"RETURN",THEME.colors.muted)
    for &box in row_boxes { box = {} }
    start := ledger_page*PAGE_SIZE
    for i in start..<min(count,start+PAGE_SIZE) {
        r := research_rows[i]; row_y := y+112+f64(i-start)*39
        row_boxes[i] = {m,row_y,c,38}
        if i == selected { fill(row_boxes[i],THEME.colors.panel) } else if i == hovered_row { fill(row_boxes[i],THEME.colors.row_hover) }
        write(m+8,row_y+24,11,fmt.tprintf("%s%s",r.date,"*" if r.incomplete else ""))
        write(m+c*0.48,row_y+24,11,fmt.tprintf("%.2f",r.close.value) if r.close.valid else "--")
        write(m+c*0.72,row_y+24,11,fmt.tprintf("%+.2f%%",r.period_return.value*100) if r.period_return.valid else "--")
    }
}
render_footer :: proc(layout: Layout) {
    y := layout.table_y+135+f64(min(count,PAGE_SIZE))*39
    write(layout.margin,y,10,fmt.tprintf("API %s / build %s","online" if online else "offline",string(backend_build[:backend_build_length])),THEME.colors.muted)
}
