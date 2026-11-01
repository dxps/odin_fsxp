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

// Shared API types and canvas geometry.
// Aliases keep the browser and native backend on the same JSON contract.
Observation :: finance.Observation
Price_Response :: finance.Price_Response
// Top-left position and dimensions in CSS pixels, shared by drawing and hit tests.
Box :: struct {
	x, y, w, h: f64,
}

// Loaded dataset and current observation.
// Fixed-capacity dataset; only prices[:count] contains loaded observations.
prices: [128]Observation
// Dates are copied out of the temporary JSON allocator before it is reset.
// Each loaded prices[i].date refers to the corresponding owned dates[i] bytes.
dates: [128][16]u8
// Number of valid observations, initially zero while the first request loads.
count: int
// Zero-based active observation, shared by the ledger and chart selection marker.
// Updated by row clicks, chart inspection, and left/right arrow keys.
selected: int

// UI and connection status.
// Selects the chart's daily-return bars instead of closing-price lines.
returns_mode: bool
// Indicates a price refresh is in progress; also dims the refresh icon.
loading: bool
// SSE connection status, set by backend-ready events and transport errors.
online: bool
// User-visible price request/validation error; the previous dataset is retained.
error_message: string
// Owned copy of the backend build ID received over SSE, displayed in the footer.
backend_build: [64]u8
// Valid byte count within backend_build; the buffer is not a C string.
backend_build_length: int

// Browser response buffer and the single in-flight price request (kind 0).
// JS writes HTTP/SSE payloads here before invoking the matching Odin callback.
// Callbacks parse this reusable buffer and copy anything needed across frames.
response_bytes: [65536]u8
// Prevents duplicate price requests while request kind 0 is already in flight.
pending: [1]bool
// Elapsed seconds per pending request, used by the eight-second timeout check.
pending_age: [1]f64

// Keyboard focus, hit-test bounds, and redraw flag.\
// - `-1`: none;
// - `0`: refresh;
// - `1`: price chart control;
// - `2`: returns chart control.\
// Pointer clicks clear this indicator; Tab navigation sets it.
focus: int = -1
// Bounds refreshed during rendering and reused by pointer input handling.
refresh_box, price_box, return_box, chart_box: Box
// Row hit-test bounds; only row_boxes[:count] participates in pointer selection.
row_boxes: [len(prices)]Box
// Pointer's current row index, or -1 outside the rows; independent of selected.
hovered_row: int = -1
// Requests a redraw on the next animation frame after state/input/layout changes.
// Starts true to paint the initial loading view; step() clears it after rendering.
dirty := true
