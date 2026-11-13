import Foundation

/// Where the Windows app keeps its data: the Mac's AppPaths, under %LOCALAPPDATA%\Cra. The
/// files in it (sidebar.json, settings.json, …) are the Mac app's, read and written by the
/// same CraCore code.
enum WinPaths {
    static let supportDir: URL = {
        // CRA_DATA_DIR runs a second, independent Cra, as on the Mac.
        let env = ProcessInfo.processInfo.environment
        let base = env["CRA_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: env["LOCALAPPDATA"] ?? NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("Cra", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    /// Chromium's profiles: Default and "Profile <id>", as on the Mac.
    static var chromiumCache: URL { supportDir.appendingPathComponent("Chromium", isDirectory: true) }
    static var log: URL { supportDir.appendingPathComponent("chromium.log") }
    /// Cra's own unpacked extensions, one folder each, loaded at start-up (ExtensionFolders).
    static var extensions: URL { supportDir.appendingPathComponent("Extensions", isDirectory: true) }

    /// `url` as Windows writes it (C:\Users\…), for a command line.
    static func native(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    }
}
