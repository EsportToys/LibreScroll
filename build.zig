decay: i32 = 3,
sensY: i32 = 18,
sensX: i32 = 0,
stepY: i32 = 1,
stepX: i32 = 1,
flick: i32 = 0,
think: i32 = 0,

var global_config: @This() = .{};
var process_mutex: *anyopaque = undefined;
var main_thread_id: u32 = undefined;
var raw_thread_id: u32 = undefined;
var raw_thread_handle: ?*anyopaque = null;
var raw_thread_pending_restart = false;

const Vec2f = @Vector(2, f32);
const Vec2i = @Vector(2, i32);

const LIBRE_SCROLL_VERSION_TEXT = "v2.2.1";
const MAGIC_WORD: [8]u8 = "PASS\x00\x00\x00\x00".*;
const WM_TRAY = 0x8001;
const WM_RAW_STOPPED = 0x8002;
const WM_RAW_STARTED = 0x8003;
const WM_HOOK_STOPPED = 0x8004;
const WM_HOOK_STARTED = 0x8005;
const TRAY_UID = 0x69;

pub fn main() void {
    process_mutex = CreateMutexA(null, 1, "LibreScroll") orelse return;
    if (0 != GetLastError()) return;
    main_thread_id = GetCurrentThreadId();

    if (.NULL == SetThreadDpiAwarenessContext(.UNAWARE_GDISCALED)) return;

    const hwndTray = CreateDialogParamA(null, "CFGDLG", null, trayProc, 0) orelse return;

    const hSensY = GetDlgItem(hwndTray, 0x4002) orelse return;
    const hSensX = GetDlgItem(hwndTray, 0x4003) orelse return;
    _ = SetWindowLongPtrA(hSensY, -21, SetWindowLongPtrA(hSensY, -4, @bitCast(@intFromPtr(&inputProc))));
    _ = SetWindowLongPtrA(hSensX, -21, SetWindowLongPtrA(hSensX, -4, @bitCast(@intFromPtr(&inputProc))));

    const ico = ico: {
        const cpl = LoadLibraryA("main.cpl") orelse break :ico null;
        defer _ = FreeLibrary(cpl);
        break :ico LoadIconA(cpl, @ptrFromInt(608));
    };

    _ = SendMessageA(hwndTray, 0x0080, 0, @bitCast(@intFromPtr(ico))); // set small icon
    _ = SendMessageA(hwndTray, 0x0080, 1, @bitCast(@intFromPtr(ico))); // set big icon

    var tray_data: NOTIFYICONDATAA = .{
        .hWnd = hwndTray,
        .uID = TRAY_UID,
        .uFlags = 0x8F,
        .uCallbackMessage = WM_TRAY,
        .hIcon = ico,
        .uTimeout = 4,
        .szTip = @splat(0),
        .dwState = 0,
        .dwStateMask = 1,
    };
    tray_data.szTip[0..11].* = "LibreScroll".*;

    if (0 == Shell_NotifyIconA(.ADD, &tray_data)) return;
    defer _ = Shell_NotifyIconA(.DELETE, &tray_data);
    if (0 == Shell_NotifyIconA(.SETVERSION, &tray_data)) return;

    if (!startThread()) return;

    var msg: MSG = undefined;
    while (GetMessageA(&msg, null, 0, 0) > 0) {
        if (null == msg.hWnd) {
            if (WM_RAW_STOPPED == msg.message) {
                tray_data.szTip[11..23].* = " - Inactive\x00".*;
                _ = Shell_NotifyIconA(.MODIFY, &tray_data);
                if (GetDlgItem(hwndTray, 104)) |hPause| {
                    _ = SetWindowTextA(hPause, "Unpause");
                    _ = SetWindowLongA(hPause, -12, 105);
                }
                _ = CloseHandle(raw_thread_handle.?);
                raw_thread_handle = null;
                if (raw_thread_pending_restart) {
                    raw_thread_pending_restart = false;
                    _ = startThread(); // non-critical failure
                }
            } else if (WM_RAW_STARTED == msg.message) {
                tray_data.szTip[11..21].* = " - Active\x00".*;
                _ = Shell_NotifyIconA(.MODIFY, &tray_data);
                if (GetDlgItem(hwndTray, 105)) |hUnpause| {
                    _ = SetWindowTextA(hUnpause, "Pause");
                    _ = SetWindowLongA(hUnpause, -12, 104);
                }
            }
        } else if (0 == IsDialogMessageA(hwndTray, &msg)) {
            _ = TranslateMessage(&msg);
            _ = DispatchMessageA(&msg);
        }
    }
}

