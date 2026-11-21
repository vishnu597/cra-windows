import CraCore
import Foundation
import WinSDK

/// Settings ▸ Advanced ▸ "Keep Cra in the notification area" (the Mac's MenuBarItem, GitHub #231):
/// Cra's icon by the clock while the setting is on. A click brings the browser window back; the
/// right-click menu lists MenuBarMode.menuCommands, with each command's shortcut, then Quit Cra.
/// Its messages come to a message-only window of its own.
@MainActor
final class NotificationAreaIcon {
    private let perform: (String) -> Void
    private let quit: () -> Void
    private var window: HWND?
    private var added = false
    /// The open menu's command ids, by item id less one; Quit Cra is the item after them.
    private var menuIDs: [String] = []

    /// `perform` gets a command id (newWindow, settings, …) or "show" for a click on the icon;
    /// `quit` is the menu's Quit Cra.
    init(perform: @escaping (String) -> Void, quit: @escaping () -> Void) {
        self.perform = perform
        self.quit = quit
        window = Self.makeWindow()
        guard let window else {
            print("Cra: the notification-area icon has no window (\(GetLastError()))")
            return
        }
        Self.icons[UInt(bitPattern: window)] = self
        add()
    }

    func remove() {
        guard let window else { return }
        var data = Self.data(window)
        if added { _ = Shell_NotifyIconW(DWORD(Self.nimDelete), &data) }
        added = false
        Self.icons[UInt(bitPattern: window)] = nil
        DestroyWindow(window)
        self.window = nil
    }

    private func add() {
        guard let window else { return }
        var data = Self.data(window)
        data.uFlags = UINT(Self.nifMessage | Self.nifIcon | Self.nifTip)
        data.uCallbackMessage = Self.callback
        data.hIcon = WindowIcon.small.map { unsafeBitCast($0, to: HICON.self) }
        let tip = Array("Cra".utf16) + [0]
        withUnsafeMutableBytes(of: &data.szTip) { field in tip.withUnsafeBytes { field.copyMemory(from: $0) } }
        added = Shell_NotifyIconW(DWORD(Self.nimAdd), &data)
        print("Cra: notification-area icon \(added ? "shown" : "failed")")
    }

    private func handle(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) {
        if message == Self.wmCommand {
            // A menu item, posted once the menu has closed: its id in the low word.
            let picked = Int(wParam & 0xFFFF)
            if picked == menuIDs.count + 1 { return quit() }
            if picked > 0, picked <= menuIDs.count { perform(menuIDs[picked - 1]) }
            return
        }
        if message == Self.taskbarCreated {
            // Explorer restarted: its notification area starts empty.
            added = false
            return add()
        }
        guard message == Self.callback else { return }
        switch UINT(truncatingIfNeeded: lParam) {
        case Self.wmLeftUp: perform("show")
        case Self.wmRightUp: showMenu()
        default: break
        }
    }

    private func showMenu() {
        guard let window, let menu = CreatePopupMenu() else { return }
        defer { DestroyMenu(menu) }
        var ids: [String] = []
        defer { menuIDs = ids }
        for (n, group) in MenuBarMode.menuCommands.enumerated() {
            if n > 0 { AppendMenuW(menu, UINT(Self.mfSeparator), 0, nil) }
            for id in group {
                guard let action = WinKeyBindings.shared.action(id) else { continue }
                ids.append(id)
                let keys = action.shortcuts.first.map { "\t" + $0.windowsDisplay } ?? ""
                _ = (action.name + keys).withCString(encodedAs: UTF16.self) { AppendMenuW(menu, 0, UINT_PTR(ids.count), $0) }
            }
        }
        AppendMenuW(menu, UINT(Self.mfSeparator), 0, nil)
        let quitID = ids.count + 1
        _ = "Quit Cra".withCString(encodedAs: UTF16.self) { AppendMenuW(menu, 0, UINT_PTR(quitID), $0) }
        var point = POINT()
        GetCursorPos(&point)
        // The menu closes when the user clicks elsewhere only while its window is in front.
        SetForegroundWindow(window)
        // The pick comes as WM_COMMAND (TPM_RETURNCMD's answer is a BOOL, which Swift reads as true or false).
        _ = TrackPopupMenu(menu, UINT(Self.tpmRightButton), point.x, point.y, 0, window, nil)
        PostMessageW(window, 0, 0, 0)  // WM_NULL, as the documentation for TrackPopupMenu asks
    }

    // MARK: Win32

    nonisolated(unsafe) private static var icons: [UInt: NotificationAreaIcon] = [:]
    private static let className = Array("CraNotificationArea".utf16) + [0]
    private static let callback: UINT = 0x8001  // WM_APP + 1
    nonisolated(unsafe) private static let taskbarCreated: UINT = "TaskbarCreated".withCString(encodedAs: UTF16.self) { RegisterWindowMessageW($0) }
    // NIM_ADD, NIM_DELETE, NIF_MESSAGE, NIF_ICON, NIF_TIP, MF_SEPARATOR, TPM_RIGHTBUTTON,
    // WM_LBUTTONUP, WM_RBUTTONUP, WM_COMMAND, WS_POPUP: macros Swift can't see.
    private static let nimAdd = 0, nimDelete = 2
    private static let nifMessage = 1, nifIcon = 2, nifTip = 4
    private static let mfSeparator = 0x800
    private static let tpmRightButton = 0x2
    private static let wmLeftUp: UINT = 0x0202, wmRightUp: UINT = 0x0205, wmCommand: UINT = 0x0111
    private static let popup: DWORD = 0x8000_0000

    private static func data(_ window: HWND) -> NOTIFYICONDATAW {
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = window
        data.uID = 1
        return data
    }

    private static func makeWindow() -> HWND? {
        let instance = GetModuleHandleW(nil)
        let proc: WNDPROC = { hwnd, message, wParam, lParam in
            if let hwnd, let icon = NotificationAreaIcon.icons[UInt(bitPattern: hwnd)] {
                MainActor.assumeIsolated { icon.handle(message, wParam, lParam) }
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
        return className.withUnsafeBufferPointer { name -> HWND? in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.lpfnWndProc = proc
            wc.hInstance = instance
            wc.lpszClassName = name.baseAddress
            _ = RegisterClassExW(&wc)  // Fails harmlessly when already registered.
            // A popup that is never shown, not a message-only window: only top-level windows hear
            // Explorer's TaskbarCreated.
            return CreateWindowExW(0, name.baseAddress, nil, popup, 0, 0, 0, 0, nil, nil, instance, nil)
        }
    }
}
