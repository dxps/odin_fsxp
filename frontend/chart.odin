package main

import "core:fmt"

// Price/return chart, axes, selection marker, and observation readout.
render_chart :: proc(layout: Layout) {
	margin, content, chart_y := layout.margin, layout.content, layout.chart_y
	fill({margin, chart_y, content, 354}, THEME.colors.panel)
	write(margin + 20, chart_y + 32, 18, "Daily returns" if returns_mode else "Closing prices")
	price_box = {margin + 20, chart_y + 49, 86, 38}
	return_box = {margin + 114, chart_y + 49, 96, 38}
	button(price_box, "Price", !returns_mode, 1)
	button(return_box, "Returns", returns_mode, 2)
	chart_box = {margin + 60, chart_y + 120, content - 92, 170}
	if count < 2 {
		write(margin + 24, chart_y + 190, 14, "Waiting for the price API...", THEME.colors.muted)
	} else {
		lo, hi := prices[0].close, prices[0].close
		if returns_mode {
			lo = 0
			hi = 0
		}
		for item in prices[:count] {
			v := item.daily_return * 100 if returns_mode else item.close
			lo = min(lo, v)
			hi = max(hi, v)
		}
		padding := max((hi - lo) * 0.15, 0.1)
		lo -= padding
		hi += padding
		for j in 0 ..< 5 {
			y := chart_box.y + f64(j) * chart_box.h / 4
			stroke(chart_box.x, y, chart_box.x + chart_box.w, y)
			write(margin + 10, y + 4, 10, fmt.tprintf("%.1f", hi - f64(j) * (hi - lo) / 4), THEME.colors.muted)
		}
		previous_x, previous_y: f64
		for item, i in prices[:count] {
			x := chart_box.x + f64(i) * chart_box.w / f64(count - 1)
			v := item.daily_return * 100 if returns_mode else item.close
			y := chart_box.y + (hi - v) / (hi - lo) * chart_box.h
			if returns_mode {
				zero := chart_box.y + hi / (hi - lo) * chart_box.h
				if item.has_return {
					fill({x - 8, min(y, zero), 16, max(2.0, abs(zero - y))}, THEME.colors.positive if v >= 0 else THEME.colors.negative, corner_radius = 0)
				}
			} else {
				if i > 0 {
					stroke(previous_x, previous_y, x, y, THEME.colors.positive, 2)
				}
				dot(x, y, 3, THEME.colors.positive)
			}
			if i == selected {
				stroke(x, chart_box.y, x, chart_box.y + chart_box.h, THEME.colors.muted)
				dot(x, y, 5, THEME.colors.text)
			}
			previous_x = x
			previous_y = y
		}
		write(chart_box.x, chart_y + 315, 11, prices[0].date, THEME.colors.muted)
		write(chart_box.x + chart_box.w - 78, chart_y + 315, 11, prices[count - 1].date, THEME.colors.muted)
		item := prices[selected]
		write(
			margin + 20,
			chart_y + 340,
			12,
			fmt.tprintf(
				"%s  |  Close %.2f  |  %s",
				item.date,
				item.close,
				fmt.tprintf("%+.2f%%", item.daily_return * 100) if item.has_return else "No prior close",
			),
		)
	}
}
