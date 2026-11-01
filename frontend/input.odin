package main

import "base:runtime"
import "core:math"

// Pointer and keyboard actions; browser event translation stays in `bridge.js`.
@(export)
pointer :: proc "c" (x, y: f64, down: i32) {
	context = runtime.default_context()
	hovered_row = -1
	for box, i in row_boxes[:count] {
		if inside(box, x, y) {
			hovered_row = i
			break
		}
	}
	set_pointer_cursor(1 if inside(refresh_box, x, y) || hovered_row >= 0 else 0)
	if down != 0 {
		// Pointer input does not retain the keyboard focus indicator.
		focus = -1
		if hovered_row >= 0 {
			selected = hovered_row
		}
		if inside(refresh_box, x, y) {
			refresh()
		}
		if inside(price_box, x, y) {
			returns_mode = false
		}
		if inside(return_box, x, y) {
			returns_mode = true
		}
	}
	if count > 1 && inside(chart_box, x, y) {
		position := (x - chart_box.x) / chart_box.w
		selected = clamp(int(math.round(position * f64(count - 1))), 0, count - 1)
	}
	dirty = true
}

// Codes are supplied by the browser adapter: left, right, Tab, and activate.
@(export)
key :: proc "c" (code, shift: i32) -> i32 {
	context = runtime.default_context()
	switch code {
	case 1:
		selected = max(0, selected - 1)
	case 2:
		selected = min(max(0, count - 1), selected + 1)
	case 3:
		if shift != 0 {
			if focus <= 0 {
				focus = -1
				dirty = true
				return 0
			}
			focus -= 1
		} else {
			if focus == 2 {
				focus = -1
				dirty = true
				return 0
			}
			focus += 1
		}
	case 4:
		if focus == 0 {
			refresh()
		}
		if focus == 1 {
			returns_mode = false
		}
		if focus == 2 {
			returns_mode = true
		}
	case:
		return 0
	}
	dirty = true
	return 1
}
