package main

// Startup and frame lifecycle. Supporting files share this package.
DEV_MODE :: #config(DEV_MODE, false)
FRONTEND_BUILD :: #config(FRONTEND_BUILD, "manual")

main :: proc() {
	url: string = "/api/dev/events"
	connect_events(raw_data(url), i32(len(url)))
	refresh()
}

last_width, last_height: f64

@(export)
step :: proc(delta: f64) -> bool {
	update_requests(delta)
	width := max(360.0, viewport_width())
	height := viewport_height()
	if width != last_width || height != last_height {
		dirty = true
		last_width = width
		last_height = height
	}
	if dirty {
		render(width, height)
		dirty = false
	}
	free_all(context.temp_allocator)
	return true
}
