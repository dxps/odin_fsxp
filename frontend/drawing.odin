package main

import "core:math"

// Canvas primitives and reusable controls. Coordinates are in CSS pixels.
fill :: proc(box: Box, color: string) {
	rect(box.x, box.y, box.w, box.h, raw_data(color), i32(len(color)))
}

write :: proc(x, y, size: f64, value: string, color := INK) {
	text(x, y, size, raw_data(value), i32(len(value)), raw_data(color), i32(len(color)))
}

stroke :: proc(x1, y1, x2, y2: f64, color := GRID, width: f64 = 1) {
	line(x1, y1, x2, y2, width, raw_data(color), i32(len(color)))
}

dot :: proc(x, y, radius: f64, color: string) {
	circle(x, y, radius, raw_data(color), i32(len(color)))
}

inside :: proc(box: Box, x, y: f64) -> bool {
	return x >= box.x && x <= box.x + box.w && y >= box.y && y <= box.y + box.h
}

button :: proc(b: Box, title: string, active: bool, index: int) {
	if focus == index {
		fill({b.x - 2, b.y - 2, b.w + 4, b.h + 4}, GREEN)
	}
	fill(b, GRID if active else PANEL)
	write(b.x + 14, b.y + 25, 13, title, GREEN if active else INK)
}

refresh_icon :: proc(b: Box) {
	if focus == 0 {
		fill({b.x - 2, b.y - 2, b.w + 4, b.h + 4}, GREEN)
		fill(b, BG)
	}
	color := MUTED if loading else RED if error_message != "" else GREEN
	cx, cy := b.x + b.w / 2, b.y + b.h / 2
	// Two opposing curved arrows, with arrowheads aligned to each arc's tangent.
	radius: f64 = 8.5
	for arrow in 0 ..< 2 {
		start := (-165.0 + f64(arrow) * 180) * math.PI / 180
		end := start + 150 * math.PI / 180
		previous_x, previous_y := cx + radius * math.cos(start), cy + radius * math.sin(start)
		dot(previous_x, previous_y, 1, color)
		for i in 1 ..= 24 {
			angle := start + f64(i) / 24 * (end - start)
			x, y := cx + radius * math.cos(angle), cy + radius * math.sin(angle)
			stroke(previous_x, previous_y, x, y, color, 2)
			previous_x = x
			previous_y = y
		}
		nx, ny := math.cos(end), math.sin(end)
		tx, ty := -ny, nx
		sides := [2]int{-1, 1}
		for side in sides {
			wing_x := previous_x - 5 * tx + f64(side) * 3.5 * nx
			wing_y := previous_y - 5 * ty + f64(side) * 3.5 * ny
			stroke(wing_x, wing_y, previous_x, previous_y, color, 2)
			dot(wing_x, wing_y, 1, color)
		}
		dot(previous_x, previous_y, 1, color)
	}
}
