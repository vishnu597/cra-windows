import Foundation

/// The pages extensions open right after Cra starts. An extension Cra loads from its own folder
/// (--load-extension, `ExtensionFolders`) counts as freshly installed on every launch, so its
/// onInstalled welcome page ("AdBlock is now installed!") came back as a new tab each time
/// (PR #42's PC test on Windows; the Mac's AppDelegate drops them the same way). Within
/// `window` of the launch such a page is dropped, unless one of Cra's extensions is new since
/// the last launch; then each page opens once, and one already open isn't opened again.
public struct ExtensionStartUpPages: Equatable {
    /// How long after launch a page counts as a start-up page.
    public static let window: TimeInterval = 10
    /// The file that keeps the extensions seen at the last launch, in Cra's data folder.
    public static let fileName = "extensions-welcomed.json"

    public let launchedAt: Date
    /// One of `installed` wasn't there at the last launch.
    public let hasNewExtension: Bool

    /// `installed`: this launch's extensions (Windows: Cra's folders by name); `welcomed`: the last launch's.
    public init(launchedAt: Date, installed: [String], welcomed: Set<String>) {
        self.launchedAt = launchedAt
        hasNewExtension = !Set(installed).isSubset(of: welcomed)
    }

    /// Whether the page an extension opens at `now` is left unopened; `isOpen`: a tab shows it already.
    public func drops(at now: Date, isOpen: Bool) -> Bool {
        now.timeIntervalSince(launchedAt) < Self.window && (!hasNewExtension || isOpen)
    }

    /// Reads the last launch's extensions from `directory`, writes this launch's in their place
    /// and returns the decision for this launch.
    public static func launch(at date: Date, installed: [String], directory: URL) -> ExtensionStartUpPages {
        let file = directory.appendingPathComponent(fileName)
        let welcomed = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: file))) ?? [])
        try? JSONEncoder().encode(installed.sorted()).write(to: file, options: .atomic)
        return ExtensionStartUpPages(launchedAt: date, installed: installed, welcomed: welcomed)
    }
}