fn trayProc(hwnd: HWND, uMsg: u32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    switch (uMsg) {
        else => return 0,
        0x0010 => _ = ShowWindowAsync(hwnd, 0), // hide to tray instead of quitting
        0x0111 => onWmCommand(hwnd, wParam, lParam),
        WM_TRAY => onWmTray(hwnd, wParam, lParam),
    }
    return 1;
}

// from https://devblogs.microsoft.com/oldnewthing/20190222-00/?p=101064
fn inputProc(hwnd: HWND, uMsg: u32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    if (uMsg == 0x0102 and wParam >= ' ') {
        switch(wParam) {
            else => if (wParam != '-' or 0 != SendMessageA(hwnd, 0x00B0, 0, 0)) return 0,
            '0'...'9' => {},
        }
    }
    const proc: WNDPROC = @ptrFromInt(@as(usize, @bitCast(GetWindowLongPtrA(hwnd, -21))));
    return CallWindowProcA(proc, hwnd, uMsg, wParam, lParam);
}

fn onWmCommand(hwnd: HWND, wParam: usize, lParam: isize) void {
    const hCtrl: ?HWND = @ptrFromInt(@as(usize, @bitCast(lParam)));
    const id = wParam & 0xFFFF;
    const uMsg = wParam >> 16;
    const is_accel = (null == hCtrl) and (1 == uMsg); _ = is_accel;
    switch (id) {
        else => {},
        100 => quit(),
        101 => show(hwnd),
        102 => info(hwnd),
        103 => elevate(),
        104 => if (raw_thread_handle) |_| {
            raw_thread_pending_restart = false;
            _ = PostThreadMessageA(raw_thread_id, 0x0012, 0, 0);
        },
        105, 106 => {
            if (106 == id) save(hwnd);
            if (raw_thread_handle) |_| {
                raw_thread_pending_restart = true;
                _ = PostThreadMessageA(raw_thread_id, 0x0012, 0, 0);
            } else {
                raw_thread_pending_restart = false;
                if (!startThread()) quit();
            }
        },
    }
}

fn onWmTray(hwnd: HWND, wParam: usize, lParam: isize) void {
    const src: packed struct(usize) {
        msg: u16,
        uid: u16,
        _: if (8 == @sizeOf(usize)) u32 else u0,
    } = @bitCast(lParam);
    const pos: packed struct(usize) {
        x: i16,
        y: i16,
        _: if (8 == @sizeOf(usize)) u32 else u0,
    } = @bitCast(wParam);
    switch (src.msg) {
        else => {},
        0x007B => menu(hwnd, src.uid, pos.x, pos.y), // WM_CONTEXTMENU
        0x0400 => show(hwnd), // WM_USER
    }
}

fn elevate() void {
    var buf: [32767:0]u8 = undefined;
    const len = GetModuleFileNameA(null, &buf, buf.len); // copied `len` characters plus zero sentinel at index `len`
    if (len == 0) return;
    if (len == buf.len and 0 != GetLastError()) return;
    _ = CloseHandle(process_mutex);
    _ = ShellExecuteA(null, "runas", &buf, null, null, 0);
    quit();
}

fn quit() void {
    _ = PostQuitMessage(0);
}

fn info(hwnd: HWND) void {
    _ = MessageBoxA(hwnd, "Visit https://github.com/EsportToys/LibreScroll for more info.", "About LibreScroll " ++ LIBRE_SCROLL_VERSION_TEXT, 0);
}

fn menu(hwnd: HWND, uid: u16, x: i16, y: i16) void {
    const tray_hmenu = LoadMenuA(null, "menu") orelse return;
    defer _ = DestroyMenu(tray_hmenu);
    const hMenu = GetSubMenu(tray_hmenu, IsUserAnAdmin() | @as(i32, if (raw_thread_handle) |_| 2 else 0)) orelse return;
    var rect: [4]i32 = undefined;
    _ = Shell_NotifyIconGetRect(&.{ .hWnd = hwnd, .uID = uid }, &rect);
    _ = SetForegroundWindow(hwnd);
    _ = SetThreadDpiAwarenessContext(.PER_MONITOR_AWARE_V2);
    _ = TrackPopupMenu(hMenu, 0, x, y, 0, hwnd, null);
    _ = SetThreadDpiAwarenessContext(.NULL);
}

