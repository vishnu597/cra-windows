import WinSDK

/// Cra's icon (Resources/Cra.rc, icon 1 in Cra.exe) on a window's title bar, taskbar button and
/// Alt+Tab entry. An AppWindow has none of its own, so Windows showed its generic window icon.
enum WindowIcon {
    // WM_SETICON, ICON_SMALL / ICON_BIG, IMAGE_ICON, SM_CXICON, SM_CXSMICON: macros Swift can't see.
    private static let setIcon: UINT = 0x0080, imageIcon: UINT = 1
    private static let bigSize: Int32 = 11, smallSize: Int32 = 49

    /// Loaded once: shared icons stay valid for the life of the process.
    nonisolated(unsafe) private static let icons: (small: HANDLE?, big: HANDLE?) = (load(smallSize), load(bigSize))

    static func apply(to hwnd: UInt) {
        guard let window = HWND(bitPattern: hwnd) else { return }
        for (kind, icon) in [(WPARAM(0), icons.small), (WPARAM(1), icons.big)] {
            guard let icon else { continue }
            _ = SendMessageW(window, setIcon, kind, LPARAM(Int(bitPattern: icon)))
        }
    }

    /// Icon 1 at the system size `metric` names; LR_SHARED (0x8000) so Windows owns it.
    private static func load(_ metric: Int32) -> HANDLE? {
        let size = GetSystemMetrics(metric)
        return LoadImageW(GetModuleHandleW(nil), UnsafePointer<WCHAR>(bitPattern: 1), imageIcon, size, size, 0x8000)
    }
}
