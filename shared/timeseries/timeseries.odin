package timeseries

import "core:fmt"
import "core:math"

// Daily session date, not an intraday timestamp. Ordered as YYYYMMDD.
Date :: distinct int
Value :: struct { value: f64, valid: bool }
Point :: struct { date: Date, value: Value }
Join :: enum { Inner, Left, Outer }
Frequency :: enum { Daily, Weekly, Monthly }
Aligned :: struct { date: Date, left, right: Value }
Diagnostics :: struct { left_only, right_only, matched, discarded: int }
Bar :: struct { period, observed: Date, value: Value, incomplete: bool }

parse_date :: proc(s: string) -> (Date, bool) {
    if len(s) != 10 || s[4] != '-' || s[7] != '-' { return 0, false }
    n: int
    for c, i in s { if i == 4 || i == 7 { continue }; if c < '0' || c > '9' { return 0, false }; n = n*10 + int(c-'0') }
    y, m, d := n/10000, n/100%100, n%100
    if y < 1 || m < 1 || m > 12 { return 0, false }
    days := [12]int{31,28,31,30,31,30,31,31,30,31,30,31}
    limit := days[m-1]
    if m == 2 && (y%400 == 0 || (y%4 == 0 && y%100 != 0)) { limit = 29 }
    return Date(n), d >= 1 && d <= limit
}
format_date :: proc(d: Date) -> string { n := int(d); return fmt.tprintf("%04d-%02d-%02d", n/10000, n/100%100, n%100) }
finite :: proc(v: f64) -> bool { return !math.is_nan(v) && !math.is_inf(v) }
validate :: proc(points: []Point) -> bool {
    for p, i in points {
        if _, ok := parse_date(format_date(p.date)); !ok { return false }
        if i > 0 && p.date <= points[i-1].date { return false }
        if p.value.valid && !finite(p.value.value) { return false }
    }
    return true
}
// Inclusive date slice; input must be validated and sorted.
slice_dates :: proc(points: []Point, start, end: Date) -> []Point {
    a, b := 0, len(points)
    for a < b && points[a].date < start { a += 1 }
    for b > a && points[b-1].date > end { b -= 1 }
    return points[a:b]
}
// Outputs use the caller's allocator. Inputs must have sorted, unique dates.
align :: proc(left, right: []Point, policy: Join) -> ([]Aligned, Diagnostics) {
    rows := make([dynamic]Aligned)
    stats: Diagnostics
    i, j: int
    for i < len(left) || j < len(right) {
        if i < len(left) && j < len(right) && left[i].date == right[j].date {
            append(&rows, Aligned{left[i].date, left[i].value, right[j].value}); stats.matched += 1; i += 1; j += 1
        } else if i < len(left) && (j == len(right) || left[i].date < right[j].date) {
            stats.left_only += 1
            if policy != .Inner { append(&rows, Aligned{date=left[i].date, left=left[i].value}) } else { stats.discarded += 1 }
            i += 1
        } else {
            stats.right_only += 1
            if policy == .Outer { append(&rows, Aligned{date=right[j].date, right=right[j].value}) } else { stats.discarded += 1 }
            j += 1
        }
    }
    return rows[:], stats
}
// Gregorian ordinal enables deterministic weekly grouping (Monday through Sunday).
ordinal :: proc(date: Date) -> int {
    n := int(date); y, m, d := n/10000, n/100%100, n%100
    offsets := [12]int{0,31,59,90,120,151,181,212,243,273,304,334}
    prev := y-1
    result := 365*prev + prev/4-prev/100+prev/400 + offsets[m-1]+d
    if m > 2 && (y%400 == 0 || (y%4 == 0 && y%100 != 0)) { result += 1 }
    return result
}
next_date :: proc(date: Date) -> Date {
    n := int(date)
    if d, ok := parse_date(format_date(Date(n+1))); ok { return d }
    y, m := n/10000, n/100%100
    if m == 12 { return Date((y+1)*10000+101) }
    return Date(y*10000+(m+1)*100+1)
}
period_key :: proc(d: Date, frequency: Frequency) -> int {
    switch frequency { case .Daily: return int(d); case .Monthly: return int(d)/100; case .Weekly: return (ordinal(d)-1)/7 }
    return 0
}
// Last observation per period, including missing values; never silently forward fills.
// First/final partial periods are marked conservatively using calendar boundaries.
resample :: proc(points: []Point, frequency: Frequency) -> []Bar {
    bars := make([dynamic]Bar)
    for p, i in points {
        key := period_key(p.date, frequency)
        if i == 0 || key != period_key(points[i-1].date, frequency) {
            append(&bars, Bar{period=p.date, observed=p.date, value=p.value})
        } else { bars[len(bars)-1].observed = p.date; bars[len(bars)-1].value = p.value }
    }
    for &b, i in bars {
        if frequency == .Monthly { b.period = Date(int(b.period)/100*100+1) }
        if frequency == .Weekly {
            // Find Monday's calendar date without timezone conversion.
            n := b.period
            for ordinal(n)%7 != 1 { // ordinal 1 is Monday
                raw := int(n)-1
                if _, ok := parse_date(format_date(Date(raw))); ok { n = Date(raw) } else {
                    month := int(n)/100%100; year := int(n)/10000
                    if month == 1 { year -= 1; month = 12 } else { month -= 1 }
                    n = Date(year*10000+month*100+28)
                    for period_key(next_date(n), .Monthly) == period_key(n, .Monthly) { n = next_date(n) }
                }
            }
            b.period = n
        }
        if frequency != .Daily {
            b.incomplete = (i == 0 && points[0].date != b.period) || (i == len(bars)-1 && period_key(next_date(b.observed), frequency) == period_key(b.observed, frequency))
        }
    }
    return bars[:]
}