fn show(hwnd: HWND) void {
    _ = SetDlgItemInt(  hwnd, 0x4001, @bitCast(global_config.decay), 0 );
    _ = SetDlgItemInt(  hwnd, 0x4002, @bitCast(global_config.sensY), 1 );
    _ = SetDlgItemInt(  hwnd, 0x4003, @bitCast(global_config.sensX), 1 );
    _ = SetDlgItemInt(  hwnd, 0x4004, @bitCast(global_config.stepY), 0 );
    _ = SetDlgItemInt(  hwnd, 0x4005, @bitCast(global_config.stepX), 0 );
    _ = CheckDlgButton( hwnd, 0x4006, @bitCast(global_config.flick)    );
    _ = CheckDlgButton( hwnd, 0x4007, @bitCast(global_config.think)    );
    if (0 == IsWindowVisible(hwnd)) _ = ShowWindowAsync(hwnd, 5);
    _ = SetForegroundWindow(hwnd);
}

fn save(hwnd: HWND) void {
    const ini = "./options.ini";
    const sec = "LibreScroll";
    var buf: [32767:0]u8 = undefined;
    inline for (.{ "decay", "sensY", "sensX", "stepY", "stepX" }, 0x4001..) |key, i| {
        _ = GetDlgItemTextA(hwnd, i, &buf, buf.len);
        _ = WritePrivateProfileStringA(sec, key, &buf, ini);
    }
    _ = WritePrivateProfileStringA(sec, "flick", if (0 == IsDlgButtonChecked(hwnd, 0x4006)) "0" else "1", ini);
    _ = WritePrivateProfileStringA(sec, "think", if (0 == IsDlgButtonChecked(hwnd, 0x4007)) "0" else "1", ini);
}

fn startThread() bool {
    const ini = "./options.ini";
    const sec = "LibreScroll";
    global_config.decay = @max( 0 ,           GetPrivateProfileIntA(sec, "decay", global_config.decay, ini)   );
    global_config.sensY =                     GetPrivateProfileIntA(sec, "sensY", global_config.sensY, ini)    ;
    global_config.sensX =                     GetPrivateProfileIntA(sec, "sensX", global_config.sensX, ini)    ;
    global_config.stepY = @max( 0 ,           GetPrivateProfileIntA(sec, "stepY", global_config.stepY, ini)   );
    global_config.stepX = @max( 0 ,           GetPrivateProfileIntA(sec, "stepX", global_config.stepX, ini)   );
    global_config.flick = @max( 0 , @min( 1 , GetPrivateProfileIntA(sec, "flick", global_config.flick, ini) ) );
    global_config.think = @max( 0 , @min( 1 , GetPrivateProfileIntA(sec, "think", global_config.think, ini) ) );
    raw_thread_handle = CreateThread(
        null,
        0,
        &rawMain,
        null,
        0,
        &raw_thread_id,
    ) orelse return false;
    return true;
}

fn hookProc(code: i32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    if (code >= 0 and (wParam == 0x207 or wParam == 0x208)) {
        const inf: *const MSLLHOOKSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
        const pass: usize = @bitCast(MAGIC_WORD);
        if (0 == 3 & inf.flags or pass != inf.dwExtraInfo) return 1;
    }
    return CallNextHookEx(null, code, wParam, lParam);
}

fn hookMain(_: ?*anyopaque) callconv(.winapi) u32 {
    defer _ = PostThreadMessageA(raw_thread_id, 0x0012, 0, 0);
    const hhook = SetWindowsHookExA(14, hookProc, null, 0) orelse return 0;
    defer _ = UnhookWindowsHookEx(hhook);
    _ = PostThreadMessageA(raw_thread_id, WM_HOOK_STARTED, 0, 0);
    var msg: MSG = undefined;
    while (GetMessageA(&msg, null, 0, 0) > 0) {
        _ = DispatchMessageA(&msg);
    }
    return 0;
}

