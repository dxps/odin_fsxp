package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:time"

stopping: bool

on_signal :: proc "c" (_: posix.Signal) {
    sync.atomic_store(&stopping, true)
}

run :: proc(command: []string) -> bool {
    child, err := os.process_start({command=command, stdout=os.stdout, stderr=os.stderr})
    if err != nil {
        fmt.eprintfln("Cannot start %s: %v", command[0], err)
        return false
    }
    state, wait_err := os.process_wait(child)
    return wait_err == nil && state.success && state.exit_code == 0
}

stop :: proc(child: ^os.Process) {
    if child.pid == 0 { return }
    _ = os.process_terminate(child^)
    _, err := os.process_wait(child^, time.Second)
    if err != nil {
        _ = os.process_kill(child^)
        _, _ = os.process_wait(child^)
    }
    child^ = {}
}

// Content fingerprints catch edits, additions, deletions, and atomic saves.
// Scratch allocations are reset by the caller after each scan/build iteration.
fingerprint :: proc(root: string) -> u64 {
    hash: u64 = 14695981039346656037
    walker := os.walker_create(root)
    defer os.walker_destroy(&walker)
    for info in os.walker_walk(&walker) {
        if info.type != .Regular { continue }
        if !strings.has_suffix(info.name, ".odin") && !strings.has_suffix(info.name, ".js") && !strings.has_suffix(info.name, ".html") { continue }
        bytes, err := os.read_entire_file(info.fullpath, context.temp_allocator)
        if err != nil {
            fmt.eprintfln("Cannot watch %s: %v", info.fullpath, err)
            continue
        }
        file_hash: u64 = 14695981039346656037
        for b in info.fullpath { file_hash = (file_hash ~ u64(b)) * 1099511628211 }
        for b in bytes { file_hash = (file_hash ~ u64(b)) * 1099511628211 }
        // Addition is independent of the directory enumeration order.
        hash += file_hash
    }
    if path, err := os.walker_error(&walker); err != nil {
        fmt.eprintfln("Cannot watch %s: %v", path, err)
    }
    return hash
}

build_backend :: proc() -> bool {
    build_id, ok := next_build_id()
    if !ok { return false }
    define := fmt.tprintf("-define:BUILD_ID=%s", build_id)
    if !run([]string{"odin", "build", "backend", "-out:build/backend.next", define}) { return false }
    // Persist before publishing so an exposed identifier cannot be reused.
    if err := os.write_entire_file("build/backend-build-id.next", build_id); err != nil {
        fmt.eprintfln("Cannot save build identifier: %v", err)
        return false
    }
    if err := os.rename("build/backend-build-id.next", "build/backend-build-id"); err != nil {
        fmt.eprintfln("Cannot publish build identifier: %v", err)
        return false
    }
    if err := os.rename("build/backend.next", "build/backend"); err != nil {
        fmt.eprintfln("Cannot publish backend: %v", err)
        return false
    }
    return true
}

next_build_id :: proc() -> (string, bool) {
    year, month, day := time.date(time.now()) // core:time dates are UTC.
    date := fmt.tprintf("%02d.%02d.%02d", year % 100, int(month), day)
    counter: uint = 1
    if os.exists("build/backend-build-id") {
        bytes, err := os.read_entire_file("build/backend-build-id", context.temp_allocator)
        if err != nil {
            fmt.eprintfln("Cannot read build identifier: %v", err)
            return "", false
        }
        previous := strings.trim_space(string(bytes))
        separator := strings.last_index(previous, ".")
        if separator != 8 {
            fmt.eprintln("Invalid build/backend-build-id; expected yy.mm.dd.counter.")
            return "", false
        }
        previous_counter, valid := strconv.parse_uint(previous[separator+1:], 10)
        if !valid || previous_counter == 0 || previous_counter == max(uint) {
            fmt.eprintln("Invalid or exhausted build counter in build/backend-build-id.")
            return "", false
        }
        if previous[:separator] == date { counter = previous_counter + 1 }
    }
    return fmt.tprintf("%s.%d", date, counter), true
}

copy_file :: proc(source, target: string) -> bool {
    bytes, read_err := os.read_entire_file(source, context.temp_allocator)
    if read_err != nil { fmt.eprintfln("Cannot read %s: %v", source, read_err); return false }
    staged := fmt.tprintf("%s.next", target)
    if err := os.write_entire_file(staged, bytes); err != nil {
        fmt.eprintfln("Cannot stage %s: %v", target, err); return false
    }
    if err := os.rename(staged, target); err != nil {
        fmt.eprintfln("Cannot publish %s: %v", target, err); return false
    }
    return true
}

