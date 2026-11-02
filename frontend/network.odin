package main

import finance "../shared/finance"
import ts "../shared/timeseries"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"

// Price requests, response ownership, and SSE lifecycle.
request :: proc(kind: int, url: string) {
	if pending[kind] {
		return
	}
	pending[kind] = true
	pending_age[kind] = 0
	fetch_text(i32(kind), raw_data(url), i32(len(url)))
}

refresh :: proc() {
	loading = true
	error_message = ""
	instruments := [2]string{"A", "B"}
    frequencies := [3]string{"daily", "weekly", "monthly"}
    joins := [3]string{"inner", "left", "outer"}
    starts := [3]string{"2026-01-01", "2026-01-01", "2026-04-01"}
    ends := [3]string{"2026-06-30", "2026-03-31", "2026-06-30"}
    windows := [3]int{3, 10, 20}
    request(0, fmt.tprintf("/api/research?instrument=%s&frequency=%s&join=%s&start=%s&end=%s&window=%d", instruments[instrument], frequencies[frequency], joins[join_policy], starts[range_choice], ends[range_choice], windows[window_choice]))
	dirty = true
}

@(export)
response_buffer :: proc "c" () -> rawptr {
	return &response_bytes[0]
}

@(export)
response_capacity :: proc "c" () -> i32 {
	return i32(len(response_bytes))
}

@(export)
receive :: proc "c" (kind, status, length: i32) {
	context = runtime.default_context()
	if kind < 0 ||
	   kind >= i32(len(pending)) ||
	   length < 0 ||
	   length > i32(len(response_bytes)) {
		return
	}
	pending[kind] = false
	dirty = true
	data := response_bytes[:int(length)]
	if kind == 0 {
		loading = false
		if status != 200 {
			error_message = "Price API unavailable. Start backend and Retry."
			return
		}
        result: finance.Research_Response
        if json.unmarshal(data, &result, allocator=context.temp_allocator) != nil || len(result.observations) > len(research_rows) {
            error_message = "The API returned an invalid research dataset."
            return
        }
        // Validate before publishing so errors preserve the previous dataset.
        for item, i in result.observations {
            _, date_ok := ts.parse_date(item.date)
            _, period_ok := ts.parse_date(item.period)
            if !date_ok || !period_ok || (i > 0 && item.period <= result.observations[i-1].period) { error_message = "Invalid research dates."; return }
            for value in ([8]ts.Value{item.close, item.benchmark, item.period_return, item.moving_average, item.volatility, item.wealth, item.excess_return, item.lagged_return}) {
                if value.valid && !ts.finite(value.value) { error_message = "Invalid research numbers."; return }
            }
        }
        count = len(result.observations)
        for item, i in result.observations {
            copy(research_dates[i][:], item.date)
            copy(research_periods[i][:], item.period)
            research_rows[i] = item
            research_rows[i].date = string(research_dates[i][:10])
            research_rows[i].period = string(research_periods[i][:10])
        }
        research_stats = {result.diagnostics.matched, result.diagnostics.discarded, result.diagnostics.left_only, result.diagnostics.right_only}
        selected = clamp(selected, 0, max(0,count-1))
        ledger_page = min(ledger_page, max(0,(count-1)/PAGE_SIZE))
        error_message = ""
        summary := fmt.tprintf("Odin research lab. Synthetic %s. %d observations, %d matched, %d discarded. Tab selects controls, Enter changes options, arrows inspect observations. Warm-up and missing values are gaps.", result.symbol, count, research_stats.matched, research_stats.discarded)
        label(raw_data(summary), i32(len(summary)))
	}
}

@(export)
event_received :: proc "c" (kind, length: i32) {
	context = runtime.default_context()
	if length < 0 || length > i32(len(response_bytes)) {return}
	dirty = true
	data := response_bytes[:int(length)]
	switch kind {
	case 0:
		// EventSource error: it will reconnect automatically.
		online = false
	case 1:
		ready: struct {
			build: string,
		}
		if json.unmarshal(data, &ready, allocator = context.temp_allocator) != nil ||
		   ready.build == "" {
			return
		}
		online = true
		backend_build_length = copy(backend_build[:], ready.build)
		// Each successful SSE connection refetches data, including reconnects
		// to the same backend after a temporary network interruption.
		refresh()
	case 2:
		when DEV_MODE {
			version: struct {
				frontend: string,
			}
			if json.unmarshal(data, &version, allocator = context.temp_allocator) == nil &&
			   version.frontend != "" &&
			   version.frontend != FRONTEND_BUILD {
				reload()
			}
		}
	}
}

update_requests :: proc(delta: f64) {
	for &age, i in pending_age {
		if pending[i] {
			age += delta
			if age > 8 {
				pending[i] = false
				if i == 0 {
					loading = false
					error_message = "Price request timed out. Please Retry."
				}
				dirty = true
			}
		}
	}
}