fn rawMain(_: ?*anyopaque) callconv(.winapi) u32 {
    defer _ = PostThreadMessageA(main_thread_id, WM_RAW_STOPPED, 0, 0);
    if (.NULL == SetThreadDpiAwarenessContext(.PER_MONITOR_AWARE_V2)) return 0;
    const HWND_MESSAGE: HWND = @ptrFromInt(~@as(usize, 2));
    const hwnd = CreateWindowExA(0, "Message", null, 0, 0, 0, 0, 0, HWND_MESSAGE, null, null, null) orelse return 0;
    defer _ = DestroyWindow(hwnd);

    if (0 == RegisterRawInputDevices(&.{.{
        .usUsagePage = 0x01, // generic desktop
        .usUsage = 0x02, // mouse
        .dwFlags = 0x100, // inputsink
        .hwndTarget = hwnd,
    }}, 1, @sizeOf(RAWINPUTDEVICE))) return 0;

    defer _ = RegisterRawInputDevices(&.{.{
        .usUsagePage = 0x01, // generic desktop
        .usUsage = 0x02, // mouse
        .dwFlags = 0x1, // inputsink
        .hwndTarget = null,
    }}, 1, @sizeOf(RAWINPUTDEVICE));

    var hook_active = false;
    var hook_thread_id: u32 = undefined;
    const hook_thread_handle = CreateThread(
        null,
        0,
        &hookMain,
        null,
        0,
        &hook_thread_id,
    ) orelse return 0;
    _ = SetThreadPriority(hook_thread_handle, 15); // THREAD_PRIORITY_TIME_CRITICAL
    defer _ = CloseHandle(hook_thread_handle);
    defer _ = PostThreadMessageA(hook_thread_id, 0x0012, 0, 0);

    _ = PostThreadMessageA(main_thread_id, WM_RAW_STARTED, 0, 0);

    var qpf: u64 = undefined;
    var now: u64 = undefined;
    var past: u64 = undefined;
    _ = QueryPerformanceFrequency(@ptrCast(&qpf));
    _ = QueryPerformanceCounter(@ptrCast(&past));

    const USER_TIMER_MINIMUM = 10;
    const fpscap_interval_ms = 4;
    const targeted_militicks = qpf * @min(fpscap_interval_ms, USER_TIMER_MINIMUM);

    var size: u32 = @sizeOf(RAWINPUT.MOUSE);
    var data: RAWINPUT.MOUSE = undefined;
    var state: State = .{};
    var timer: usize = 0;
    var scroll_acu: Vec2i = @splat(0);
    var unclip_pending = false;
    var msg: MSG = undefined;
    while (GetMessageA(&msg, null, 0, 0) > 0) {
        defer _ = DispatchMessageA(&msg);
        if (!hook_active) {
            if (WM_HOOK_STARTED == msg.message) hook_active = true;
            continue;
        }
        if (0xff == msg.message
            and GetRawInputData(msg.lParam, 0x10000003, &data, &size, @sizeOf(RAWINPUT.HEADER)) > 0) _: {
            const flags = data.data.usButtonFlags;
            if (null == data.header.hDevice) {
                if (unclip_pending and 32 == 32 & flags) {
                    unclip_pending = false;
                    _ = ClipCursor(null);
                }
                break :_;
            }
            if (flags == 0) { // movement only
                scroll_acu += .{ data.data.lLastX, data.data.lLastY };
            } else if (32 == 32 & flags) {
                if (global_config.flick == 0) {
                    if (0 != KillTimer(null, timer)) timer = 0;
                }
                if (state.scroll_pending) {
                    unclip_pending = true;
                    _ = INPUT.send(&.{
                        .mi(.{ .dwFlags = 0x20, .dwExtraInfo = @bitCast(MAGIC_WORD) }),
                        .mi(.{ .dwFlags = 0x40, .dwExtraInfo = @bitCast(MAGIC_WORD) }),
                    });
                } else {
                    _ = ClipCursor(null);
                }
                state.scroll_pending = false;
                state.is_scrolling = false;
            } else if (16 == 16 & flags) {
                if (timer == 0) {
                    timer = SetTimer(null, 0, USER_TIMER_MINIMUM, null);
                    if (timer == 0) break;
                }
                scroll_acu = @splat(0);
                state.vel = @splat(0);
                state.is_scrolling = true;
                state.scroll_pending = true;
                _ = GetCursorPos(state.rect[0..2]);
                state.rect[2] = state.rect[0] + 1;
                state.rect[3] = state.rect[1] + 1;
                _ = ClipCursor(&state.rect);
            } else if (global_config.flick != 0 and !state.is_scrolling) {
                state.vel = @splat(0); // in flick mode, any mouse action besides the above should immediately halt
                if (0 != KillTimer(null, timer)) timer = 0;
            }
        }
        _ = QueryPerformanceCounter(@ptrCast(&now));
        const dt = now - past;
        if (dt * 1000 > targeted_militicks) {
            if (state.step(scroll_acu, dt, qpf)) |send| state.flush(send);
            scroll_acu = @splat(0);
            past = now;
        }
    }
    return 0;
}

