// =============================================================================
// Project : tinybasic
// File    : tinybasic\src\win32_gdi.zig
// Author  : Ilija Mandic
// Purpose : Win32 GDI rendering and window integration layer.
// =============================================================================
const std = @import("std");

const BOOL = i32;
const UINT = u32;
const DWORD = u32;
const WORD = u16;
const LONG = i32;
const LPARAM = isize;
const WPARAM = usize;
const LRESULT = isize;

const HANDLE = ?*anyopaque;
const HINSTANCE = HANDLE;
const HICON = HANDLE;
const HCURSOR = HANDLE;
const HBRUSH = HANDLE;
const HDC = HANDLE;
const HWND = HANDLE;
const HBITMAP = HANDLE;
const HGDIOBJ = HANDLE;
const HMENU = HANDLE;

const ATOM = WORD;

const WndProc = ?*const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

const WNDCLASSEXA = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WndProc,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: ?[*:0]const u8,
    lpszClassName: ?[*:0]const u8,
    hIconSm: HICON,
};

const POINT = extern struct {
    x: LONG,
    y: LONG,
};

const RECT = extern struct {
    left: LONG,
    top: LONG,
    right: LONG,
    bottom: LONG,
};

const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

const RGBQUAD = extern struct {
    rgbBlue: u8,
    rgbGreen: u8,
    rgbRed: u8,
    rgbReserved: u8,
};

const BITMAPINFOHEADER = extern struct {
    biSize: DWORD,
    biWidth: LONG,
    biHeight: LONG,
    biPlanes: WORD,
    biBitCount: WORD,
    biCompression: DWORD,
    biSizeImage: DWORD,
    biXPelsPerMeter: LONG,
    biYPelsPerMeter: LONG,
    biClrUsed: DWORD,
    biClrImportant: DWORD,
};

const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]RGBQUAD,
};

