# Milestone 01: Odin native backend and browser UI

Implemented and verified: 2026-11-01.

## Runtime decision

Odin's supported browser target requires JavaScript host infrastructure. The
user approved minimal runtime glue while keeping all application code in Odin.
The delivered browser assets are:

- `frontend.wasm`: Odin application state, input actions, layout, charts, JSON
  parsing, financial calculations, SSE event handling, and reload decisions.
- `odin.js`: official runtime copied from the installed compiler's
  `core/sys/wasm/js/odin.js` during each frontend build.
- `bridge.js`: browser host adapter for canvas primitives, HTTP fetch, input,
  viewport dimensions, WASM startup, and page reload. No financial or UI logic.
- `index.html`: canvas host and script references, without HTML UI controls or
  an authored stylesheet.

References:

- [Odin browser runtime](https://github.com/odin-lang/Odin/blob/master/core/sys/wasm/README.md)
- [Official browser example](https://pkg.odin-lang.org/examples/wasm/js_wasm32/)

## Toolchain

Verified with Homebrew Odin `dev-2026-10:84bc3fc21`, Homebrew LLD 23.1.4, and
Chrome on macOS/Apple Silicon. Both native and WASM targets compile and link.
The project currently uses the installed toolchain rather than enforcing a
specific compiler version. See the root readme for installation commands.

## Implemented foundation

- `shared/finance`: synthetic price fixture, API contract, and validated simple
  returns. Both native and WASM targets import this package.
- `backend`: HTTP health and price endpoints, SSE stream, and explicitly listed
  static assets. Bounded concurrent workers; loopback address by default.
- `frontend`: responsive Canvas 2D dashboard with price/return charts, metrics,
  observation inspection, ledger, refresh/retry, and backend connection status.
- `tools/dev`: Odin builds/tests and source-content polling, with independent
  backend and frontend watcher modes or a combined runner.

The backend serves both API and browser assets from one origin; a separate
frontend HTTP server is unnecessary. The frontend watcher runs independently
when desired. A successful frontend build publishes a new version marker;
the backend samples the local marker and pushes changes over one SSE
connection. Odin handles these events and refreshes on version changes.
EventSource reconnects after backend restarts or connection interruptions;
Odin then refetches prices. Browsers do not poll health or version endpoints.

Backend reload is rebuild/restart. Frontend reload is a page refresh. Neither
preserves in-memory state across replacement. Failed compilations retain the
last working process/artifact. Source changes to the runner require restarting
it once.

## Verification

- Native backend, Odin development runner, and WASM frontend compile.
- Finance tests pass for gains, losses, invalid prices, and compounded returns.
- Local HTTP checks verify health, fixture responses, unknown routes, and
  rejected methods. Browser execution verifies WASM loading and asset serving.
- Chrome checks verify the fixture's +6% total return and 106 latest close,
  chart switching, keyboard observation selection, and desktop/phone layouts.
- Blocking the price API produces Retry while preserving the last dataset;
  unblocking and retrying recovers.
- An isolated updated runner verifies that source edits automatically rebuild
  and reload the browser. Intentionally invalid frontend source preserves the
  WASM artifact/version and running UI; fixing it triggers a successful reload.
- Prior native reload checks verified continued serving after a failed backend
  compilation and recovery after the error was fixed.
- SSE checks verify initial events, version change notifications, heartbeats,
  concurrent API/asset requests, stream limits, and slot reuse after disconnect.
- Browser SSE checks cover no health/version polling, rebuild notifications,
  backend restart/reconnection, and recovery after a temporary server outage.

## Current limits

Data is synthetic. Historical data ingestion, strategy backtesting, and
persistence are later increments. The HTTP server is a bounded, concurrent
local-development server. The canvas supplies keyboard controls and a summary,
with full semantic accessibility still to be developed.