build_frontend :: proc(development := true) -> bool {
    build_id := fmt.tprintf("web-%d", time.time_to_unix_nano(time.now()))
    define := fmt.tprintf("-define:FRONTEND_BUILD=%s", build_id)
    dev_define := "-define:DEV_MODE=true" if development else "-define:DEV_MODE=false"
    if !run([]string{"odin", "build", "frontend", "-target:js_wasm32", "-out:build/frontend.next.wasm", define, dev_define}) { return false }
    if !os.exists("build/web") {
        if err := os.make_directory_all("build/web"); err != nil { fmt.eprintfln("Cannot create web assets directory: %v", err); return false }
    }
    state, root_bytes, stderr, err := os.process_exec({command=[]string{"odin", "root"}}, context.temp_allocator)
    if err != nil || !state.success { fmt.eprintln("Cannot locate Odin browser runtime:", string(stderr)); return false }
    root := strings.trim_space(string(root_bytes))
    if !copy_file(fmt.tprintf("%s/core/sys/wasm/js/odin.js", root), "build/web/odin.js") { return false }
    if !copy_file("frontend/web/index.html", "build/web/index.html") { return false }
    if !copy_file("frontend/web/bridge.js", "build/web/bridge.js") { return false }
    if err := os.rename("build/frontend.next.wasm", "build/frontend.wasm"); err != nil {
        fmt.eprintfln("Cannot publish WASM: %v", err)
        return false
    }
    if write_err := os.write_entire_file("build/frontend-build-id.next", build_id); write_err != nil {
        fmt.eprintfln("Cannot save frontend version: %v", write_err); return false
    }
    if rename_err := os.rename("build/frontend-build-id.next", "build/frontend-build-id"); rename_err != nil {
        fmt.eprintfln("Cannot publish frontend version: %v", rename_err); return false
    }
    fmt.printfln("Odin/WASM UI rebuilt.%s", " Browser live reload enabled." if development else "")
    return true
}

main :: proc() {
    if !os.exists("shared/finance/finance.odin") {
        fmt.eprintln("Run this tool from the repository root.")
        os.exit(1)
    }
    mode := "dev"
    if len(os.args) > 1 { mode = os.args[1] }
    address := "127.0.0.1:8080"
    if len(os.args) > 2 { address = os.args[2] }
    if mode == "test" {
        if !run([]string{"odin", "test", "tests/finance"}) { os.exit(1) }
        return
    }
    if mode != "build" && mode != "dev" && mode != "backend" && mode != "frontend" {
        fmt.eprintln("Usage: odin run tools/dev -- [build|test|dev|backend|frontend] [127.0.0.1:8080]")
        os.exit(1)
    }
    if !os.exists("build") {
        if err := os.make_directory_all("build"); err != nil {
            fmt.eprintfln("Cannot create build directory: %v", err)
            os.exit(1)
        }
    }
    if mode == "build" {
        backend_ok := build_backend()
        frontend_ok := build_frontend()
        if !backend_ok || !frontend_ok { os.exit(1) }
        return
    }
    posix.signal(.SIGINT, on_signal)
    posix.signal(.SIGTERM, on_signal)
    child: os.Process
    defer stop(&child)
    backend_enabled := mode != "frontend"
    frontend_enabled := mode != "backend"
    last_backend, last_frontend: u64
    first := true
    fmt.println("Watching Odin sources; Ctrl-C stops the runner and backend.")
    for !sync.atomic_load(&stopping) {
        shared := fingerprint("shared")
        backend := fingerprint("backend") + shared
        frontend := fingerprint("frontend") + shared
        if backend_enabled && (first || backend != last_backend) {
            if build_backend() && !sync.atomic_load(&stopping) {
                stop(&child)
                err: os.Error
                child, err = os.process_start({command=[]string{"build/backend", address}, stdout=os.stdout, stderr=os.stderr})
                if err != nil { fmt.eprintfln("Cannot start backend: %v", err) }
            } else {
                fmt.eprintln("Backend build failed or interrupted; retaining last running build.")
            }
            last_backend = backend
        }
        if frontend_enabled && (first || frontend != last_frontend) && !sync.atomic_load(&stopping) {
            if !build_frontend(true) { fmt.eprintln("WASM build failed; retaining last successful artifact.") }
            last_frontend = frontend
        }
        if child.pid != 0 {
            state, err := os.process_wait(child, 0)
            if err == nil && state.exited {
                fmt.eprintfln("Backend exited (%d); fix the issue and edit a watched source to restart.", state.exit_code)
                child = {}
            }
        }
        first = false
        free_all(context.temp_allocator)
        time.sleep(300*time.Millisecond)
    }
}
