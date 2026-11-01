package main

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"
import finance "../shared/finance"

BUILD_ID :: #config(BUILD_ID, "manual")

Observation :: finance.Observation

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
    for {
        client, _, accept_err := net.accept_tcp(listener)
        if accept_err != nil { continue }
        handle(client)
        free_all(context.temp_allocator)
    }
}

// Deliberately small, sequential HTTP/1.x GET server for the local milestone.
// Bound requests and deadlines prevent a stalled client blocking indefinitely.
handle :: proc(client: net.TCP_Socket) {
    defer net.close(client)
    when ODIN_OS == .Darwin {
        _ = net.set_option(client, .No_SIGPIPE_From_EPIPE, true)
    }
    _ = net.set_option(client, .Receive_Timeout, time.Second)
    _ = net.set_option(client, .Send_Timeout, time.Second)
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
    case "/api/dev/version":
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
