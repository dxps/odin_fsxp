package finance

import "core:math"

Price :: struct {
    date: string,
    close: f64,
}

// HTTP contract shared by the native server and WASM client.
Observation :: struct {
    date: string,
    close: f64,
    daily_return: f64,
    has_return: bool,
}

Price_Response :: struct {
    symbol, source: string,
    observations: []Observation,
}

// Synthetic, fixed prices for learning and reproducible tests; not market data.
FIXTURE :: [6]Price{
    {"2026-01-05", 100},
    {"2026-01-06", 102},
    {"2026-01-07", 101},
    {"2026-01-08", 104},
    {"2026-01-09", 103},
    {"2026-01-12", 106},
}

simple_return :: proc "contextless" (previous, current: f64) -> (value: f64, ok: bool) {
    if previous <= 0 || current <= 0 ||
       math.is_nan(previous) || math.is_nan(current) ||
       math.is_inf(previous) || math.is_inf(current) {
        return 0, false
    }
    value = current / previous - 1
    return value, !math.is_inf(value)
}
