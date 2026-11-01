package main

import finance "../shared/finance"
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
	request(0, "/api/prices")
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
		result: Price_Response
		if json.unmarshal(data, &result, allocator = context.temp_allocator) != nil ||
		   len(result.observations) < 2 ||
		   len(result.observations) > len(prices) {
			error_message = "The API returned an invalid price dataset."
			return
		}
		for item in result.observations {
			if _, valid := finance.simple_return(item.close, item.close);
			   !valid || len(item.date) > len(dates[0]) {
				error_message = "The API returned invalid prices or dates."
				return
			}
		}
		count = len(result.observations)
		for item, i in result.observations {
			copy(dates[i][:], item.date)
			prices[i] = item
			prices[i].date = string(dates[i][:len(item.date)])
			if i > 0 {
				prices[i].daily_return, prices[i].has_return = finance.simple_return(
					prices[i - 1].close, item.close,
				)
			} else {
				prices[i].has_return = false
			}
		}
		selected = min(selected, count - 1)
		error_message = ""
		summary := fmt.tprintf(
			"Odin research lab. Synthetic DEMO dataset. %d observations. Latest close %.2f. Tab selects controls, Enter activates, arrow keys inspect prices.",
			count,
			prices[count - 1].close,
		)
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