const State = struct {
    vel: Vec2f = @splat(0),
    res: Vec2f = @splat(0),
    rect: [4]i32 = @splat(0),
    is_scrolling: bool = false,
    scroll_pending: bool = false,

    fn step(state: *State, acu: Vec2i, tick: u64, freq: u64) ?[2]f32 {
        if (state.is_scrolling) {
            var current_rect: [4]i32 = undefined;
            _ = GetClipCursor(&current_rect);
            if (current_rect[0] != state.rect[0] or
                current_rect[1] != state.rect[1] or
                current_rect[2] != state.rect[2] or
                current_rect[3] != state.rect[3]) _ = ClipCursor(&state.rect);
            var delta: Vec2f = .{
                @floatFromInt(global_config.sensX), 
                @floatFromInt(global_config.sensY),
            };
            delta *= @floatFromInt(acu);
            state.vel += delta;
        } else if (global_config.flick == 0) {
            return null;
        }
        var dt: f32 = @floatFromInt(tick);
        dt /= @floatFromInt(freq);
        const mu: f32 = @floatFromInt(global_config.decay);
        const f0 = @exp(-dt * mu);
        const f1 = (1 - f0) / mu;
        var send = state.vel;
        send *= @splat(f1);
        state.vel *= @splat(f0);
        if (@reduce(.Add, state.vel * state.vel) < 1) {
            state.vel /= @splat(mu);
            send += state.vel;
            state.vel = @splat(0);
        }
        return send;
    }

    fn flush(state: *State, delta: Vec2f) void {
        state.res += delta;
        const thresh: Vec2f = .{ @floatFromInt(global_config.stepX), @floatFromInt(global_config.stepY) };
        const batch = thresh * @trunc(state.res / thresh);
        var send: Vec2i = @intFromFloat(batch);
        state.res -= batch;
        if (global_config.think != 0) {
            if (@abs(send[0]) > @abs(send[1])) {
                send[1] = 0;
                state.res[1] = 0;
            } else {
                send[0] = 0;
                state.res[0] = 0;
            }
        }
        if (0 == send[0] and 0 == send[1]) return;
        const buf: [2]INPUT = .{
            .mi(.{ .mouseData = -send[1], .dwFlags = 0x0800 }),
            .mi(.{ .mouseData =  send[0], .dwFlags = 0x1000 }),
        };
        state.scroll_pending = false;
        if (send[1] != 0) {
            _ = INPUT.send(buf[0..if (send[0] != 0) 2 else 1]);
        } else if (send[0] != 0) {
            _ = INPUT.send(buf[1..]);
        }
    }
};

const HMODULE = *const opaque{};
const HWND = *const opaque{};
const HMENU = *const opaque{};
const HICON = *const opaque{};
const HHOOK = *const opaque{};

