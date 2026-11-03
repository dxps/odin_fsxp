# Milestone 02: Quantitative workflow lab

This milestone implements an Odin quantitative workflow.

<br/>

## Try it

Keep `./run_dev.sh` running and open <http://127.0.0.1:8080/>.

Click a control repeatedly to cycle its choices:

- Asset: A or B; the other instrument is the benchmark.
- Frequency: daily, weekly, monthly.
- Range: January–June, January–March, April–June 2026.
- Join: inner, left, outer.
- Window: 3, 10, 20 observations at the selected frequency.
- Chart: close with moving average, period returns, rolling volatility,
  wealth index, calendar comparison.

Use Previous/Next page to navigate the 12-row ledger. Hover the chart or click
ledger rows to inspect observations. Arrow keys move selection and its ledger
page. With the canvas focused, Tab/Shift-Tab navigate controls and Enter/Space
activate them. Refresh retries a failed request and retains the last dataset
while loading or on failure. Data-affecting controls are locked during a request.

The comparison chart shows raw instrument prices, not normalized performance.
Blue denotes the moving average in the price chart and the benchmark in the
comparison chart. Green denotes the selected instrument. Gaps and `--` mean
unavailable values, including rolling-window warm-up. Asterisks indicate partial
periods. Volatility is per period, with no annualization in the UI.

Monthly data contains only six observations: select window 3 to see a rolling
average/volatility. A ten-period window correctly produces no monthly estimates.

<br/>

## Data and calculation flow

```text
Deterministic synthetic daily series (two illustrative calendars)
  -> inclusive date-range slice
  -> daily / weekly / monthly last-observation aggregation
  -> explicit period-key alignment and diagnostics
  -> returns, trailing statistics, lagged returns, excess returns, wealth
  -> bounded JSON response
  -> WASM validation and owned state
  -> canvas charts, summary, and paginated ledger
```

The fixture covers January 1 through June 30, 2026. Weekends are excluded.
DEMO-A additionally omits January 19 and May 25; DEMO-B omits February 16 and
April 3. These are deliberately illustrative calendars, not exchange calendars.
Prices use fixed mathematical functions, with no random seed or network source.
Full-range daily joins have 125 matched dates and four unmatched dates in total.

### Time-series contract

`shared/timeseries/timeseries.odin` provides:

- Gregorian daily dates, represented internally as ordered `YYYYMMDD` integers;
  strict `YYYY-MM-DD` parsing and formatting at boundaries.
- Sorted, unique date validation, inclusive slicing, and finite-value checks.
- Values with an explicit validity flag. Missing values are never zero-filled.
- Inner joins (intersection), left joins (primary calendar), and outer joins
  (union), with matched, left-only, right-only, and discarded-row counts.
- Resampling to daily, Monday–Sunday weekly, or calendar-month buckets, keeping
  the last observation in each bucket, including its missing-value state.

Daily series retain their session dates. Monthly period keys use the first day
of the month and weekly keys use Monday. These are bucket identifiers, not
trade/execution dates. Each response row also includes the actual primary
observation date; a benchmark-only row uses its benchmark observation date.

First/final partial periods are marked conservatively against calendar
boundaries. Without real exchange calendars, a final Friday or month-end
weekday before a weekend can be marked partial even if the market period was
complete. Missing entire periods are not fabricated. No forward/backward fill
occurs. Joining by period does not imply both instruments closed simultaneously.

### Numerical contract

`shared/finance/series.odin` contains reusable, UI-independent procedures:

| Procedure | Definition and behavior |
| --- | --- |
| `period_returns` | `price[t] / price[t-lag] - 1`; default lag 1; both prices must be finite and positive. |
| `lag` | Positive observation lag; unavailable leading rows. Negative shifts yield unavailable output. |
| `rolling` mean | Trailing inclusive arithmetic mean. Default requires every observation in the window. Optional minimum count is explicit. |
| `rolling` standard deviation | Two-pass sample standard deviation by default (`ddof=1`); population convention is available with `ddof=0`. Optional annualization multiplies by the square root of the supplied periods-per-year. |
| `wealth` | `100 * product(1 + return)`; missing or invalid returns invalidate the remainder of the path. Returns of -100% are supported by this generic return-series procedure. |
| `excess_returns` | Row-wise subtraction of benchmark returns from a row-major asset matrix, with explicit row/column dimensions and validity propagation. Shape mismatch fails. |

Return values are decimal fractions; percentages are presentation only.
The first research row establishes wealth at 100 without claiming a measured
first-period return. Cumulative return displayed in percent is `wealth - 100`.
The research endpoint uses sample volatility without annualization.

