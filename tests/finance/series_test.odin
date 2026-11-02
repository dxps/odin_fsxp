package finance_test

import "core:testing"
import "core:mem"
import finance "../../shared/finance"
import ts "../../shared/timeseries"

@(test)
dates_alignment_and_slicing :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena)
    defer mem.dynamic_arena_destroy(&arena)
    context.allocator = mem.dynamic_arena_allocator(&arena)
    for s in ([]string{"2026-02-29","2026-13-01","2026-00-01","2026-01-00","2026-1-01","2026-aa-01"}) { _,ok := ts.parse_date(s); testing.expect(t,!ok) }
    leap,ok := ts.parse_date("2024-02-29"); testing.expect(t,ok && ts.next_date(leap)==20240301)
    testing.expect(t,ts.next_date(20261231)==20270101)
    a := []ts.Point{{20260701,{100,true}},{20260702,{102,true}}}
    b := []ts.Point{{20260702,{50,true}},{20260703,{51,true}}}
    testing.expect(t,ts.validate(a))
    invalid := []ts.Point{a[1],a[0]}; testing.expect(t,!ts.validate(invalid))
    testing.expect(t,len(ts.slice_dates(a,20260702,20260702))==1)
    inner,si := ts.align(a,b,.Inner)
    left,sl := ts.align(a,b,.Left)
    outer,so := ts.align(a,b,.Outer)
    testing.expect(t,len(inner)==1 && si.discarded==2 && si.matched==1)
    testing.expect(t,len(left)==2 && !left[0].right.valid && sl.discarded==1)
    testing.expect(t,len(outer)==3 && !outer[2].left.valid && so.discarded==0)
}
@(test)
rolling_compounding_and_causality :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena)
    defer mem.dynamic_arena_destroy(&arena)
    context.allocator = mem.dynamic_arena_allocator(&arena)
    returns := []ts.Value{{0.1,true},{0.1,true}}
    growth := finance.wealth(returns)
    testing.expect(t,abs(growth[1].value-121)<1e-10 && growth[1].valid)
    values := []ts.Value{{1,true},{2,true},{3,true},{4,true}}
    avg := finance.rolling(values,3)
    sd := finance.rolling(values,3,true)
    testing.expect(t,!avg[1].valid && avg[2].valid && avg[2].value==2)
    testing.expect(t,sd[2].valid && abs(sd[2].value-1)<1e-12)
    annual := finance.rolling(values,3,true,0,1,252)
    testing.expect(t,abs(annual[2].value*annual[2].value-252)<1e-10)
    lagged := finance.lag(values,1)
    testing.expect(t,!lagged[0].valid && lagged[2].value==2)
    values[3].value = 999
    changed := finance.rolling(values,3)
    testing.expect(t,changed[2]==avg[2])
    r := finance.period_returns([]ts.Value{{100,true},{110,true},{121,true}})
    testing.expect(t,!r[0].valid && abs(r[2].value-0.1)<1e-12)
    gap := []ts.Value{{0.1,true},{},{0.1,true}}
    broken := finance.wealth(gap); testing.expect(t,!broken[1].valid && !broken[2].valid)
    missing := []ts.Value{{1,true},{},{3,true}}
    full := finance.rolling(missing,3); partial := finance.rolling(missing,3,false,2)
    testing.expect(t,!full[2].valid && partial[2].valid && partial[2].value==2)
    excess,good := finance.excess_returns([]ts.Value{{0.1,true},{0.2,true},{0.3,true},{0.4,true}},[]ts.Value{{0.01,true},{}},2,2)
    testing.expect(t,good && abs(excess[0].value-0.09)<1e-12 && !excess[2].valid)
    _,bad := finance.excess_returns(values,returns,3,2); testing.expect(t,!bad)
}
@(test)
resampling_and_research_contract :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena)
    defer mem.dynamic_arena_destroy(&arena)
    context.allocator = mem.dynamic_arena_allocator(&arena)
    points := []ts.Point{{20260101,{100,true}},{20260130,{110,true}},{20260202,{115,true}},{20260227,{121,true}}}
    months := ts.resample(points,.Monthly)
    testing.expect(t,len(months)==2 && months[0].value.value==110 && months[0].observed==20260130 && months[0].period==20260101)
    testing.expect(t,months[1].incomplete)
    weeks := ts.resample([]ts.Point{{20260101,{1,true}},{20260102,{2,true}},{20260105,{3,true}}},.Weekly)
    testing.expect(t,len(weeks)==2 && weeks[0].period==20251229 && weeks[1].period==20260105)
    for frequency in ts.Frequency { for join in ts.Join {
        result := finance.build_research({start=20260101,end=20260630,window=3,frequency=frequency,join=join})
        testing.expect(t,len(result.observations)>0 && len(result.observations)<256)
        testing.expect(t,!result.observations[0].period_return.valid)
        if join == .Inner {
            last := result.observations[len(result.observations)-1]
            first := result.observations[0]
            testing.expect(t,last.wealth.valid && abs(last.wealth.value/100-last.close.value/first.close.value)<1e-10)
        }
    } }
    empty := finance.build_research({start=20260103,end=20260104,window=3})
    testing.expect(t,len(empty.observations)==0)
}
