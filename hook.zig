extern "user32" fn GetMessageA(*MSG, ?HWND, u32, u32) callconv(.winapi) i32;
extern "user32" fn DispatchMessageA(*const MSG) callconv(.winapi) isize;
extern "user32" fn SetWindowsHookExA(i32, HOOKPROC, ?HMODULE, u32) callconv(.winapi) ?HHOOK;
extern "user32" fn UnhookWindowsHookEx(HHOOK) callconv(.winapi) i32;
extern "user32" fn CallNextHookEx(?HHOOK, i32, usize, isize) callconv(.winapi) isize;

fn hookProc(code: i32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    if (code >= 0 and (wParam == 0x207 or wParam == 0x208)) {
        const inf: *const MSLLHOOKSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
        const pass: usize = @bitCast(MAGIC_WORD);
        if (0 == 3 & inf.flags or pass != inf.dwExtraInfo) return 1;
    }
    return CallNextHookEx(null, code, wParam, lParam);
}

export fn hookMain(_: ?*anyopaque) callconv(.winapi) u32 {
    const hhook = SetWindowsHookExA(14, hookProc, null, 0) orelse return 0;
    defer _ = UnhookWindowsHookEx(hhook);
    var msg: MSG = undefined;
    while (GetMessageA(&msg, null, 0, 0) > 0) {
        _ = DispatchMessageA(&msg);
    }
    return 0;
}

const MAGIC_WORD: [8]u8 = "PASS\x00\x00\x00\x00".*;

const HMODULE = *const opaque{};
const HWND = *const opaque{};
const HHOOK = *const opaque{};

const HOOKPROC = *const fn (i32, usize, isize) callconv(.winapi) isize;

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