extern "kernel32" fn CreateMutexA(?*const SECURITY_ATTRIBUTES, i32, [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetModuleFileNameA(?HMODULE, [*]u8, u32) callconv(.winapi) u32;
extern "kernel32" fn LoadLibraryA([*:0]const u8) callconv(.winapi) ?HMODULE;
extern "kernel32" fn FreeLibrary(HMODULE) callconv(.winapi) i32;
extern "kernel32" fn GetPrivateProfileIntA([*:0]const u8, [*:0]const u8, i32, [*:0]const u8) callconv(.winapi) i32;
extern "kernel32" fn WritePrivateProfileStringA([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8) callconv(.winapi) i32;
extern "kernel32" fn SetThreadPriority(*const anyopaque, i32) callconv(.winapi) i32;
extern "kernel32" fn CreateThread(?*const SECURITY_ATTRIBUTES, usize, THREADPROC, ?*anyopaque, u32, ?*u32) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;
extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
extern "kernel32" fn CloseHandle(*const anyopaque) callconv(.winapi) i32;
extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) i32;
extern "kernel32" fn QueryPerformanceFrequency(*i64) callconv(.winapi) i32;

const SECURITY_ATTRIBUTES = extern struct {
    nLength: u32,
    lpSecurityDescriptor: ?*anyopaque,
    bInheritHandle: i32,
};

extern "user32" fn GetWindowLongPtrA(HWND, i32) callconv(.winapi) isize;
extern "user32" fn SetWindowLongPtrA(HWND, i32, isize) callconv(.winapi) isize;
extern "user32" fn SetWindowLongA(HWND, i32, i32) callconv(.winapi) i32;
extern "user32" fn SetWindowTextA(HWND, ?[*:0]const u8) callconv(.winapi) i32;
extern "user32" fn CreateWindowExA(u32, ?[*:0]const u8, ?[*:0]const u8, u32, i32, i32, i32, i32, ?HWND, ?HMENU, ?HMODULE, ?*anyopaque) callconv(.winapi) ?HWND;
extern "user32" fn DestroyWindow(HWND) callconv(.winapi) i32;
extern "user32" fn ShowWindowAsync(HWND, i32) callconv(.winapi) i32;
extern "user32" fn IsWindowVisible(HWND) callconv(.winapi) i32;
extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
extern "user32" fn PostThreadMessageA(u32, u32, usize, isize) callconv(.winapi) i32;
extern "user32" fn SendMessageA(HWND, u32, usize, isize) callconv(.winapi) i32;
extern "user32" fn GetMessageA(*MSG, ?HWND, u32, u32) callconv(.winapi) i32;
extern "user32" fn DispatchMessageA(*const MSG) callconv(.winapi) isize;
extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) i32;
extern "user32" fn RegisterRawInputDevices([*]const RAWINPUTDEVICE, u32, u32) i32;
extern "user32" fn GetRawInputData(isize, u32, ?*anyopaque, *u32, u32) callconv(.winapi) i32;
extern "user32" fn SendInput(cInputs: u32, pInputs: [*]const INPUT, cbSize: i32) callconv(.winapi) u32;
extern "user32" fn LoadIconA(?HMODULE, [*:0]const u8) callconv(.winapi) ?HICON;
extern "user32" fn LoadMenuA(?HMODULE, [*:0]const u8) callconv(.winapi) ?HMENU;
extern "user32" fn DestroyMenu(HMENU) callconv(.winapi) i32;
extern "user32" fn TrackPopupMenu(HMENU, u32, i32, i32, i32, ?HWND, ?*const [4]i32) callconv(.winapi) u32;
extern "user32" fn SetForegroundWindow(HWND) callconv(.winapi) i32;
extern "user32" fn GetSubMenu(HMENU, i32) callconv(.winapi) ?HMENU;
extern "user32" fn MessageBoxA(?HWND, ?[*:0]const u8, ?[*:0]const u8, u32) callconv(.winapi) i32;
extern "user32" fn SetTimer(?HWND, usize, u32, ?TIMERPROC) callconv(.winapi) usize;
extern "user32" fn KillTimer(?HWND, usize) callconv(.winapi) i32;
extern "user32" fn GetClipCursor(*[4]i32) callconv(.winapi) i32;
extern "user32" fn GetCursorPos(*[2]i32) callconv(.winapi) i32;
extern "user32" fn ClipCursor(?*const [4]i32) callconv(.winapi) i32;
extern "user32" fn SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT) callconv(.winapi) DPI_AWARENESS_CONTEXT;
extern "user32" fn CreateDialogParamA(?HMODULE, [*:0]const u8, ?HWND, ?DLGPROC, isize) callconv(.winapi) ?HWND;
extern "user32" fn GetDlgItem(?HWND, i32) callconv(.winapi) ?HWND;
extern "user32" fn SetDlgItemInt(HWND, i32, u32, i32) callconv(.winapi) i32;
extern "user32" fn GetDlgItemInt(HWND, i32, ?*i32, i32) callconv(.winapi) u32;
extern "user32" fn GetDlgItemTextA(HWND, i32, [*:0]u8, i32) callconv(.winapi) u32;
extern "user32" fn IsDialogMessageA(HWND, *MSG) callconv(.winapi) i32;
extern "user32" fn IsDlgButtonChecked(HWND, i32) callconv(.winapi) u32;
extern "user32" fn CheckDlgButton(HWND, i32, u32) callconv(.winapi) i32;
extern "user32" fn SetWindowsHookExA(i32, HOOKPROC, ?HMODULE, u32) callconv(.winapi) ?HHOOK;
extern "user32" fn UnhookWindowsHookEx(HHOOK) callconv(.winapi) i32;
extern "user32" fn CallNextHookEx(?HHOOK, i32, usize, isize) callconv(.winapi) isize;
extern "user32" fn CallWindowProcA(WNDPROC, HWND, u32, usize, isize) callconv(.winapi) isize;

const DPI_AWARENESS_CONTEXT = enum(isize) {
    NULL = 0,
    UNAWARE = -1,
    SYSTEM_AWARE = -2,
    PER_MONITOR_AWARE = -3,
    PER_MONITOR_AWARE_V2 = -4,
    UNAWARE_GDISCALED = -5,
};

const WNDPROC = *const fn (HWND, u32, usize, isize) callconv(.winapi) isize;
const DLGPROC = *const fn (HWND, u32, usize, isize) callconv(.winapi) isize;
const HOOKPROC = *const fn (i32, usize, isize) callconv(.winapi) isize;
const TIMERPROC = *const fn (?HWND, u32, usize, u32) callconv(.winapi) void;
const THREADPROC = *const fn (*anyopaque) callconv(.winapi) u32;

const MSLLHOOKSTRUCT = extern struct {
    pt: [2]i32,
    mouseData: u32,
    flags: u32,
    time: u32,
    dwExtraInfo: usize,
};

