package main

// Browser host ABI; implemented by web/bridge.js.
foreign import browser "browser"
@(default_calling_convention = "c")
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
	connect_events :: proc(url: rawptr, length: i32) ---
}
