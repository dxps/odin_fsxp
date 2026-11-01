package main

// Canvas primitives and reusable controls. Coordinates are in CSS pixels.
// Radius is configurable per rectangle; 0 draws square corners.
fill :: proc(box: Box, color: string, corner_radius: f64 = DEFAULT_CORNER_RADIUS, top_corners_only := false) {
	radius := clamp(corner_radius, 0, max(0.0, min(box.w, box.h) / 2))
	rect(box.x, box.y, box.w, box.h, radius, 1 if top_corners_only else 0, raw_data(color), i32(len(color)))
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
		fill({b.x - 2, b.y - 2, b.w + 4, b.h + 4}, GREEN, DEFAULT_CORNER_RADIUS + 2)
	}
	fill(b, GRID if active else PANEL)
	write(b.x + 14, b.y + 25, 13, title, GREEN if active else INK)
}

refresh_icon :: proc(b: Box) {
	if focus == 0 {
		fill({b.x - 2, b.y - 2, b.w + 4, b.h + 4}, GREEN, DEFAULT_CORNER_RADIUS + 2)
		fill(b, BG)
	}
	color := MUTED if loading else RED if error_message != "" else GREEN
	// One continuous Bezier path avoids seams between tiny line segments.
	// Geometry is defined in a centered 24-by-24 icon space, entirely in Odin.
	x, y := b.x + b.w / 2 - 12, b.y + b.h / 2 - 12
	path_begin()
	path_move(x + 20, y + 12)
	path_curve(x + 20, y + 16.418, x + 16.418, y + 20, x + 12, y + 20)
	path_curve(x + 7.582, y + 20, x + 4, y + 16.418, x + 4, y + 12)
	path_curve(x + 4, y + 7.582, x + 7.582, y + 4, x + 12, y + 4)
	path_curve(x + 15, y + 4, x + 17.6, y + 5.6, x + 19, y + 8)
	path_move(x + 19, y + 3)
	path_line(x + 19, y + 8)
	path_line(x + 14, y + 8)
	path_stroke(2, raw_data(color), i32(len(color)))
}
