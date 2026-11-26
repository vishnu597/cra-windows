// An emoji drawn to pixels (CraCEFWin.h, cra_emoji_render), so the space dock can fade an unlit
// space's emoji the way the Mac's Core Image filter does: XAML can't desaturate a colour font's
// glyph, but it can show premultiplied BGRA in a WriteableBitmap. Direct2D draws the emoji in
// colour (Segoe UI Emoji's layers) into a WIC bitmap; nothing here touches CEF. Any thread.
#include "CraCEFWin.h"

#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>

#include <cstdlib>
#include <string>

namespace {

const CLSID kWICImagingFactory = {0xcacaf262, 0x9370, 0x4615, {0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a}};
const GUID kPixelFormat32bppPBGRA = {0x6fddc324, 0x4e03, 0x4bfe, {0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x10}};

std::wstring Wide(const char *utf8) {
    if (!utf8 || !*utf8) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    std::wstring out(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out.data(), n);
    return out;
}

template <typename T>
struct Com {
    T *p = nullptr;
    ~Com() {
        if (p) p->Release();
    }
    T *operator->() const { return p; }
    T **operator&() { return &p; }
    explicit operator bool() const { return p != nullptr; }
};

struct ComScope {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    ~ComScope() {
        if (SUCCEEDED(hr)) CoUninitialize();
    }
};

/// `text` in `family` (the first of a ';'-separated list the system has), centred in the square.
int Render(const char *text, const wchar_t *families, int side, CraImage *out) {
    if (!text || !*text || side <= 0 || side > 512 || !out) return 0;
    *out = CraImage{};
    const std::wstring wide = Wide(text);
    ComScope com;
    Com<IWICImagingFactory> wic;
    if (FAILED(CoCreateInstance(kWICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic)))) return 0;
    Com<IWICBitmap> bitmap;
    if (FAILED(wic->CreateBitmap(UINT(side), UINT(side), kPixelFormat32bppPBGRA, WICBitmapCacheOnLoad, &bitmap))) return 0;
    Com<ID2D1Factory> d2d;
    if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), nullptr,
                                 reinterpret_cast<void **>(&d2d))))
        return 0;
    Com<IDWriteFactory> dwrite;
    if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(&dwrite))))
        return 0;
    D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
    Com<ID2D1RenderTarget> target;
    if (FAILED(d2d->CreateWicBitmapRenderTarget(bitmap.p, &props, &target))) return 0;
    // The emoji fills the square as XAML's 14 DIP glyph fills its 18 DIP box.
    Com<IDWriteTextFormat> format;
    const FLOAT size = FLOAT(side) * 0.75f;
    std::wstring family;
    {
        Com<IDWriteFontCollection> fonts;
        std::wstring list(families);
        size_t start = 0;
        while (start <= list.size()) {
            size_t end = list.find(L';', start);
            if (end == std::wstring::npos) end = list.size();
            std::wstring name = list.substr(start, end - start);
            if (family.empty()) family = name;  // the first, should none be installed
            UINT32 index = 0;
            BOOL exists = FALSE;
            if (!fonts && FAILED(dwrite->GetSystemFontCollection(&fonts))) break;
            if (SUCCEEDED(fonts->FindFamilyName(name.c_str(), &index, &exists)) && exists) {
                family = name;
                break;
            }
            start = end + 1;
        }
    }
    if (FAILED(dwrite->CreateTextFormat(family.c_str(), nullptr, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
                                        DWRITE_FONT_STRETCH_NORMAL, size, L"", &format)))
        return 0;
    format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
    format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    Com<ID2D1SolidColorBrush> ink;
    if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &ink))) return 0;
    target->BeginDraw();
    target->Clear(D2D1::ColorF(0, 0, 0, 0));
    target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    target->DrawText(wide.c_str(), UINT32(wide.size()), format.p, D2D1::RectF(0, 0, FLOAT(side), FLOAT(side)), ink.p,
                     D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
    if (FAILED(target->EndDraw())) return 0;
    const size_t bytes = size_t(side) * side * 4;
    auto *pixels = static_cast<uint8_t *>(malloc(bytes));
    if (!pixels) return 0;
    if (FAILED(bitmap->CopyPixels(nullptr, UINT(side) * 4, UINT(bytes), pixels))) {
        free(pixels);
        return 0;
    }
    out->width = side;
    out->height = side;
    out->pixels = pixels;
    return 1;
}

}  // namespace

extern "C" int cra_emoji_render(const char *text, int side, CraImage *out) {
    return Render(text, L"Segoe UI Emoji", side, out);
}

extern "C" int cra_symbol_render(const char *text, int side, CraImage *out) {
    return Render(text, L"Segoe Fluent Icons;Segoe MDL2 Assets", side, out);
}
