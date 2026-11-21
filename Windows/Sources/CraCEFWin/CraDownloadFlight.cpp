// Arc's download flight (CraCEFWin.h, MARK: Download flight): the glyph thrown from the pointer
// onto the sidebar's downloads button as a download starts, the Mac's DownloadFlight. A small
// borderless layered window, owned by the browser window, that the mouse goes through; the shell
// computes each frame (CraCore's DownloadFlightPath) and this draws it with per-pixel alpha and
// moves the window there. Plain Win32; nothing here touches CEF. Main thread.
#include "CraCEFWin.h"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace {

const wchar_t *kFlightClass = L"CraDownloadFlight";

LRESULT CALLBACK FlightProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

void RegisterFlightClass() {
    static bool done = false;
    if (done) return;
    done = true;
    WNDCLASSEXW c{sizeof(c)};
    c.lpfnWndProc = FlightProc;
    c.hInstance = GetModuleHandleW(nullptr);
    c.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    c.lpszClassName = kFlightClass;
    RegisterClassExW(&c);
}

/// Distance from (x, y) to the segment from (ax, ay) to (bx, by).
double SegmentDistance(double x, double y, double ax, double ay, double bx, double by) {
    double dx = bx - ax, dy = by - ay;
    double len = dx * dx + dy * dy;
    double t = len > 0 ? std::clamp(((x - ax) * dx + (y - ay) * dy) / len, 0.0, 1.0) : 0;
    return std::hypot(x - (ax + t * dx), y - (ay + t * dy));
}

struct Colour {
    double r, g, b, a;
};

/// `top` over `under`, both straight (not premultiplied) alpha.
Colour Over(Colour top, Colour under) {
    double a = top.a + under.a * (1 - top.a);
    if (a <= 0) return {0, 0, 0, 0};
    auto mix = [&](double t, double u) { return (t * top.a + u * under.a * (1 - top.a)) / a; };
    return {mix(top.r, under.r), mix(top.g, under.g), mix(top.b, under.b), a};
}

}  // namespace

extern "C" uintptr_t cra_download_flight_create(uintptr_t owner) {
    RegisterFlightClass();
    HWND hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, kFlightClass, L"",
                                WS_POPUP, 0, 0, 1, 1, reinterpret_cast<HWND>(owner), nullptr, GetModuleHandleW(nullptr), nullptr);
    return reinterpret_cast<uintptr_t>(hwnd);
}

extern "C" void cra_download_flight_draw(uintptr_t flight, int center_x, int center_y, double diameter, double angle,
                                         double opacity, double glow) {
    HWND hwnd = reinterpret_cast<HWND>(flight);
    if (!hwnd || diameter <= 0) return;
    const double R = diameter / 2;
    const int side = static_cast<int>(std::ceil(diameter + 2 * glow)) + 2;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(info.bmiHeader);
    info.bmiHeader.biWidth = side;
    info.bmiHeader.biHeight = -side;  // top-down
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
    std::memset(pixels, 0, static_cast<size_t>(side) * side * 4);

    // The Mac's glyph: a navy disc with a light ring 2.5/48 of it wide, a down arrow 0.42 of it
    // tall in the light colour, and a blue glow (its shadow, radius 9 at 0.55).
    const Colour navy{4, 7, 42, 1}, light{239, 239, 255, 1};
    const double ring = diameter * 2.5 / 48;
    const double half = diameter * 0.21, stroke = std::max(1.0, diameter * 0.075), head = diameter * 0.16;
    // The arrow along (−sin θ, cos θ): ↓ at 0, ↘ at −π/4 (y down).
    const double ux = -std::sin(angle), uy = std::cos(angle);
    const double px_ = -uy, py_ = ux;  // across it
    const double c = side / 2.0;
    const double tipX = c + ux * half, tipY = c + uy * half, tailX = c - ux * half, tailY = c - uy * half;
    const double backX = tipX - ux * head, backY = tipY - uy * head;
    const double leftX = backX + px_ * head, leftY = backY + py_ * head;
    const double rightX = backX - px_ * head, rightY = backY - py_ * head;
    const double sigma = std::max(1.0, glow / 2);
    opacity = std::clamp(opacity, 0.0, 1.0);
    for (int y = 0; y < side; ++y) {
        for (int x = 0; x < side; ++x) {
            double fx = x + 0.5, fy = y + 0.5;
            double r = std::hypot(fx - c, fy - c);
            Colour out{0, 0, 0, 0};
            if (r > R - 1) {
                double d = std::max(0.0, r - R);
                out = {26, 107, 217, 0.55 * std::exp(-d * d / (2 * sigma * sigma))};
            }
            double disc = std::clamp(R + 0.5 - r, 0.0, 1.0);
            if (disc > 0) {
                double inRing = std::clamp(r - (R - ring) + 0.5, 0.0, 1.0);
                double arrow = std::min({SegmentDistance(fx, fy, tailX, tailY, tipX, tipY),
                                         SegmentDistance(fx, fy, leftX, leftY, tipX, tipY),
                                         SegmentDistance(fx, fy, rightX, rightY, tipX, tipY)});
                double onArrow = std::clamp(stroke / 2 + 0.5 - arrow, 0.0, 1.0);
                double lit = std::max(inRing, onArrow);
                Colour face{navy.r + (light.r - navy.r) * lit, navy.g + (light.g - navy.g) * lit,
                            navy.b + (light.b - navy.b) * lit, disc};
                out = Over(face, out);
            }
            double a = std::clamp(out.a * opacity, 0.0, 1.0);
            if (a <= 0) continue;
            auto A = static_cast<uint32_t>(std::lround(a * 255));
            auto Rr = static_cast<uint32_t>(std::lround(out.r * a)), G = static_cast<uint32_t>(std::lround(out.g * a)),
                 B = static_cast<uint32_t>(std::lround(out.b * a));
            pixels[y * side + x] = (A << 24) | (Rr << 16) | (G << 8) | B;  // premultiplied BGRA
        }
    }
    POINT origin{center_x - side / 2, center_y - side / 2}, source{0, 0};
    SIZE size{side, side};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    UpdateLayeredWindow(hwnd, screen, &origin, &size, dc, &source, 0, &blend, ULW_ALPHA);
    SelectObject(dc, old);
    DeleteObject(bitmap);
    DeleteDC(dc);
    ReleaseDC(nullptr, screen);
    if (!IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_SHOWNOACTIVATE);
}

extern "C" void cra_download_flight_destroy(uintptr_t flight) {
    if (HWND hwnd = reinterpret_cast<HWND>(flight)) DestroyWindow(hwnd);
}
