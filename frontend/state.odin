package main

import finance "../shared/finance"

// State and theme shared by the frontend files in this Odin package.

// Colors grouped by their role in the interface.
Palette :: struct {
	// Canvas background and unselected table rows.
	background:         string,
	// Cards, chart panel, and the active observation row.
	panel:              string,
	// Inactive row hover: brighter than background, dimmer than panel.
	row_hover:          string,
	// Primary text, secondary labels, and grid/control surfaces.
	text, muted, grid:  string,
	// Positive values/connected status and negative values/error status.
	positive, negative: string,
}

Theme :: struct {
	colors:        Palette,
	// Default rectangle radius in CSS pixels; individual draws can override it.
	corner_radius: f64,
}

// Immutable visual defaults, separate from mutable application state below.
THEME :: Theme {
	colors = Palette {
		background = "#0c1420",
		panel = "#142132",
		row_hover = "#101b29",
		text = "#edf3f8",
		muted = "#93a7bb",
		grid = "#27374a",
		positive = "#76e0bb",
		negative = "#ff9b92",
	},
	corner_radius = 6,
}

// Canvas coordinates are CSS pixels. All loaded strings have owned storage.
Box :: struct { x,y,w,h: f64 }
MAX_ROWS :: 256
PAGE_SIZE :: 12
CONTROL_COUNT :: 9
research_rows: [MAX_ROWS]finance.Research_Row
research_dates, research_periods: [MAX_ROWS][16]u8
count, selected: int
instrument, frequency, join_policy, range_choice: int
window_choice: int = 1
chart_mode, ledger_page: int
research_stats: struct { matched, discarded, left_only, right_only: int }
loading, online: bool
error_message: string
backend_build: [64]u8
backend_build_length: int
response_bytes: [262144]u8
pending: [1]bool
pending_age: [1]f64
focus: int = -1
controls: [CONTROL_COUNT]Box
chart_box: Box
row_boxes: [MAX_ROWS]Box
hovered_row: int = -1
dirty := true
