// The docked sidebar's resize strip (CraCEFWin.h, MARK: Resize strip): an all-but-transparent
// window owned by the browser window, over the sidebar's edge and the page beside it, showing
// the left-right pointer and reporting a press, its drag and its end. Main thread.
#include "CraCEFWin.h"

#include <windows.h>

#include <algorithm>

namespace {

const wchar_t *kStripClass = L"CraResizeStrip";

struct Strip {
    void *context;
    CraStripDragged dragged;
    bool dragging = false;
};

void Report(Strip *s, int phase) {
    POINT p{};
    GetCursorPos(&p);
    if (s->dragged) s->dragged(s->context, phase, p.x, static_cast<double>(GetMessageTime()) / 1000.0);
}

LRESULT CALLBACK StripProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_NCCREATE) {
        auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto *s = reinterpret_cast<Strip *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (message) {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_SETCURSOR:
        SetCursor(LoadCursorW(nullptr, IDC_SIZEWE));
        return TRUE;
    case WM_LBUTTONDOWN:
        if (s) {
            SetCapture(hwnd);
            s->dragging = true;
            Report(s, 0);
        }
        return 0;
    case WM_MOUSEMOVE:
        if (s && s->dragging) Report(s, 1);
        return 0;
    case WM_LBUTTONUP:
        // Losing the capture ends the drag (below), as Alt+Tab or a menu taking it would.
        if (s && s->dragging) ReleaseCapture();
        return 0;
    case WM_CAPTURECHANGED:
        if (s && s->dragging) {
            s->dragging = false;
            Report(s, 2);
        }
        return 0;
    case WM_NCDESTROY:
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        delete s;
        break;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

}  // namespace

extern "C" uintptr_t cra_resize_strip_create(uintptr_t owner, void *context, CraStripDragged dragged) {
    static bool registered = false;
    if (!registered) {
        registered = true;
        WNDCLASSEXW c{sizeof(c)};
        c.lpfnWndProc = StripProc;
        c.hInstance = GetModuleHandleW(nullptr);
        c.hCursor = LoadCursorW(nullptr, IDC_SIZEWE);
        c.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
        c.lpszClassName = kStripClass;
        RegisterClassExW(&c);
    }
    auto *s = new Strip{context, dragged};
    HWND hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kStripClass, L"", WS_POPUP, 0, 0, 0, 0,
                                reinterpret_cast<HWND>(owner), nullptr, GetModuleHandleW(nullptr), s);
    if (!hwnd) {
        delete s;
        return 0;
    }
    // 1 of 255: unseen, but still hit by the mouse (a layered window at 0 lets clicks through).
    SetLayeredWindowAttributes(hwnd, 0, 1, LWA_ALPHA);
    return reinterpret_cast<uintptr_t>(hwnd);
}

extern "C" void cra_resize_strip_place(uintptr_t strip, int x, int y, int width, int height) {
    if (!strip) return;
    HWND hwnd = reinterpret_cast<HWND>(strip);
    if (width <= 0 || height <= 0) {
        ShowWindow(hwnd, SW_HIDE);
        return;
    }
    // In front of its owner's other windows when it first shows; after that it keeps its place,
    // under whatever came over the window since (a Peek, the command bar).
    const UINT keep = IsWindowVisible(hwnd) ? SWP_NOZORDER : 0;
    SetWindowPos(hwnd, HWND_TOP, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOOWNERZORDER | keep);
}

extern "C" void cra_resize_strip_destroy(uintptr_t strip) {
    if (strip) DestroyWindow(reinterpret_cast<HWND>(strip));
}
