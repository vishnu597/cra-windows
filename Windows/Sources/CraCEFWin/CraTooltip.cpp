// Arc's hover tips (CraCEFWin.h, MARK: Arc tips): one layered window, topmost and never focused
// or clicked, drawn with GDI+ in the space's tones: a capsule with the text and key caps. The
// shell decides when and where (CraCore's ArcTooltipRules); this measures and draws. Main thread.
#include "CraCEFWin.h"

#include <windows.h>
#include <objidl.h>

#include <algorithm>
// GDI+'s headers use min and max, which NOMINMAX takes away.
namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

#include <cmath>
#include <string>
#include <vector>

namespace {

std::wstring Wide(const char *utf8) {
    if (!utf8 || !*utf8) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    std::wstring out(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out.data(), n);
    return out;
}

void StartGdiplus() {
    static ULONG_PTR token = 0;
    if (!token) {
        Gdiplus::GdiplusStartupInput input;
        Gdiplus::GdiplusStartup(&token, &input, nullptr);
    }
}

const wchar_t *kArcTipClass = L"CraArcTip";
HWND gTip = nullptr;

LRESULT CALLBACK ArcTipProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

HWND TipWindow() {
    if (gTip && IsWindow(gTip)) return gTip;
    static bool registered = false;
    if (!registered) {
        registered = true;
        WNDCLASSEXW c{sizeof(c)};
        c.lpfnWndProc = ArcTipProc;
        c.hInstance = GetModuleHandleW(nullptr);
        c.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        c.lpszClassName = kArcTipClass;
        RegisterClassExW(&c);
    }
    gTip = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TRANSPARENT, kArcTipClass, L"",
                           WS_POPUP, 0, 0, 1, 1, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    return gTip;
}

// Arc's 12 pt medium text; the caps' 10 pt bold.
const wchar_t *kTextFamily = L"Segoe UI Semibold";
const wchar_t *kCapFamily = L"Segoe UI";

Gdiplus::Color ColorOf(uint32_t rgb, BYTE alpha = 255) {
    return Gdiplus::Color(alpha, static_cast<BYTE>((rgb >> 16) & 0xFF), static_cast<BYTE>((rgb >> 8) & 0xFF), static_cast<BYTE>(rgb & 0xFF));
}

void AddRoundRect(Gdiplus::GraphicsPath &path, Gdiplus::REAL x, Gdiplus::REAL y, Gdiplus::REAL w, Gdiplus::REAL h, Gdiplus::REAL r) {
    r = std::min({r, w / 2, h / 2});
    if (r <= 0) {
        path.AddRectangle(Gdiplus::RectF(x, y, w, h));
        return;
    }
    path.AddArc(x, y, 2 * r, 2 * r, 180, 90);
    path.AddArc(x + w - 2 * r, y, 2 * r, 2 * r, 270, 90);
    path.AddArc(x + w - 2 * r, y + h - 2 * r, 2 * r, 2 * r, 0, 90);
    path.AddArc(x, y + h - 2 * r, 2 * r, 2 * r, 90, 90);
    path.CloseFigure();
}

}  // namespace

