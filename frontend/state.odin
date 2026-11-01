package main

import finance "../shared/finance"

// State and theme shared by the frontend files in this Odin package.
// Palette.
BG :: "#0c1420"
PANEL :: "#142132"
INK :: "#edf3f8"
MUTED :: "#93a7bb"
GRID :: "#27374a"
GREEN :: "#76e0bb"
RED :: "#ff9b92"

// Shared API types and canvas geometry.
Observation :: finance.Observation
Price_Response :: finance.Price_Response
Box :: struct {
	x, y, w, h: f64,
}

// Loaded dataset and current observation.
prices: [128]Observation
// Dates are copied out of the temporary JSON allocator before it is reset.
dates: [128][16]u8
count, selected: int

// UI and connection status.
returns_mode, loading, online: bool
error_message: string
backend_build: [64]u8
backend_build_length: int

// Browser response buffer and the single in-flight price request (kind 0).
response_bytes: [65536]u8
pending: [1]bool
pending_age: [1]f64

// Keyboard focus, hit-test bounds, and redraw flag.
focus: int = -1
refresh_box, price_box, return_box, chart_box: Box
dirty := true

