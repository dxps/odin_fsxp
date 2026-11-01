package main

import finance "../shared/finance"
import "core:fmt"

// Responsive layout and dashboard sections, in the order they appear on screen.
Layout :: struct {
	width, height, margin, content, chart_y, table_y: f64,
	narrow: bool,
}

calculate_layout :: proc(width, viewport_height: f64) -> Layout {
	narrow := width < 700
	margin: f64 = 24 if narrow else 48
	chart_y: f64 = 536 if narrow else 352
	table_y := chart_y + 382
	height := max(viewport_height, table_y + 150 + f64(max(count, 2)) * 39)
	return {width, height, margin, width - 2 * margin, chart_y, table_y, narrow}
}

render :: proc(width, viewport_height: f64) {
	layout := calculate_layout(width, viewport_height)
	begin(layout.width, layout.height)
	fill({0, 0, layout.width, layout.height}, BG)
	render_header(layout)
	render_metrics(layout)
	render_chart(layout)
	render_ledger(layout)
	render_footer(layout)
}

render_header :: proc(layout: Layout) {
	w, margin, narrow := layout.width, layout.margin, layout.narrow
	write(margin, 40, 13, "ODIN  /  RESEARCH", GREEN)
	write(margin, 96, 34 if narrow else 42, "Market data lab")
	write(margin, 127, 14, "Read. Build. Inspect. Repeat.", MUTED)
	refresh_box = {w - margin - 40, 154, 40, 40}
	refresh_icon(refresh_box)
	write(margin, 180, 12, "DEMO / SYNTHETIC", GREEN)
	if error_message != "" {
		write(margin, 207, 11, error_message, RED)
	}
}

render_metrics :: proc(layout: Layout) {
	margin, content, narrow := layout.margin, layout.content, layout.narrow
	cards_y: f64 = 216
	total, latest: f64
	if count > 1 {
		total, _ = finance.simple_return(prices[0].close, prices[count - 1].close)
		latest = prices[count - 1].close
	}
	titles := [3]string{"TOTAL RETURN", "LATEST CLOSE", "OBSERVATIONS"}
	values := [3]string {
		fmt.tprintf("%+.2f%%", total * 100),
		fmt.tprintf("%.2f", latest),
		fmt.tprintf("%d", count),
	}
	for i in 0 ..< 3 {
		box := Box{margin + f64(i) * (content + 16) / 3, cards_y, (content - 32) / 3, 106}
		if narrow {
			box = {margin, cards_y + f64(i) * 94, content, 82}
		}
		fill(box, PANEL)
		write(box.x + 18, box.y + 26, 11, titles[i], MUTED)
		write(
			box.x + 18,
			box.y + box.h - 23,
			29,
			values[i] if count > 0 else "--",
			GREEN if i == 0 else INK,
		)
	}
}

render_ledger :: proc(layout: Layout) {
	margin, content, table_y := layout.margin, layout.content, layout.table_y
	write(margin, table_y, 18, "Observation ledger")
	write(margin, table_y + 25, 11, "Chart: hover or use left / right arrow keys.", MUTED)
	fill({margin, table_y + 43, content, 32}, GRID)
	write(margin + 14, table_y + 64, 11, "DATE", MUTED)
	write(margin + content * 0.48, table_y + 64, 11, "CLOSE", MUTED)
	write(margin + content * 0.72, table_y + 64, 11, "RETURN", MUTED)
	for item, i in prices[:count] {
		row_y := table_y + 76 + f64(i) * 39
		if i == selected {
			fill({margin, row_y, content, 38}, PANEL)
		}
		write(margin + 14, row_y + 24, 12, item.date)
		write(margin + content * 0.48, row_y + 24, 12, fmt.tprintf("%.2f", item.close))
		write(
			margin + content * 0.72,
			row_y + 24,
			12,
			fmt.tprintf("%+.2f%%", item.daily_return * 100) if item.has_return else "--",
			GREEN if item.daily_return >= 0 else RED,
		)
	}
}

render_footer :: proc(layout: Layout) {
	margin, table_y := layout.margin, layout.table_y
	footer_y := table_y + 100 + f64(count) * 39
	dot(margin + 4, footer_y - 4, 3, GREEN if online else RED)
	write(
		margin + 16,
		footer_y,
		11,
		fmt.tprintf(
			"API %s / build %s",
			"online" if online else "offline",
			string(backend_build[:backend_build_length]),
		),
		MUTED,
	)
}
