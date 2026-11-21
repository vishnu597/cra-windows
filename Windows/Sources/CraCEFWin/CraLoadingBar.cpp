// Arc's loading bar at the top middle of a browser window (CraCEFWin.h, MARK: Loading bar): a
// borderless layered window owned by the browser window, over its page, that the mouse goes
// through. The shell computes each frame (CraCore's LoadingIndicator.Clock) and this draws it
// with per-pixel alpha. Plain Win32; nothing here touches CEF. Main thread.
#include "CraCEFWin.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace {

const wchar_t *kLoadingBarClass = L"CraLoadingBar";

LRESULT CALLBACK LoadingBarProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

void RegisterLoadingBarClass() {
    static bool done = false;
    if (done) return;
    done = true;
    WNDCLASSEXW c{sizeof(c)};
    c.lpfnWndProc = LoadingBarProc;
    c.hInstance = GetModuleHandleW(nullptr);
    c.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    c.lpszClassName = kLoadingBarClass;
    RegisterClassExW(&c);
}

/// How much of the pixel at (px, py) (its centre at +0.5) a capsule from `left` to `right`,
/// `top` to `top + height`, covers: a signed distance to its edge, softened over one pixel.
double CapsuleCoverage(double px, double py, double left, double right, double top, double height) {
    double r = height / 2, cy = top + r;
    double x = px + 0.5, y = py + 0.5;
    double cx = std::clamp(x, left + r, std::max(left + r, right - r));
    double d = std::hypot(x - cx, y - cy) - r;
    return std::clamp(0.5 - d, 0.0, 1.0);
}

}  // namespace

extern "C" uintptr_t cra_loading_bar_create(uintptr_t owner) {
    RegisterLoadingBarClass();
    HWND hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, kLoadingBarClass, L"",
                                WS_POPUP, 0, 0, 1, 1, reinterpret_cast<HWND>(owner), nullptr, GetModuleHandleW(nullptr), nullptr);
    return reinterpret_cast<uintptr_t>(hwnd);
}

extern "C" void cra_loading_bar_draw(uintptr_t bar, int x, int y, int width, int height, double scale, double track_width,
                                     double bar_height, double opacity, int lit, double segment_start, double segment_end,
                                     uint32_t ink, double bright_alpha, double track_alpha) {
    HWND hwnd = reinterpret_cast<HWND>(bar);
    if (!hwnd || width <= 0 || height <= 0) return;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(info.bmiHeader);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;  // top-down
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    HDC screen = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(screen);
    void *bits = nullptr;
    HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bitmap || !bits) {
        if (bitmap) DeleteObject(bitmap);
        DeleteDC(dc);
        ReleaseDC(nullptr, screen);
        return;
    }
    HGDIOBJ old = SelectObject(dc, bitmap);
    auto *pixels = static_cast<uint32_t *>(bits);
    std::memset(pixels, 0, static_cast<size_t>(width) * height * 4);

    const double w = std::max(0.0, track_width * scale), h = std::max(1.0, bar_height * scale);
    const double left = (width - w) / 2, right = left + w, top = (height - h) / 2;
    const bool segment = !lit && segment_start >= 0 && segment_end > segment_start;
    const double segLeft = left + w * std::clamp(segment_start, 0.0, 1.0), segRight = left + w * std::clamp(segment_end, 0.0, 1.0);
    const double r = ((ink >> 16) & 0xFF), g = ((ink >> 8) & 0xFF), b = (ink & 0xFF);
    opacity = std::clamp(opacity, 0.0, 1.0);
    for (int py = 0; py < height; ++py) {
        for (int px = 0; px < width; ++px) {
            double cover = w > 0 ? CapsuleCoverage(px, py, left, right, top, h) : 0;
            if (cover <= 0) continue;
            double a = lit ? bright_alpha : track_alpha;
            if (segment) {
                // The bright segment inside the track, its ends softened over a pixel.
                double inside = std::clamp(std::min(px + 1 - segLeft, segRight - px), 0.0, 1.0);
                a = track_alpha + (bright_alpha - track_alpha) * inside;
            }
            double alpha = std::clamp(cover * a * opacity, 0.0, 1.0);
            auto A = static_cast<uint32_t>(std::lround(alpha * 255));
            auto R = static_cast<uint32_t>(std::lround(r * alpha)), G = static_cast<uint32_t>(std::lround(g * alpha)),
                 B = static_cast<uint32_t>(std::lround(b * alpha));
            pixels[py * width + px] = (A << 24) | (R << 16) | (G << 8) | B;  // premultiplied BGRA
        }
    }
    POINT origin{x, y}, source{0, 0};
    SIZE size{width, height};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    UpdateLayeredWindow(hwnd, screen, &origin, &size, dc, &source, 0, &blend, ULW_ALPHA);
    SelectObject(dc, old);
    DeleteObject(bitmap);
    DeleteDC(dc);
    ReleaseDC(nullptr, screen);
    if (!IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_SHOWNOACTIVATE);
}

extern "C" void cra_loading_bar_hide(uintptr_t bar) {
    if (HWND hwnd = reinterpret_cast<HWND>(bar)) ShowWindow(hwnd, SW_HIDE);
}

extern "C" void cra_loading_bar_destroy(uintptr_t bar) {
    if (HWND hwnd = reinterpret_cast<HWND>(bar)) DestroyWindow(hwnd);
}
