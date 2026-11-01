# Odin Financial Research Platform

A personal financial research and trading platform built in Odin.

The targets are a native backend and an Odin WebAssembly frontend.
The first increment includes a native HTTP API, shared financial calculations,
an Odin development runner, and a canvas UI rendered by Odin/WASM. See
[Milestone 01](docs/milestone-01-feasibility.md) for findings and the proposed
development workflow.

<br/>

## Prerequisites

### In macOS

1. **Xcode Command Line Tools** — provide the native compiler, linker, macOS SDK,
   and Git. Install them and complete the installation dialog:

   ```sh
   xcode-select --install
   ```

   If already installed, verify the selected developer directory:

   ```sh
   xcode-select -p
   git --version
   ```

2. **Homebrew** — used to install the Odin toolchain. Follow the instructions at
   [brew.sh](https://brew.sh/), including its shell setup instructions so `brew`
   is available on `PATH`.

3. **Odin and LLD** — Odin compiles the native backend and WASM frontend;
   LLD provides `wasm-ld`, required to link WebAssembly builds:

   ```sh
   brew install odin lld
   ```

   Verify that both executables are available:

   ```sh
   odin version
   wasm-ld --version
   ```

   `wasm-ld` belongs to **LLD**, not `wasm-tools`. Homebrew manages the LLVM
   dependencies of these packages. If using a versioned, keg-only LLD package
   instead, add its `bin` directory to `PATH`; for example, for `lld@22`:

   ```sh
   export PATH="$(brew --prefix lld@22)/bin:$PATH"
   ```

   Add that line to `~/.zshrc` to retain it in new interactive zsh sessions.
   Package references: [Odin](https://formulae.brew.sh/formula/odin) and
   [LLD](https://formulae.brew.sh/formula/lld).

4. **A current browser with WebAssembly and Canvas 2D support** — needed to run
   the frontend. No WebGPU, Node.js, npm, Python, or external UI libraries are
   required to build or run the application.

### Browser runtime boundary

Odin's supported `js_wasm32` browser target requires the bundled `odin.js`
runtime and a browser bootstrap. This infrastructure is accepted for this
project. All application layout, state, interaction, JSON parsing, financial
calculations, charting, and reload decisions are authored in Odin. See the
[official browser example](https://pkg.odin-lang.org/examples/wasm/js_wasm32/).

The small `frontend/web/bridge.js` adapter exposes canvas drawing, asynchronous
HTTP requests, pointer/keyboard events, viewport dimensions, and page reload.
It also loads WASM through the official `odin.js`, copied from the installed
Odin toolchain into `build/web/`. `index.html` hosts the canvas and scripts;
there are no HTML application controls or authored stylesheets.

<br/>

## Build and Run

Run these commands from the repository root. All project tooling is Odin;
there are no additional watcher packages to install.

- Build the native backend, WASM UI, and browser host assets into build/ using `odin run tools/dev -- build`

- Run financial calculation tests using `odin run tools/dev -- test`

- Watch both targets and run the backend on 127.0.0.1:8080 using `odin run tools/dev -- dev` \
  Or use `./run_dev.sh`


Open [the Web UI](http://127.0.0.1:8080/) after the first build completes.
If a runner is already open from an earlier version, stop it with Ctrl-C and
restart it once to load the updated development tooling.

The development runner polls source contents every 300 ms. Backend edits
trigger a build and process restart; frontend Odin, JavaScript bridge, or HTML
host edits rebuild the WASM UI and browser assets. One server-sent events (SSE)
connection notifies the browser after a successful build; Odin then refreshes
the page. The frontend does not poll health or version endpoints.
Shared-package edits rebuild both targets. A failed compilation retains the
last working backend or WASM artifact. Ctrl-C stops the runner and its backend.
Edits to the runner itself require restarting it.

For independent development processes, use separate terminals:

```sh
# Terminal 1: backend plus shared-package watching.
odin run tools/dev -- backend

# Terminal 2: WASM UI plus browser assets and shared-package watching.
odin run tools/dev -- frontend
```

Use either the combined runner or the independent runners; avoid concurrent
runners building the same target. The runner currently targets macOS/POSIX.
The backend serves the UI and API from the same origin in both modes; the
frontend watcher is an independent process and needs no second HTTP server.
An optional address selects a different listening port:

```sh
odin run tools/dev -- dev 127.0.0.1:8081
```

To run the compiled backend directly, optionally selecting a different address:

```sh
./build/backend
./build/backend 127.0.0.1:8081
```

<br/>

## Current API

- `GET /api/health`: status and build identifier.
- `GET /api/prices`: six deterministic **synthetic** closing prices and their
  simple daily returns.\
  The first observation has `has_return: false` because
  no preceding price exists.
- `GET /api/dev/events`: persistent SSE connection for backend availability and
  frontend rebuild notifications.\
  `/api/health` remains available for diagnostics.
- `GET /api/dev/version`: diagnostic/compatibility endpoint, allowing previously
  loaded polling clients to discover the SSE build. \
  The new UI does not poll it.

Backend build identifiers use `yy.mm.dd.counter`, for example `26.11.01.1`.
The date is UTC; the counter starts at 1 each day and increments after a
successful compilation. It is saved in `build/backend-build-id`, so restarting
the development runner preserves it. Deleting `build/` resets this local
history. Failed compilations do not advance the counter. Direct builds without
the development runner use the identifier `manual`.

Open [health](http://127.0.0.1:8080/api/health) or [prices](http://127.0.0.1:8080/api/prices)
while the backend is running. The server also serves the explicitly listed browser assets
with their proper MIME types, including `application/wasm`. It uses bounded concurrent 
HTTP/1.x workers: up to 32 connections, of which at most 16 may be SSE streams, leaving
capacity for API and asset requests. It remains a local-development server.

The SSE stream sends `backend-ready` on every connection, `frontend-changed`
with the current frontend version initially and whenever that version changes,
and heartbeat comments every 10 seconds. The browser's `EventSource` handles
reconnection with a one-second retry delay. Its minimal JavaScript adapter
forwards events to Odin; Odin decides whether to refetch data or reload.
Closed streams release their slots, and slow/broken writes terminate a stream.
Only local build-marker sampling remains on the server (every 300 ms per
stream); there is no browser health/version polling.

<br/>

## Web UI

The `frontend/` Odin package compiles to `build/frontend.wasm`. The UI fetches the native
price API and shows summary metrics, an interactive price/return chart, and an
observation ledger. Returns are recalculated in WASM with `shared/finance`,
matching the backend's calculation package. Data is explicitly synthetic.

Start reading the frontend at `main.odin`, which contains startup and the frame
loop. All frontend Odin files belong to the same package:

| File | Responsibility |
| --- | --- |
| `main.odin` | Startup, frame lifecycle, and build configuration |
| `state.odin` | Theme, dataset, request state, and interaction state |
| `browser.odin` | Browser host function declarations |
| `network.odin` | Price requests, JSON responses, SSE events, and timeouts |
| `input.odin` | Pointer and keyboard actions |
| `drawing.odin` | Canvas primitives, buttons, and refresh icon |
| `view.odin` | Responsive layout, header, metrics, ledger, and footer |
| `chart.odin` | Price/return chart and selected observation |

Use the Price/Returns buttons to switch charts, move over the chart to inspect
an observation, and use Refresh to reload data. With the canvas focused, left
and right arrow keys change the inspected observation; Tab cycles through
controls and Enter activates them. Errors preserve the last usable dataset and
offer Retry. The UI adapts to desktop and phone widths (360 px and above).

This canvas milestone supplies keyboard actions and a screen-reader summary;
it does not yet expose every chart point and table cell as semantic controls.

Backend reload currently means rebuild/restart, with in-memory state reset.
Frontend live reload refreshes the page and resets UI state. Backend restarts
are detected when SSE reconnects; the UI then refetches prices. Neither side
currently implements state-preserving code replacement. Browser host assets
are copied from local source/toolchain files; no CDN is needed.
