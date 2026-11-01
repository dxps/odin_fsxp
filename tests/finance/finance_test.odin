package finance_test

import "core:math"
import "core:testing"
import finance "../../shared/finance"

@(test)
returns_and_invalid_prices :: proc(t: ^testing.T) {
    gain, gain_ok := finance.simple_return(100, 102)
    loss, loss_ok := finance.simple_return(100, 95)
    testing.expect(t, gain_ok && abs(gain - 0.02) < 1e-12)
    testing.expect(t, loss_ok && abs(loss + 0.05) < 1e-12)
    invalid := []f64{0, -1, math.nan_f64(), math.inf_f64(1)}
    for bad in invalid {
        _, previous_ok := finance.simple_return(bad, 100)
        _, current_ok := finance.simple_return(100, bad)
        testing.expect(t, !previous_ok && !current_ok)
    }
}

@(test)
fixture_compounds_to_total_return :: proc(t: ^testing.T) {
    growth: f64 = 1
    prices := finance.FIXTURE
    for i in 1..<len(prices) {
        r, ok := finance.simple_return(prices[i-1].close, prices[i].close)
        testing.expect(t, ok)
        growth *= 1 + r
    }
    testing.expect(t, abs(growth - 1.06) < 1e-12)
}
