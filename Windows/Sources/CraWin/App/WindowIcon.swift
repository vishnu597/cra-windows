import CraCEFWin
import CraCore
import Foundation
import WinSDK

/// Cra's icon on a window's title bar, taskbar button and Alt+Tab entry. An AppWindow has none
/// of its own, so Windows showed its generic window icon. The icon is Cra.exe's (Resources/Cra.rc,
/// icon 1: Segments) or the one picked in Settings ▸ General (`AppIconChoice`, the Mac's
/// AppIconManager): one of resources/app-icons beside Cra.exe, made into icons at the system's
/// sizes and given to every window Cra has open. The pick is kept under HKCU\Software\Cra, as
/// the Mac keeps it in its defaults. A taskbar pin and the Start menu keep Cra.exe's own icon.
enum WindowIcon {
    // WM_SETICON, ICON_SMALL / ICON_BIG, IMAGE_ICON, SM_CXICON, SM_CXSMICON: macros Swift can't see.
    private static let setIcon: UINT = 0x0080, imageIcon: UINT = 1
    private static let bigSize: Int32 = 11, smallSize: Int32 = 49

    /// Cra.exe's own, loaded once: shared icons stay valid for the life of the process.
    nonisolated(unsafe) private static let exeIcons: (small: HANDLE?, big: HANDLE?) = (load(smallSize), load(bigSize))
    /// The picked preset's, made by Cra (destroyed when another is picked); nil for Cra.exe's.
    nonisolated(unsafe) private static var picked: (id: String, small: UInt, big: UInt)?
    /// Every window given an icon, so a new pick reaches them all.
    nonisolated(unsafe) private static var windows: Set<UInt> = []

    private static let preferencesKey = #"Software\Cra"#

    /// Cra.exe's small icon, for the notification area.
    static var small: HANDLE? { exeIcons.small }

    /// The picked icon's id (`AppIconChoice.presets`).
    static var selectedID: String {
        AppIconChoice.resolved(stored: WinRegistry.string(preferencesKey, AppIconChoice.storageKey), hasCustom: false)
    }

    static func apply(to hwnd: UInt) {
        guard let window = HWND(bitPattern: hwnd) else { return }
        windows = windows.filter { IsWindow(HWND(bitPattern: $0)) == true }
        windows.insert(hwnd)
        let icons = current()
        for (kind, icon) in [(WPARAM(0), icons.small), (WPARAM(1), icons.big)] {
            guard let icon else { continue }
            _ = SendMessageW(window, setIcon, kind, LPARAM(Int(bitPattern: icon)))
        }
    }

    /// Settings ▸ General ▸ App icon: keeps the pick and shows it on every open window.
    static func select(_ id: String) {
        guard AppIconChoice.presets.contains(where: { $0.id == id }) else { return }
        _ = WinRegistry.setString(preferencesKey, AppIconChoice.storageKey, id)
        let old = picked
        picked = nil
        for hwnd in windows { apply(to: hwnd) }
        if let old {
            cra_icon_destroy(UInt(old.small))
            cra_icon_destroy(UInt(old.big))
        }
    }

    /// A preset's picture beside Cra.exe (`AppIconChoice.bundledFile`), for the picker.
    static func pictureFile(_ id: String) -> URL? {
        guard let file = AppIconChoice.bundledFile(id) else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(file)
    }

    private static func current() -> (small: HANDLE?, big: HANDLE?) {
        let id = selectedID
        guard id != AppIconChoice.defaultID else { return exeIcons }
        if let picked, picked.id == id { return (handle(picked.small), handle(picked.big)) }
        guard let file = pictureFile(id), let data = try? Data(contentsOf: file),
              let small = icon(data, GetSystemMetrics(smallSize)), let big = icon(data, GetSystemMetrics(bigSize)) else {
            return exeIcons
        }
        picked = (id, small, big)
        return (handle(small), handle(big))
    }

    private static func icon(_ png: Data, _ side: Int32) -> UInt? {
        guard side > 0, let pixels = Pixels.decode(png, side: Int(side)) else { return nil }
        let made = pixels.bgra.withUnsafeBufferPointer { cra_icon_from_pixels($0.baseAddress, Int32(pixels.width), Int32(pixels.height)) }
        return made == 0 ? nil : UInt(made)
    }

    private static func handle(_ value: UInt) -> HANDLE? { HANDLE(bitPattern: value) }

    /// Icon 1 at the system size `metric` names; LR_SHARED (0x8000) so Windows owns it.
    private static func load(_ metric: Int32) -> HANDLE? {
        let size = GetSystemMetrics(metric)
        return LoadImageW(GetModuleHandleW(nil), UnsafePointer<WCHAR>(bitPattern: 1), imageIcon, size, size, 0x8000)
    }
}
