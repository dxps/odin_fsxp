package main

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import finance "../shared/finance"

BUILD_ID :: #config(BUILD_ID, "manual")

Observation :: finance.Observation

MAX_CONNECTIONS :: 32
MAX_EVENT_STREAMS :: 16
stream_mutex: sync.Mutex
stream_count: int

serve_connection :: proc(t: ^thread.Thread) {
    // Default thread contexts own their temporary allocator and clean it up.
    handle(net.TCP_Socket(t.user_index))
}

main :: proc() {
    endpoint := "127.0.0.1:8080"
    if len(os.args) > 1 { endpoint = os.args[1] }
    ep, valid := net.parse_endpoint(endpoint)
    if !valid || ep.port < 1 {
        fmt.eprintln("Usage: backend [127.0.0.1:8080]")
        os.exit(1)
    }
    listener, err := net.listen_tcp(ep)
    if err != nil {
        fmt.eprintfln("Cannot listen on %s: %v", endpoint, err)
        os.exit(1)
    }
    defer net.close(listener)
    fmt.printfln("Backend http://%s | build %s", endpoint, BUILD_ID)
    workers: [MAX_CONNECTIONS]^thread.Thread
    for {
        client, _, accept_err := net.accept_tcp(listener)
        if accept_err != nil { continue }
        configure_client(client)
        available := -1
        for &worker, i in workers {
            if worker != nil && thread.is_done(worker) {
                thread.destroy(worker)
                worker = nil
            }
            if worker == nil && available < 0 { available = i }
        }
        if available >= 0 {
            worker := thread.create(serve_connection)
            if worker != nil {
                worker.user_index = int(client)
                workers[available] = worker
                thread.start(worker)
                continue
            }
        }
        respond(client, "503 Service Unavailable", "{\"error\":\"connection limit reached\"}")
        net.close(client)
        free_all(context.temp_allocator)
    }
}

configure_client :: proc(client: net.TCP_Socket) {
    when ODIN_OS == .Darwin {
        _ = net.set_option(client, .No_SIGPIPE_From_EPIPE, true)
    }
    _ = net.set_option(client, .Receive_Timeout, time.Second)
    _ = net.set_option(client, .Send_Timeout, time.Second)
}

// Each request has its own worker. Persistent SSE streams cannot monopolize
// the accept loop, and both ordinary requests and stream counts are bounded.
handle :: proc(client: net.TCP_Socket) {
    defer net.close(client)
    buffer: [8192]u8
    used := 0
    started := time.tick_now()
    for used < len(buffer) {
        n, err := net.recv_tcp(client, buffer[used:])
        if err != nil || n == 0 { return }
        used += n
        if strings.contains(string(buffer[:used]), "\r\n\r\n") { break }
        if time.tick_since(started) >= 2*time.Second { return }
    }
    request := string(buffer[:used])
    if !strings.contains(request, "\r\n\r\n") {
        respond(client, "431 Request Header Fields Too Large", "{\"error\":\"headers too large\"}")
        return
    }
    line := request[:strings.index(request, "\r\n")]
    fields := strings.fields(line, context.temp_allocator)
    if len(fields) != 3 || (fields[2] != "HTTP/1.1" && fields[2] != "HTTP/1.0") {
        respond(client, "400 Bad Request", "{\"error\":\"invalid request line\"}")
        return
    }
    if fields[0] != "GET" {
        respond(client, "405 Method Not Allowed", "{\"error\":\"GET required\"}")
        return
    }
    path := fields[1]
    if query := strings.index(path, "?"); query >= 0 { path = path[:query] }
    switch path {
    case "/", "/index.html": serve_asset(client, "build/web/index.html", "text/html; charset=utf-8")
    case "/bridge.js": serve_asset(client, "build/web/bridge.js", "text/javascript; charset=utf-8")
    case "/odin.js": serve_asset(client, "build/web/odin.js", "text/javascript; charset=utf-8")
    case "/frontend.wasm": serve_asset(client, "build/frontend.wasm", "application/wasm")
    case "/favicon.ico": respond(client, "204 No Content", "")
    case "/api/dev/events": serve_events(client)
    case "/api/dev/version":
        // Diagnostic/compatibility endpoint: already-loaded polling clients
        // can discover the SSE build and migrate without a manual refresh.
        bytes, err := os.read_entire_file("build/frontend-build-id", context.temp_allocator)
        if err != nil { respond(client, "503 Service Unavailable", "{\"error\":\"frontend not built\"}"); return }
        data, marshal_err := json.marshal(struct {frontend: string}{strings.trim_space(string(bytes))}, allocator=context.temp_allocator)
        if marshal_err == nil { respond(client, "200 OK", string(data)) }
    case "/api/health":
        data, err := json.marshal(struct {status, build: string}{"ok", BUILD_ID}, allocator=context.temp_allocator)
        if err == nil { respond(client, "200 OK", string(data)) }
    case "/api/prices":
        observations: [len(finance.FIXTURE)]Observation
        prices := finance.FIXTURE
        for price, i in prices {
            observations[i].date = price.date
            observations[i].close = price.close
            if i > 0 {
                observations[i].daily_return, observations[i].has_return =
                    finance.simple_return(prices[i-1].close, price.close)
            }
        }
        result := finance.Price_Response{"DEMO", "synthetic fixture", observations[:]}
        data, err := json.marshal(result, allocator=context.temp_allocator)
        if err == nil { respond(client, "200 OK", string(data)) }
    case:
        respond(client, "404 Not Found", "{\"error\":\"not found\"}")
    }
}

