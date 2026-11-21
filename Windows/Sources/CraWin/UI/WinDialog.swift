import Foundation
import WinSDK

/// Windows' own message boxes over a window (the Mac's AppDialog).
enum WinDialog {
    /// OK / Cancel with a question icon; true for OK.
    static func confirm(owner: UInt, title: String, message: String) -> Bool {
        show(owner: owner, title: title, message: message, flags: 0x1 | 0x20) == 1  // MB_OKCANCEL | MB_ICONQUESTION, IDOK
    }

    /// A notice with OK only.
    static func notice(owner: UInt, title: String, message: String = "") {
        _ = show(owner: owner, title: title, message: message, flags: 0x40)  // MB_ICONINFORMATION
    }

    private static func show(owner: UInt, title: String, message: String, flags: UINT) -> Int32 {
        // The box's caption is the app; the question goes in its text, as Windows' own dialogs do.
        let text = message.isEmpty ? title : "\(title)\n\n\(message)"
        return text.withCString(encodedAs: UTF16.self) { text in
            "Cra".withCString(encodedAs: UTF16.self) { caption in
                MessageBoxW(HWND(bitPattern: owner), text, caption, flags)
            }
        }
    }
}