const MSG = extern struct {
    hWnd: ?HWND,
    message: u32,
    wParam: usize,
    lParam: isize,
    time: u32,
    pt: [2]i32,
    lPrivate: u32,
};

const RAWINPUTDEVICE = extern struct {
    usUsagePage: u16,
    usUsage: u16,
    dwFlags: u32,
    hwndTarget: ?HWND,
};

const RAWINPUT = extern union {
    mi: MOUSE,
    ki: KEYBOARD,
    hi: HID(1),
    pub const HEADER = extern struct {
        dwType: u32,
        dwSize: u32,
        hDevice: ?*anyopaque,
        wParam: usize,
    };
    pub const MOUSE = extern struct {
        header: HEADER,
        data: extern struct {
            usFlags: u16,
            _: u16,
            usButtonFlags: u16,
            usButtonData: i16,
            ulRawButtons: u32,
            lLastX: i32,
            lLastY: i32,
            ulExtraInformation: u32,
        },
    };
    pub const KEYBOARD = extern struct {
        header: HEADER,
        data: extern struct {
            MakeCode: u16,
            Flags: u16,
            Reserved: u16,
            VKey: u16,
            Message: u32,
            ExtraInformation: u32,
        },
    };
    pub fn HID(comptime n: usize) type {
        return extern struct {
            header: HEADER,
            data: extern struct {
                dwSizeHid: u32,
                dwCount: u32,
                bRawData: [n]u8,
            },
        };
    }
};

const INPUT = extern struct {
    type: u32,
    input: extern union {
        mi: MOUSEINPUT,
        ki: KEYBDINPUT,
        hi: HARDWAREINPUT,
    },
    const MOUSEINPUT = extern struct {
        dx: i32 = 0,
        dy: i32 = 0,
        mouseData: i32 = 0,
        dwFlags: u32 = 0,
        time: u32 = 0,
        dwExtraInfo: usize = 0,
    };
    const KEYBDINPUT = extern struct {
        wVK: u16 = 0,
        wScan: u16 = 0,
        dwFlags: u32 = 0,
        time: u32 = 0,
        dwExtraInfo: usize = 0,
    };
    const HARDWAREINPUT = extern struct {
        uMsg: u32 = 0,
        wParamL: u16 = 0,
        wParamH: u16 = 0,
    };
    fn mi(m: MOUSEINPUT)    INPUT { return .{ .type = 0, .input = .{.mi = m} }; }
    fn ki(k: KEYBDINPUT)    INPUT { return .{ .type = 1, .input = .{.ki = k} }; }
    fn hi(h: HARDWAREINPUT) INPUT { return .{ .type = 2, .input = .{.hi = h} }; }
    fn send(inputs: []const INPUT) u32 {
        return SendInput(@truncate(inputs.len), inputs.ptr, @sizeOf(INPUT));
    }
};

extern "shell32" fn IsUserAnAdmin() callconv(.winapi) i32;
extern "shell32" fn ShellExecuteA(?HWND, ?[*:0]const u8, [*:0]const u8, ?[*:0]const u8, ?[*:0]const u8, i32) callconv(.winapi) ?HMODULE;
extern "shell32" fn Shell_NotifyIconGetRect(*const NOTIFYICONIDENTIFIER, *[4]i32) callconv(.winapi) i32;
extern "shell32" fn Shell_NotifyIconA(NIM, *const NOTIFYICONDATAA) callconv(.winapi) i32;

const NIM = enum(u32) {
    ADD = 0,
    MODIFY = 1,
    DELETE = 2,
    SETFOCUS = 3,
    SETVERSION = 4,
};

const NOTIFYICONDATAA = extern struct {
    cbSize: u32 = @sizeOf(NOTIFYICONDATAA),
    hWnd: ?HWND = null,
    uID: u32 = 0,
    uFlags: u32 = 0,
    uCallbackMessage: u32 = 0, // uFlags 1, user defined WM_* message identifier
    hIcon: ?HICON = null, // uFlags 2, tray icon
    szTip: [128]u8 = @splat(0), // uFlags 4, hover tooltips, 64 for below win2k
    dwState: u32 = 0, // uFlags 8, set state flags
    dwStateMask: u32 = 0, // uFlags 8, which dwState to change
    szInfo: [256]u8 = @splat(0), // uFlags 16, balloon text
    uTimeout: u32 = 0, // uFlags 16, or uVersion if calling with SETVERSION
    szInfoTitle: [64]u8 = @splat(0), // balloon title
    dwInfoFlags: u32 = 0, // balloon options
    guidItem: GUID = .{}, // uFlags 32
    hBalloonIcon: ?HICON = null, // custom balloon title icon (require dwInfoFlags 0x4 bit)
};

