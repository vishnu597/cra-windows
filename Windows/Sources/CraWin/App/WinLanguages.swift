import CraCore
import Foundation
import WinSDK

/// Windows' display languages, for Chromium's own locale (`ChromiumLocale.pick(localePaks:)`).
enum WinLanguages {
    /// MUI_LANGUAGE_NAME: answer "de-DE", not LCIDs.
    private static let muiLanguageName: DWORD = 0x8

    /// The user's display languages, most wanted first ("de-DE", "en-US").
    static var preferred: [String] {
        var count: ULONG = 0
        var size: ULONG = 0
        _ = GetUserPreferredUILanguages(muiLanguageName, &count, nil, &size)
        guard size > 0 else { return [] }
        var buffer = [WCHAR](repeating: 0, count: Int(size))
        _ = GetUserPreferredUILanguages(muiLanguageName, &count, &buffer, &size)
        // A double-null-terminated list.
        return buffer.split(separator: 0).map { String(decoding: $0, as: UTF16.self) }
    }

    /// Chromium's locale for this user, from the `locales` folder next to Cra.exe; nil leaves
    /// CEF's en-US.
    static func chromiumLocale(exeFolder: URL) -> String? {
        let folder = exeFolder.appendingPathComponent("locales").path
        let paks = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return ChromiumLocale.pick(localePaks: paks, preferredLanguages: preferred)
    }
}
