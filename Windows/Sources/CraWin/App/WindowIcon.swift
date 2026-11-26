import CraCEFWin
import CraCore
import Foundation
import WinSDK

/// Cra's icon on a window's title bar, taskbar button and Alt+Tab entry. An AppWindow has none
/// of its own, so Windows showed its generic window icon. The icon is Cra.exe's (Resources/Cra.rc,
/// icon 1: Segments) or the one picked in Settings ▸ General (`AppIconChoice`, the Mac's
/// AppIconManager): one of resources/app-icons beside Cra.exe, made into icons at the system's
/// sizes and given to every window Cra has open. The pick is kept under HKCU\Software\Cra, as
/// the Mac keeps it in its defaults. "Your own" is any image the user picks, kept as it came in
/// Cra's data folder (`AppIconImage.fileName`) and made into icons by CraCore's `AppIconImage`, as
/// the Mac's AppIconManager makes its own. A taskbar pin and the Start menu keep Cra.exe's own icon.
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

    /// The picked icon's id (`AppIconChoice.presets`, or `customID` while the user's own is kept).
    static var selectedID: String {
        AppIconChoice.resolved(stored: WinRegistry.string(preferencesKey, AppIconChoice.storageKey), hasCustom: hasCustom)
    }

    /// The user's own image, as it was picked.
    static var customFile: URL { WinPaths.supportDir.appendingPathComponent(AppIconImage.fileName) }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customFile.path) }

    enum CustomError: Error { case unreadable }

    /// Choose Image…: keeps a copy of `file` and picks it. Throws when it isn't an image Windows can read.
    static func setCustom(from file: URL) throws {
        guard let data = try? Data(contentsOf: file), Pixels.decode(data) != nil else { throw CustomError.unreadable }
        try FileManager.default.createDirectory(at: WinPaths.supportDir, withIntermediateDirectories: true)
        try data.write(to: customFile, options: .atomic)
        // A new image under the same id: made again.
        if picked?.id == AppIconChoice.customID { forgetPicked() }
        select(AppIconChoice.customID)
    }

    /// Remove: the user's own goes, and Segments comes back if it was picked.
    static func removeCustom() {
        try? FileManager.default.removeItem(at: customFile)
        if picked?.id == AppIconChoice.customID || WinRegistry.string(preferencesKey, AppIconChoice.storageKey) == AppIconChoice.customID {
            select(AppIconChoice.defaultID)
        }
    }

    /// The user's own icon at `side` pixels, for the picker; nil without one.
    static func customPicture(side: Int) -> Pixels? {
        guard let data = try? Data(contentsOf: customFile), let source = Pixels.decode(data) else { return nil }
        return Pixels(width: side, height: side, bgra: AppIconImage.render(source.bgra, width: source.width, height: source.height, side: side))
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
        guard AppIconChoice.presets.contains(where: { $0.id == id }) || (id == AppIconChoice.customID && hasCustom) else { return }
        _ = WinRegistry.setString(preferencesKey, AppIconChoice.storageKey, id)
        forgetPicked()
    }

    /// Lets the made icons go and gives every window the pick again.
    private static func forgetPicked() {
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
        let smallSide = Int(GetSystemMetrics(smallSize)), bigSide = Int(GetSystemMetrics(bigSize))
        let made: (small: UInt?, big: UInt?)
        if id == AppIconChoice.customID {
            guard let data = try? Data(contentsOf: customFile), let source = Pixels.decode(data) else { return exeIcons }
            func own(_ side: Int) -> UInt? {
                guard side > 0 else { return nil }
                return icon(Pixels(width: side, height: side, bgra: AppIconImage.render(source.bgra, width: source.width, height: source.height, side: side)))
            }
            made = (own(smallSide), own(bigSide))
        } else {
            guard let file = pictureFile(id), let data = try? Data(contentsOf: file) else { return exeIcons }
            func preset(_ side: Int) -> UInt? { side > 0 ? Pixels.decode(data, side: side).flatMap(icon) : nil }
            made = (preset(smallSide), preset(bigSide))
        }
        guard let small = made.small, let big = made.big else {
            if let s = made.small { cra_icon_destroy(s) }
            if let b = made.big { cra_icon_destroy(b) }
            return exeIcons
        }
        picked = (id, small, big)
        return (handle(small), handle(big))
    }

    private static func icon(_ pixels: Pixels) -> UInt? {
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