const NOTIFYICONIDENTIFIER = extern struct {
    cbSize: u32 = @sizeOf(NOTIFYICONIDENTIFIER),
    hWnd: HWND,
    uID: u32,
    guidItem: GUID = .{},
};

const GUID = extern struct {
    Data1: u32 = 0,
    Data2: u16 = 0,
    Data3: u16 = 0,
    Data4: [8]u8 = @splat(0),
};

const manifest = 
\\<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
\\<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
\\    <dependency>
\\        <dependentAssembly>
\\            <assemblyIdentity
\\                type="win32"
\\                name="Microsoft.Windows.Common-Controls"
\\                version="6.0.0.0"
\\                processorArchitecture="*"
\\                publicKeyToken="6595b64144ccf1df"
\\                language="*"
\\            />
\\        </dependentAssembly>
\\    </dependency>
\\</assembly>
;

const resource = 
\\menu MENU {
\\    POPUP "User" {
\\        MENUITEM "Start Thread", 105
\\        MENUITEM "Restart as admin", 103
\\        MENUITEM "About LibreScroll", 102
\\        MENUITEM "Options", 101
\\        MENUITEM "Quit", 100
\\    }
\\    POPUP "Admin" {
\\        MENUITEM "Start Thread", 105
\\        MENUITEM "About LibreScroll", 102
\\        MENUITEM "Options", 101
\\        MENUITEM "Quit", 100
\\    }
\\    POPUP "User" {
\\        MENUITEM "Stop Thread", 104
\\        MENUITEM "Restart as admin", 103
\\        MENUITEM "About LibreScroll", 102
\\        MENUITEM "Options", 101
\\        MENUITEM "Quit", 100
\\    }
\\    POPUP "Admin" {
\\        MENUITEM "Stop Thread", 104
\\        MENUITEM "About LibreScroll", 102
\\        MENUITEM "Options", 101
\\        MENUITEM "Quit", 100
\\    }
\\}
\\
\\
\\CFGDLG DIALOGEX 0x8000, 0x8000, 143, 130
\\STYLE 0x00C80048
\\CAPTION "LibreScroll options"
\\FONT 8.5, "MS Shell Dlg"
\\{
\\    CTEXT           "Friction",         -1,     1,  5 ,     69, 12
\\    CTEXT           "Y-Sensitivity",    -1,     1,  21,     69, 12
\\    CTEXT           "X-Sensitivity",    -1,     1,  37,     69, 12
\\    CTEXT           "Minimum Y Step",   -1,     1,  53,     69, 12
\\    CTEXT           "Minimum X Step",   -1,     1,  69,     69, 12
\\    EDITTEXT                            0x4001, 71, 3,      69, 12, 0x2000
\\    EDITTEXT                            0x4002, 71, 19,     69, 12
\\    EDITTEXT                            0x4003, 71, 35,     69, 12
\\    EDITTEXT                            0x4004, 71, 51,     69, 12, 0x2000
\\    EDITTEXT                            0x4005, 71, 67,     69, 12, 0x2000
\\    AUTOCHECKBOX    "Flick mode",       0x4006, 71, 83,     69, 12
\\    AUTOCHECKBOX    "ThinkPad mode",    0x4007, 71, 99,     69, 12
\\    PUSHBUTTON      "Pause",            104,    2 , 114,    69, 14
\\    DEFPUSHBUTTON   "Apply",            106,    72, 114,    69, 14
\\}
;

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const res = b.addWriteFiles();
    const manifest_file = res.add("main.manifest", manifest);
    const resource_file = res.add("main.rc", resource);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("build.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .unwind_tables = .none,
    });
    exe_mod.addWin32ResourceFile(.{ .file = resource_file });

    const exe = b.addExecutable(.{
        .name = "LibreScroll",
        .root_module = exe_mod,
        .win32_manifest = manifest_file ,
    });
    exe.subsystem = @enumFromInt(1); // windows subsystem
    b.installArtifact(exe);

    const zip_name = "LibreScroll-" ++ LIBRE_SCROLL_VERSION_TEXT ++ ".zip";
    const release_build = b.addSystemCommand(&.{ "zig", "build", "--release=small", "-Dtarget=x86_64-windows-gnu" });
    const release_zip = b.addSystemCommand(&.{ "tar", "-caf", "zig-out/" ++ zip_name, "-C", "zig-out/bin", "LibreScroll.exe" });
    const release_step = b.step("release", "build release artifact");
    release_zip.step.dependOn(&release_build.step);
    release_step.dependOn(&release_zip.step);
}