extern "C" void cra_arc_tip_measure(const char *text, double max_width, const char *const *keys, size_t count, double *text_width,
                                    double *text_height, double *key_widths) {
    StartGdiplus();
    const std::wstring wide = Wide(text);
    HDC screen = GetDC(nullptr);
    {
        Gdiplus::Graphics g(screen);
        g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
        // Measured at 1 DIP a pixel; the caller works in DIPs.
        Gdiplus::Font font(kTextFamily, 12, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
        Gdiplus::RectF one, wrapped;
        g.MeasureString(wide.c_str(), -1, &font, Gdiplus::PointF(0, 0), &one);
        if (one.Width > max_width) {
            g.MeasureString(wide.c_str(), -1, &font, Gdiplus::RectF(0, 0, static_cast<Gdiplus::REAL>(max_width), 1000), nullptr, &wrapped);
            if (text_width) *text_width = one.Width;  // past the limit: the caller wraps
            if (text_height) *text_height = std::min<double>(wrapped.Height, 3 * one.Height);
        } else {
            if (text_width) *text_width = one.Width;
            if (text_height) *text_height = one.Height;
        }
        Gdiplus::Font capFont(kCapFamily, 10, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
        for (size_t i = 0; i < count && key_widths; ++i) {
            const std::wstring key = Wide(keys ? keys[i] : nullptr);
            Gdiplus::RectF box;
            g.MeasureString(key.c_str(), -1, &capFont, Gdiplus::PointF(0, 0), &box);
            key_widths[i] = box.Width;
        }
    }
    ReleaseDC(nullptr, screen);
}

extern "C" double cra_arc_tip_measure_badge(const char *name) {
    StartGdiplus();
    const std::wstring wide = Wide(name);
    double width = 0;
    HDC screen = GetDC(nullptr);
    {
        Gdiplus::Graphics g(screen);
        g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
        Gdiplus::Font font(kTextFamily, 11, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
        Gdiplus::RectF box;
        g.MeasureString(wide.c_str(), -1, &font, Gdiplus::PointF(0, 0), &box);
        width = box.Width;
    }
    ReleaseDC(nullptr, screen);
    return width;
}

namespace {

// The Mac's ProfileAvatarView in a 14 DIP box at `x, y`: a faint disc, two eyes and a smile.
void DrawAvatar(Gdiplus::Graphics &g, Gdiplus::REAL x, Gdiplus::REAL y, uint32_t ink) {
    Gdiplus::SolidBrush disc(ColorOf(ink, 26)), solid(ColorOf(ink));
    g.FillEllipse(&disc, x, y, 14.0f, 14.0f);
    for (Gdiplus::REAL ex : {4.5f, 8.0f}) {
        Gdiplus::GraphicsPath eye;
        AddRoundRect(eye, x + ex, y + 3, 1.5f, 4, 0.75f);
        g.FillPath(&solid, &eye);
    }
    Gdiplus::Pen smile(ColorOf(ink), 1.35f);
    smile.SetStartCap(Gdiplus::LineCapRound);
    smile.SetEndCap(Gdiplus::LineCapRound);
    g.DrawBezier(&smile, x + 4.1f, y + 9.6f, x + 6.03f, y + 10.67f, x + 7.97f, y + 10.67f, x + 9.9f, y + 9.6f);
}

}  // namespace

extern "C" void cra_arc_tip_show(int x, int y, double width, double height, double scale, double corner, const char *text,
                                 double text_width, const char *const *keys, const double *cap_widths, size_t count,
                                 const char *badge, double badge_x, double badge_width, const CraArcTipColors *colors) {
    if (!colors || width <= 0 || height <= 0) return;
    HWND tip = TipWindow();
    if (!tip) return;
    StartGdiplus();
    const int w = static_cast<int>(std::ceil(width * scale)), h = static_cast<int>(std::ceil(height * scale));
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = w;
    info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HDC screen = GetDC(nullptr);
    HDC memory = CreateCompatibleDC(screen);
    HBITMAP dib = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (dib && bits) {
        HGDIOBJ old = SelectObject(memory, dib);
        {
            Gdiplus::Bitmap canvas(w, h, w * 4, PixelFormat32bppPARGB, static_cast<BYTE *>(bits));
            Gdiplus::Graphics g(&canvas);
            g.Clear(Gdiplus::Color(0, 0, 0, 0));
            g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
            g.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
            g.ScaleTransform(static_cast<Gdiplus::REAL>(scale), static_cast<Gdiplus::REAL>(scale));
            const auto W = static_cast<Gdiplus::REAL>(width), H = static_cast<Gdiplus::REAL>(height);
            const Gdiplus::REAL ring = static_cast<Gdiplus::REAL>(1 / scale);  // one pixel
            Gdiplus::GraphicsPath shape;
            AddRoundRect(shape, ring / 2, ring / 2, W - ring, H - ring, static_cast<Gdiplus::REAL>(corner));
            Gdiplus::SolidBrush fill(ColorOf(colors->fill));
            g.FillPath(&fill, &shape);
            Gdiplus::Pen edge(ColorOf(colors->ring), ring);
            g.DrawPath(&edge, &shape);

            // The text, 10 DIPs in, centred; wrapped at its measured width when it runs long.
            Gdiplus::Font font(kTextFamily, 12, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
            Gdiplus::SolidBrush title(ColorOf(colors->title));
            const std::wstring wide = Wide(text);
            Gdiplus::StringFormat format;
            format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
            format.SetTrimming(Gdiplus::StringTrimmingEllipsisWord);
            const auto textW = static_cast<Gdiplus::REAL>(text_width);
            g.DrawString(wide.c_str(), -1, &font, Gdiplus::RectF(10, 0, textW + 2, H), &format, &title);

            // Key caps: a face over a darker edge, the glyph centred on the face.
            Gdiplus::Font capFont(kCapFamily, 10, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
            Gdiplus::SolidBrush capEdge(ColorOf(colors->cap_edge)), capFace(ColorOf(colors->cap)), capGlyph(ColorOf(colors->cap_glyph));
            Gdiplus::StringFormat centred;
            centred.SetAlignment(Gdiplus::StringAlignmentCenter);
            centred.SetLineAlignment(Gdiplus::StringAlignmentCenter);
            Gdiplus::REAL cx = 10 + textW + 6;
            const Gdiplus::REAL cap = 19, top = (H - cap) / 2;

            // A space icon's profile pill: 22 DIPs tall, the avatar 6 in, the name 3 after it.
            if (badge && *badge && badge_width > 0) {
                const auto px = static_cast<Gdiplus::REAL>(badge_x), pw = static_cast<Gdiplus::REAL>(badge_width);
                const Gdiplus::REAL ph = 22, py = (H - ph) / 2;
                Gdiplus::GraphicsPath pill;
                AddRoundRect(pill, px, py, pw, ph, ph / 2);
                g.FillPath(&capFace, &pill);
                DrawAvatar(g, px + 6, py + (ph - 14) / 2, colors->cap_glyph);
                Gdiplus::Font nameFont(kTextFamily, 11, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
                Gdiplus::StringFormat left;
                left.SetLineAlignment(Gdiplus::StringAlignmentCenter);
                left.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
                const std::wstring name = Wide(badge);
                g.DrawString(name.c_str(), -1, &nameFont, Gdiplus::RectF(px + 6 + 14 + 3, py, pw - 23, ph), &left, &capGlyph);
                cx = px + pw + 6;
            }
            for (size_t i = 0; i < count; ++i) {
                const auto cw = static_cast<Gdiplus::REAL>(cap_widths ? cap_widths[i] : cap);
                Gdiplus::GraphicsPath outer, face;
                AddRoundRect(outer, cx, top, cw, cap, 4.5f);
                g.FillPath(&capEdge, &outer);
                AddRoundRect(face, cx + 1, top + 1, cw - 2, cap - 3.5f, 3.5f);
                g.FillPath(&capFace, &face);
                const std::wstring key = Wide(keys ? keys[i] : nullptr);
                g.DrawString(key.c_str(), -1, &capFont, Gdiplus::RectF(cx + 1, top + 1, cw - 2, cap - 3.5f), &centred, &capGlyph);
                cx += cw + 3;
            }
        }
        POINT origin{x, y}, zero{0, 0};
        SIZE size{w, h};
        BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
        UpdateLayeredWindow(tip, screen, &origin, &size, memory, &zero, 0, &blend, ULW_ALPHA);
        SelectObject(memory, old);
        SetWindowPos(tip, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
    if (dib) DeleteObject(dib);
    DeleteDC(memory);
    ReleaseDC(nullptr, screen);
}

extern "C" void cra_arc_tip_hide(void) {
    if (gTip && IsWindow(gTip)) ShowWindow(gTip, SW_HIDE);
}