extern "user32" fn RegisterClassExA(lpWndClass: *const WNDCLASSEXA) callconv(.winapi) ATOM;
extern "user32" fn CreateWindowExA(
    dwExStyle: DWORD,
    lpClassName: ?[*:0]const u8,
    lpWindowName: ?[*:0]const u8,
    dwStyle: DWORD,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: HWND,
    hMenu: HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) HWND;
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8) callconv(.winapi) HINSTANCE;
extern "user32" fn LoadCursorA(hInstance: HINSTANCE, lpCursorName: ?*const anyopaque) callconv(.winapi) HCURSOR;
extern "user32" fn GetDC(hWnd: HWND) callconv(.winapi) HDC;
extern "user32" fn ReleaseDC(hWnd: HWND, hDC: HDC) callconv(.winapi) i32;
extern "gdi32" fn CreateCompatibleDC(hdc: HDC) callconv(.winapi) HDC;
extern "gdi32" fn DeleteDC(hdc: HDC) callconv(.winapi) i32;
extern "gdi32" fn CreateDIBSection(
    hdc: HDC,
    pbmi: *const BITMAPINFO,
    iUsage: UINT,
    ppvBits: *?*anyopaque,
    hSection: HANDLE,
    dwOffset: DWORD,
) callconv(.winapi) HBITMAP;
extern "gdi32" fn SelectObject(hdc: HDC, h: HGDIOBJ) callconv(.winapi) HGDIOBJ;
extern "gdi32" fn DeleteObject(h: HGDIOBJ) callconv(.winapi) i32;
extern "gdi32" fn SetStretchBltMode(hdc: HDC, mode: i32) callconv(.winapi) i32;
extern "gdi32" fn StretchBlt(
    hdcDest: HDC,
    xDest: i32,
    yDest: i32,
    wDest: i32,
    hDest: i32,
    hdcSrc: HDC,
    xSrc: i32,
    ySrc: i32,
    wSrc: i32,
    hSrc: i32,
    rop: DWORD,
) callconv(.winapi) i32;
extern "user32" fn PeekMessageA(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageA(lpMsg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn DefWindowProcA(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn PostQuitMessage(exitCode: i32) callconv(.winapi) void;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn GetAsyncKeyState(vkey: i32) callconv(.winapi) i16;
extern "user32" fn AdjustWindowRectEx(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD) callconv(.winapi) BOOL;
extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;

const CS_HREDRAW: UINT = 0x0002;
const CS_VREDRAW: UINT = 0x0001;
const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
const WS_VISIBLE: DWORD = 0x10000000;
const CW_USEDEFAULT: i32 = -2147483648;
const IDC_ARROW: usize = 32512;
const BI_RGB: DWORD = 0;
const DIB_RGB_COLORS: UINT = 0;
const PM_REMOVE: UINT = 0x0001;
const COLORONCOLOR: i32 = 3;
const SRCCOPY: DWORD = 0x00CC0020;
const WM_DESTROY: UINT = 0x0002;

pub const Gdi = struct {
    hwnd: HWND,
    hdc: HDC,
    mem_dc: HDC,
    bitmap: HBITMAP,
    old_bitmap: HGDIOBJ,
    pixels: [*]u32,
    width: i32,
    height: i32,
    scale: i32,

    pub fn init(width: i32, height: i32, scale: i32) !Gdi {
        const class_name: [:0]const u8 = "TinyBasicGdi";
        var wc: WNDCLASSEXA = std.mem.zeroes(WNDCLASSEXA);
        wc.cbSize = @sizeOf(WNDCLASSEXA);
        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = wndProc;
        wc.hInstance = GetModuleHandleA(null);
        wc.hCursor = LoadCursorA(null, @as(?*const anyopaque, @ptrFromInt(IDC_ARROW)));
        wc.lpszClassName = class_name;
        _ = RegisterClassExA(&wc);

        const style = WS_OVERLAPPEDWINDOW | WS_VISIBLE;
        var rect = RECT{
            .left = 0,
            .top = 0,
            .right = width * scale,
            .bottom = height * scale,
        };
        _ = AdjustWindowRectEx(&rect, style, 0, 0);
        const win_w = rect.right - rect.left;
        const win_h = rect.bottom - rect.top;
        const hwnd = CreateWindowExA(
            0,
            class_name,
            "TinyBASIC Graphics",
            style,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            win_w,
            win_h,
            null,
            null,
            wc.hInstance,
            null,
        );
        if (hwnd == null) return error.InitFailed;

        const hdc = GetDC(hwnd);
        if (hdc == null) return error.InitFailed;

        const mem_dc = CreateCompatibleDC(hdc);
        if (mem_dc == null) return error.InitFailed;

        var bmi: BITMAPINFO = std.mem.zeroes(BITMAPINFO);
        bmi.bmiHeader.biSize = @sizeOf(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = width;
        bmi.bmiHeader.biHeight = -height;
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        var bits: ?*anyopaque = null;
        const hbitmap = CreateDIBSection(hdc, &bmi, DIB_RGB_COLORS, &bits, null, 0);
        if (hbitmap == null or bits == null) return error.InitFailed;

        const old = SelectObject(mem_dc, @as(HGDIOBJ, hbitmap));
        _ = SetStretchBltMode(hdc, COLORONCOLOR);

        return Gdi{
            .hwnd = hwnd,
            .hdc = hdc,
            .mem_dc = mem_dc,
            .bitmap = hbitmap,
            .old_bitmap = old,
            .pixels = @ptrCast(@alignCast(bits.?)),
            .width = width,
            .height = height,
            .scale = scale,
        };
    }

    pub fn deinit(self: *Gdi) void {
        _ = SelectObject(self.mem_dc, self.old_bitmap);
        _ = DeleteObject(self.bitmap);
        _ = DeleteDC(self.mem_dc);
        _ = ReleaseDC(self.hwnd, self.hdc);
        _ = DestroyWindow(self.hwnd);
    }

    pub fn pump(self: *Gdi) void {
        _ = self;
        var msg: MSG = undefined;
        while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0) {
            _ = TranslateMessage(&msg);
            _ = DispatchMessageA(&msg);
        }
    }

    pub fn clear(self: *Gdi, color: u32) void {
        const count: usize = @intCast(self.width * self.height);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            self.pixels[i] = color;
        }
    }

    pub fn drawSprite(self: *Gdi, x: i32, y: i32, w: i32, h: i32, data: []const u8) void {
        if (w <= 0 or h <= 0) return;
        var row: i32 = 0;
        while (row < h) : (row += 1) {
            var col: i32 = 0;
            while (col < w) : (col += 1) {
                const sx = x + col;
                const sy = y + row;
                if (sx < 0 or sy < 0) continue;
                if (sx >= self.width or sy >= self.height) continue;
                const src_idx: usize = @intCast(row * w + col);
                if (src_idx >= data.len) return;
                const v = data[src_idx];
                const color: u32 = 0xFF000000 | (@as(u32, v) << 16) | (@as(u32, v) << 8) | v;
                const dst_idx: usize = @intCast(sy * self.width + sx);
                self.pixels[dst_idx] = color;
            }
        }
    }

    pub fn drawText(self: *Gdi, x: i32, y: i32, text: []const u8, shade: u8, scale: i32) void {
        const s = std.math.clamp(scale, 1, 8);
        const color = grayToColor(shade);
        var cx = x;
        var cy = y;
        const start_x = x;
        for (text) |ch| {
            if (ch == '\n') {
                cx = start_x;
                cy += 8 * s;
                continue;
            }
            const rows = glyphRows(ch);
            self.drawGlyph(cx, cy, rows, color, s);
            cx += 6 * s;
        }
    }

    pub fn present(self: *Gdi) void {
        _ = StretchBlt(
            self.hdc,
            0,
            0,
            self.width * self.scale,
            self.height * self.scale,
            self.mem_dc,
            0,
            0,
            self.width,
            self.height,
            SRCCOPY,
        );
    }

    fn drawGlyph(self: *Gdi, x: i32, y: i32, rows: [7]u8, color: u32, scale: i32) void {
        var row: usize = 0;
        while (row < rows.len) : (row += 1) {
            const bits = rows[row];
            var col: usize = 0;
            while (col < 5) : (col += 1) {
                const shift: u3 = @intCast(4 - col);
                if ((bits & (@as(u8, 1) << shift)) == 0) continue;
                const px = x + @as(i32, @intCast(col)) * scale;
                const py = y + @as(i32, @intCast(row)) * scale;
                var dy: i32 = 0;
                while (dy < scale) : (dy += 1) {
                    var dx: i32 = 0;
                    while (dx < scale) : (dx += 1) {
                        self.putPixel(px + dx, py + dy, color);
                    }
                }
            }
        }
    }

    fn putPixel(self: *Gdi, x: i32, y: i32, color: u32) void {
        if (x < 0 or y < 0) return;
        if (x >= self.width or y >= self.height) return;
        const idx: usize = @intCast(y * self.width + x);
        self.pixels[idx] = color;
    }
};

fn grayToColor(v: u8) u32 {
    return 0xFF000000 | (@as(u32, v) << 16) | (@as(u32, v) << 8) | v;
}

fn glyphRows(ch: u8) [7]u8 {
    const c = std.ascii.toUpper(ch);
    return switch (c) {
        '0' => .{ 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E },
        '1' => .{ 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E },
        '2' => .{ 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F },
        '3' => .{ 0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E },
        '4' => .{ 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02 },
        '5' => .{ 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E },
        '6' => .{ 0x0E, 0x10, 0x1E, 0x11, 0x11, 0x11, 0x0E },
        '7' => .{ 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 },
        '8' => .{ 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E },
        '9' => .{ 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C },
        'A' => .{ 0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 },
        'B' => .{ 0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E },
        'C' => .{ 0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E },
        'D' => .{ 0x1E, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1E },
        'E' => .{ 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F },
        'F' => .{ 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10 },
        'G' => .{ 0x0E, 0x11, 0x10, 0x10, 0x13, 0x11, 0x0E },
        'H' => .{ 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 },
        'I' => .{ 0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E },
        'J' => .{ 0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0E },
        'K' => .{ 0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11 },
        'L' => .{ 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F },
        'M' => .{ 0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11 },
        'N' => .{ 0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11 },
        'O' => .{ 0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E },
        'P' => .{ 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10 },
        'Q' => .{ 0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D },
        'R' => .{ 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11 },
        'S' => .{ 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E },
        'T' => .{ 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04 },
        'U' => .{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E },
        'V' => .{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04 },
        'W' => .{ 0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A },
        'X' => .{ 0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11 },
        'Y' => .{ 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04 },
        'Z' => .{ 0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F },
        ':' => .{ 0x00, 0x04, 0x04, 0x00, 0x04, 0x04, 0x00 },
        '-' => .{ 0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00 },
        '.' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x06, 0x06 },
        ' ' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        else => .{ 0x00, 0x00, 0x0A, 0x00, 0x0A, 0x00, 0x00 },
    };
}

pub fn keyDown(vkey: i32) bool {
    const state: u16 = @bitCast(GetAsyncKeyState(vkey));
    return (state & 0x8000) != 0;
}

pub fn sleepMs(ms: u32) void {
    Sleep(ms);
}

fn wndProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
    switch (msg) {
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return DefWindowProcA(hwnd, msg, wparam, lparam);
}