send_event :: proc(client: net.TCP_Socket, name: string, value: any) -> bool {
    data, err := json.marshal(value, allocator=context.temp_allocator)
    if err != nil { return false }
    message := fmt.tprintf("event: %s\ndata: %s\n\n", name, string(data))
    return send_all(client, transmute([]u8)message)
}

serve_events :: proc(client: net.TCP_Socket) {
    sync.mutex_lock(&stream_mutex)
    if stream_count >= MAX_EVENT_STREAMS {
        sync.mutex_unlock(&stream_mutex)
        respond(client, "503 Service Unavailable", "{\"error\":\"event stream limit reached\"}")
        return
    }
    stream_count += 1
    sync.mutex_unlock(&stream_mutex)
    defer {
        sync.mutex_lock(&stream_mutex)
        stream_count -= 1
        sync.mutex_unlock(&stream_mutex)
    }
    // Close-delimited response: it stays open until the stream disconnects.
    header: string = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\nX-Accel-Buffering: no\r\n\r\nretry: 1000\n\n"
    if !send_all(client, transmute([]u8)header) { return }
    if !send_event(client, "backend-ready", struct {build: string}{BUILD_ID}) { return }
    if net.set_blocking(client, false) != nil { return }
    previous: [128]u8
    previous_length := 0
    heartbeat := time.tick_now()
    for {
        // Detect a closed tab promptly instead of waiting for a heartbeat's
        // next write. No request bytes are expected after the SSE handshake.
        probe: [1]u8
        _, read_err := net.recv_tcp(client, probe[:])
        if read_err != .Would_Block { return }
        // Only local build-marker sampling remains; browsers make no polling
        // requests. The runner atomically publishes this marker after success.
        bytes, err := os.read_entire_file("build/frontend-build-id", context.temp_allocator)
        if err == nil {
            version := strings.trim_space(string(bytes))
            if len(version) > 0 && len(version) <= len(previous) && version != string(previous[:previous_length]) {
                if !send_event(client, "frontend-changed", struct {frontend: string}{version}) { return }
                previous_length = copy(previous[:], version)
            }
        }
        if time.tick_since(heartbeat) >= 10*time.Second {
            if !send_all(client, transmute([]u8)string(": heartbeat\n\n")) { return }
            heartbeat = time.tick_now()
        }
        free_all(context.temp_allocator)
        time.sleep(300*time.Millisecond)
    }
}

serve_asset :: proc(client: net.TCP_Socket, file, content_type: string) {
    bytes, err := os.read_entire_file(file, context.temp_allocator)
    if err != nil {
        respond(client, "503 Service Unavailable", "{\"error\":\"Run odin run tools/dev -- build first\"}")
        return
    }
    respond(client, "200 OK", string(bytes), content_type)
}

respond :: proc(client: net.TCP_Socket, status, body: string, content_type := "application/json") {
    extra := "Allow: GET\r\n" if status == "405 Method Not Allowed" else ""
    header := fmt.tprintf("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n%s\r\n", status, content_type, len(body), extra)
    if !send_all(client, transmute([]u8)header) { return }
    _ = send_all(client, transmute([]u8)body)
}

send_all :: proc(client: net.TCP_Socket, bytes: []u8) -> bool {
    sent := 0
    for sent < len(bytes) {
        n, err := net.send_tcp(client, bytes[sent:])
        if err != nil || n == 0 { return false }
        sent += n
    }
    return true
}