Alignment precedes returns: an inner join measures returns between consecutive
retained observations, which may span multiple original sessions. A left/outer
join retains missing values; returns requiring those values remain unavailable.
An unknown return breaks wealth rather than silently skipping a period.
The range is sliced before calculating indicators, so each selected range has
its own warm-up and wealth baseline. Window lengths count observations, not
calendar days. Lagged return at row t uses the return from row t-1.

Outputs use `context.allocator`. The research pipeline is intended to run inside
an arena or request-scoped allocator: intermediate arrays share that lifetime.
The HTTP handler uses its worker's temporary allocator and releases it when
that worker ends. Tests use explicit arenas and verify clean memory tracking.
Dates/labels remain metadata alongside numeric arrays. No NumPy-style general
broadcasting engine is introduced; the supported matrix operation validates its
shape. Computation uses compiled loops and contiguous arrays; SIMD and parallel
execution should follow measured need.

<br/>

## API

`GET /api/research` accepts these optional parameters:

| Parameter | Values | Default |
| --- | --- | --- |
| `instrument` | `A`, `B` | `A` |
| `frequency` | `daily`, `weekly`, `monthly` | `daily` |
| `join` | `inner`, `left`, `outer` | `inner` |
| `start` | Valid daily date within fixture | `2026-01-01` |
| `end` | Valid daily date within fixture, not before start | `2026-06-30` |
| `window` | Integer 2–60 | `10` |

Example:

```sh
curl 'http://127.0.0.1:8080/api/research?instrument=A&frequency=monthly&join=inner&window=3'
```

The response contains instrument/source metadata, effective options, alignment
diagnostics, and observations. Each row includes `date`, `period`, `incomplete`,
and `{value, valid}` objects for `close`, `benchmark`, `period_return`,
`moving_average`, `volatility`, `wealth`, `excess_return`, and `lagged_return`.
Ignore `value` whenever `valid` is false. Dates use ISO daily strings;
frequency/join in the effective options are enum ordinals, in the table's order.

Unknown/duplicate keys, unsupported choices, invalid dates, reversed/out-of-range
ranges, and invalid window sizes return HTTP 400. A valid range containing no
observations returns an empty dataset. Query values are intentionally simple
ASCII tokens; URL-encoded equivalents are not decoded.

`/api/prices` retains the original six-observation fixture contract. Health,
static assets, and development SSE endpoints remain available.

<br/>

## Frontend bounds and behavior

The research frontend owns at most 256 rows and a 256 KiB response buffer,
covering the bounded six-month fixture. Dates and period strings are copied out
of temporary JSON storage. The ledger renders 12 rows at a time. Larger datasets
require a deliberate API/storage change; they are rejected rather than truncated.

The server computes derived data through the shared Odin packages; the browser
renders the returned calculations. Canvas controls and interaction remain Odin;
JavaScript continues to supply only browser host infrastructure.
The screen-reader summary reports dataset and join counts, but the canvas still
does not expose every control and table cell as separate semantic elements.

<br/>

## Verification and development discipline

Run:

```sh
odin run tools/dev -- test
```

Tests cover invalid/leap dates, year/month transitions, sorted date validation,
inclusive slicing, join policies and missing flags, rolling warm-up and minimum
counts, sample deviation and annualization, lagging, return calculation,
compounding 10% twice to 121, missing-return propagation, matrix dimensions,
monthly last-price aggregation, weekly year-boundary grouping, partial periods,
all frequency/join combinations, and empty datasets. A causality check changes a
future input and verifies an earlier trailing statistic remains unchanged.

Native backend and WASM frontend builds are also required. Browser/API checks
exercise controls, responsive layouts, failure/retry, strict invalid query
handling, and compatibility of `/api/prices`.

For future AI-assisted work, specify each calculation's formula, input/output
shape, date conventions, missing-value policy, units, and known expected results
before implementation. Verify the resulting calculations and record assumptions
here. The chapter's example prompts are source material, not project permissions
or instructions. Small reviewed commits provide rollback points.

<br/>

## Scope remaining after this milestone

Live provider adapters, storage, real market calendars/timezones, adjusted-price
policies, strategy execution timing, full backtesting, transaction costs, machine
learning, and deployment are separate increments. Indicators here are research
outputs; no orders or tradable strategy are generated.

### Recorded results

- All five finance tests passed with no memory-tracking warnings.
- Native backend and WASM frontend compiled successfully; no concurrent build
  runner was started, and verification builds used separate temporary outputs.
- Live API checks passed for all nine frequency/join combinations, nine invalid
  query cases, and the original six-observation `/api/prices` response.
- Chrome checks passed for initial WASM loading, instrument/frequency changes,
  keyboard activation, chart-mode cycling, and failed request/retry recovery,
  with no JavaScript page errors.
- Desktop (1200 px) and mobile (390 px) screenshots were visually inspected.
