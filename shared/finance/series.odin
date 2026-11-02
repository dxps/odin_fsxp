package finance

import "core:math"
import ts "../timeseries"

// Series procedures allocate output with context.allocator; caller owns output.
// Missing values propagate. Rates are fractions, never percentages.
lag :: proc(values: []ts.Value, periods: int) -> []ts.Value {
    out := make([]ts.Value, len(values))
    if periods < 0 { return out }
    for i in periods..<len(values) { out[i] = values[i-periods] }
    return out
}
period_returns :: proc(values: []ts.Value, periods := 1) -> []ts.Value {
    out := make([]ts.Value, len(values))
    if periods < 1 { return out }
    for i in periods..<len(values) {
        if values[i].valid && values[i-periods].valid {
            out[i].value, out[i].valid = simple_return(values[i-periods].value, values[i].value)
        }
    }
    return out
}
// Trailing inclusive windows. min_count=0 requires a complete window.
// Variance uses a two-pass calculation for stability, with explicit ddof.
rolling :: proc(values: []ts.Value, window: int, standard_deviation := false, min_count := 0, ddof := 1, annualization: f64 = 1) -> []ts.Value {
    out := make([]ts.Value, len(values))
    required := min_count
    if required == 0 { required = window }
    if window < 1 || required < 1 || required > window || ddof < 0 || !ts.finite(annualization) || annualization <= 0 { return out }
    for i in 0..<len(values) {
        n: int; mean: f64
        for v in values[max(0,i-window+1):i+1] { if v.valid && ts.finite(v.value) { n += 1; mean += (v.value-mean)/f64(n) } }
        if n < required { continue }
        value := mean
        if standard_deviation {
            if n <= ddof { continue }
            sum: f64
            for v in values[max(0,i-window+1):i+1] { if v.valid && ts.finite(v.value) { sum += (v.value-mean)*(v.value-mean) } }
            value = math.sqrt(sum/f64(n-ddof))*math.sqrt(annualization)
        }
        out[i] = {value, ts.finite(value)}
    }
    return out
}
// Wealth starts at 100 before the first return. An unknown return breaks the
// remaining path: skipping it would misrepresent cumulative performance.
wealth :: proc(returns: []ts.Value) -> []ts.Value {
    out := make([]ts.Value, len(returns))
    growth: f64 = 100
    known := true
    for r, i in returns {
        if !r.valid || !ts.finite(r.value) || r.value < -1 { known = false }
        if known { growth *= 1+r.value; known = ts.finite(growth) }
        out[i] = {growth if known else 0, known}
    }
    return out
}
// Row-major matrix, labels/dates retained by the caller. Shape mismatch fails.
excess_returns :: proc(values: []ts.Value, benchmark: []ts.Value, rows, columns: int) -> ([]ts.Value, bool) {
    if rows < 0 || columns < 1 || len(benchmark) != rows || rows > len(values)/columns || len(values) != rows*columns { return nil, false }
    out := make([]ts.Value, len(values))
    for b, row in benchmark { for col in 0..<columns { i := row*columns+col; if b.valid && values[i].valid { v := values[i].value-b.value; out[i] = {v, ts.finite(v)} } } }
    return out, true
}
