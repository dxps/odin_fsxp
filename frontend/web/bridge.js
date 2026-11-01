// Browser host only. Application state, layout, parsing, and input actions are Odin.
"use strict";
(async () => {
    const canvas = document.getElementById("app");
    const ctx = canvas.getContext("2d");
    const memory = new odin.WasmMemoryInterface();
    document.body.style.margin = "0";
    canvas.style.display = "block";
    // Odin draws focus indicators for its controls, not the canvas surface.
    canvas.style.outline = "none";
    const string = (ptr, len) => memory.loadString(ptr, len);
    let events;
    const forwardEvent = (kind, value = "") => {
        const bytes = new TextEncoder().encode(value);
        const exports = memory.exports;
        if (bytes.length > exports.response_capacity()) return;
        memory.loadBytes(exports.response_buffer(), bytes.length).set(bytes);
        exports.event_received(kind, bytes.length);
    };
    const host = {
        viewport_width: () => document.documentElement.clientWidth,
        viewport_height: () => document.documentElement.clientHeight,
        begin: (width, height) => {
            const ratio = window.devicePixelRatio || 1;
            const w = Math.round(width * ratio), h = Math.round(height * ratio);
            if (canvas.width !== w || canvas.height !== h) {
                canvas.width = w; canvas.height = h;
                canvas.style.width = `${width}px`; canvas.style.height = `${height}px`;
            }
            ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
        },
        rect: (x, y, w, h, ptr, len) => {
            ctx.fillStyle = string(ptr, len); ctx.fillRect(x, y, w, h);
        },
        text: (x, y, size, ptr, len, colorPtr, colorLen) => {
            ctx.font = `${size}px ui-sans-serif, system-ui, sans-serif`;
            ctx.fillStyle = string(colorPtr, colorLen); ctx.fillText(string(ptr, len), x, y);
        },
        line: (x1, y1, x2, y2, width, ptr, len) => {
            ctx.strokeStyle = string(ptr, len); ctx.lineWidth = width;
            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
        },
        circle: (x, y, radius, ptr, len) => {
            ctx.fillStyle = string(ptr, len); ctx.beginPath();
            ctx.arc(x, y, radius, 0, Math.PI * 2); ctx.fill();
        },
        label: (ptr, len) => canvas.setAttribute("aria-label", string(ptr, len)),
        reload: () => window.location.reload(),
        set_pointer_cursor: active => { canvas.style.cursor = active ? "pointer" : "default"; },
        connect_events: (ptr, len) => {
            events?.close();
            events = new EventSource(string(ptr, len));
            events.addEventListener("backend-ready", event => forwardEvent(1, event.data));
            events.addEventListener("frontend-changed", event => forwardEvent(2, event.data));
            events.onerror = () => forwardEvent(0);
        },
        fetch_text: (kind, ptr, len) => {
            const url = string(ptr, len);
            (async () => {
                let status = 0, bytes = new Uint8Array();
                try {
                    const response = await fetch(url, {cache: "no-store"});
                    status = response.status;
                    bytes = new Uint8Array(await response.arrayBuffer());
                } catch (_) { /* Odin handles network failure via status 0. */ }
                const exports = memory.exports;
                if (bytes.length > exports.response_capacity()) { status = 413; bytes = new Uint8Array(); }
                memory.loadBytes(exports.response_buffer(), bytes.length).set(bytes);
                exports.receive(kind, status, bytes.length);
            })();
        },
    };
    try {
        await odin.runWasm("/frontend.wasm", null, {browser: host}, memory);
        window.addEventListener("pagehide", () => events?.close());
        const pointer = event => {
            const bounds = canvas.getBoundingClientRect();
            return [event.clientX - bounds.left, event.clientY - bounds.top];
        };
        canvas.addEventListener("pointermove", event => memory.exports.pointer(...pointer(event), 0));
        canvas.addEventListener("pointerleave", () => memory.exports.pointer(-1, -1, 0));
        canvas.addEventListener("pointerdown", event => { canvas.focus(); memory.exports.pointer(...pointer(event), 1); });
        canvas.addEventListener("keydown", event => {
            const codes = {ArrowLeft: 1, ArrowRight: 2, Tab: 3, Enter: 4, " ": 4};
            if (codes[event.key] && memory.exports.key(codes[event.key], Number(event.shiftKey))) event.preventDefault();
        });
    } catch (error) {
        console.error(error);
        canvas.replaceWith(document.createTextNode(`Unable to start Odin/WASM: ${error.message}. Check the build and reload.`));
    }
})();
