package finance

import "core:fmt"
import "core:math"
import ts "../timeseries"

Research_Options :: struct {
    instrument: int,
    frequency: ts.Frequency,
    join: ts.Join,
    start: ts.Date,
    end: ts.Date,
    window: int,
}
Research_Row :: struct {
    date, period: string,
    close, benchmark, period_return, moving_average, volatility, wealth, excess_return, lagged_return: ts.Value,
    incomplete: bool,
}
Research_Response :: struct {
    symbol, benchmark_symbol, source: string,
    options: Research_Options,
    diagnostics: ts.Diagnostics,
    observations: []Research_Row,
}
// Deterministic six-month daily fixture. Distinct calendar omissions deliberately
// demonstrate alignment; these are not real exchange holiday calendars.
research_fixture :: proc(instrument: int) -> []ts.Point {
    points := make([dynamic]ts.Point)
    date := ts.Date(20260101)
    index: int
    for date <= ts.Date(20260630) {
        weekday := (ts.ordinal(date)-1)%7
        omit := (instrument == 0 && (date == ts.Date(20260119) || date == ts.Date(20260525))) || (instrument == 1 && (date == ts.Date(20260216) || date == ts.Date(20260403)))
        if weekday < 5 && !omit {
            price := 100 + f64(index)*0.15 + 3*math.sin(f64(index)*0.21)
            if instrument == 1 { price = 60 + f64(index)*0.08 + 2*math.cos(f64(index)*0.17) }
            append(&points, ts.Point{date, {price, true}})
        }
        index += 1
        date = ts.next_date(date)
    }
    return points[:]
}
// Caller chooses allocator, owns response and all derived allocations.
// Range and frequency are applied before joining; all windows count observations.
build_research :: proc(options: Research_Options) -> Research_Response {
    primary := research_fixture(options.instrument)
    benchmark := research_fixture(1-options.instrument)
    a := ts.resample(ts.slice_dates(primary, options.start, options.end), options.frequency)
    b := ts.resample(ts.slice_dates(benchmark, options.start, options.end), options.frequency)
    left := make([]ts.Point, len(a)); right := make([]ts.Point, len(b))
    for bar, i in a { left[i] = {bar.period, bar.value} }
    for bar, i in b { right[i] = {bar.period, bar.value} }
    aligned, diagnostics := ts.align(left, right, options.join)
    values := make([]ts.Value, len(aligned)); bench := make([]ts.Value, len(aligned))
    for r, i in aligned { values[i] = r.left; bench[i] = r.right }
    returns := period_returns(values)
    benchmark_returns := period_returns(bench)
    ma := rolling(values, options.window)
    vol := rolling(returns, options.window, true)
    previous := lag(returns, 1)
    excess, _ := excess_returns(returns, benchmark_returns, len(returns), 1)
    // First row establishes the wealth baseline, rather than a fictitious return.
    growth_input := make([]ts.Value, len(returns)); copy(growth_input, returns)
    if len(growth_input) > 0 && values[0].valid { growth_input[0] = {0, true} }
    equity := wealth(growth_input)
    rows := make([]Research_Row, len(aligned))
    for r, i in aligned {
        observed := r.date; incomplete := false
        for bar in a { if bar.period == r.date { observed = bar.observed; incomplete = bar.incomplete; break } }
        for bar in b { if bar.period == r.date { incomplete = incomplete || bar.incomplete; if !r.left.valid { observed = bar.observed }; break } }
        rows[i] = {date=fmt.tprintf("%s", ts.format_date(observed)), period=fmt.tprintf("%s", ts.format_date(r.date)), close=r.left, benchmark=r.right, period_return=returns[i], moving_average=ma[i], volatility=vol[i], wealth=equity[i], excess_return=excess[i], lagged_return=previous[i], incomplete=incomplete}
    }
    symbols := [2]string{"DEMO-A", "DEMO-B"}
    return {symbols[options.instrument], symbols[1-options.instrument], "synthetic six-month fixture; illustrative calendars", options, diagnostics, rows}
}
