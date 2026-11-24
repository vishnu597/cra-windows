import CraCEFWin
import CraCore
import Foundation
import UWP
import WinAppSDK
import WinSDK
import WindowsFoundation

/// A Library row or Media tile that a click opens and a drag hands out as the file (the Mac's
/// MediaTile and LibraryItemCell): into Explorer, a mail, another app or a page's upload field.
/// Its button acts on press (UI.button), so the press is followed from Win32, as the sidebar's
/// drags are (SidebarDrag): a timer samples the mouse until it is let go (the click) or moves
/// past Windows' drag distance (CraCore `PressOrDrag`), and then the shell's drag carries the file.
@MainActor
enum FileDragOut {
    // Win32 numbers WinSDK leaves as macros.
    private static let leftButton: Int32 = 0x01, rightButton: Int32 = 0x02
    private static let swapButtons: Int32 = 23, dragWidth: Int32 = 68, dragHeight: Int32 = 69  // SM_SWAPBUTTON, SM_CXDRAG, SM_CYDRAG

    private static var timer: WinAppSDK.DispatcherQueueTimer?
    private static var start = POINT()
    private static var path: String?
    private static var click: (() -> Void)?

    private static func buttonDown() -> Bool {
        GetAsyncKeyState(GetSystemMetrics(swapButtons) != 0 ? rightButton : leftButton) < 0
    }

    /// The row's button was pressed: `click` runs once it is let go in place (at once for a key),
    /// or the file at `path` goes out as a drag (nil: nothing to drag, the press is a click).
    static func pressed(path: String?, click: @escaping @MainActor () -> Void) {
        stop()
        var p = POINT()
        guard let path, buttonDown(), GetCursorPos(&p),
              let queue = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil, let t = try? queue.createTimer() else {
            return click()
        }
        start = p
        Self.path = path
        Self.click = click
        t.interval = TimeSpan(duration: 16 * 10_000)
        t.isRepeating = true
        t.tick.addHandler { _, _ in MainActor.assumeIsolated { tick() } }
        try? t.start()
        timer = t
    }

    private static func tick() {
        var p = POINT()
        guard GetCursorPos(&p) else { return }
        let decision = PressOrDrag.classify(dx: Double(p.x - start.x), dy: Double(p.y - start.y), buttonDown: buttonDown(),
                                            slopX: Double(GetSystemMetrics(dragWidth)) / 2, slopY: Double(GetSystemMetrics(dragHeight)) / 2)
        switch decision {
        case .waiting: return
        case .click:
            let action = click
            stop()
            action?()
        case .drag:
            let file = path
            stop()
            if let file { _ = cra_drag_file_out(file) }
        }
    }

    private static func stop() {
        try? timer?.stop()
        timer = nil
        path = nil
        click = nil
    }
}
