import Foundation

extension SidebarStore {
    /// The store on Cra's data folder (CRA_DATA_DIR for a test instance), with Arc's toolbar
    /// setting for the settings migration and profile folders removed at the next launch.
    convenience init(clock: Scheduler? = nil) {
        self.init(directory: AppPaths.supportDir, chromiumCache: AppPaths.chromiumCache,
                  clock: clock ?? LiveScheduler.shared, arcShowsToolbar: { ArcImporter.showsToolbar },
                  onProfileDeleted: ProfileCleanup.schedule)
    }

    /// History saved before #609 has no profiles: once, off the main thread, at launch, the
    /// profiles' own Chromium histories say whose each page was (#729). Nothing changes if a
    /// profile's History can't be read.
    func attributeHistoryProfiles(chromium root: URL = AppPaths.chromiumCache, done: (@MainActor () -> Void)? = nil) {
        guard let folders = historyProfileFolders else { done?(); return }
        DispatchQueue.global(qos: .utility).async {
            let urls = Self.chromiumHistoryURLs(root: root, folders: folders)
            DispatchQueue.main.async { [weak self] in
                if let self, let urls {
                    let changed = self.adoptHistoryProfiles(chromiumURLs: urls)
                    if changed > 0 { CraLog.note("history: \(changed) entries from before profiles took theirs from Chromium") }
                }
                done?()
            }
        }
    }

    /// The addresses each profile's Chromium History has, by CommandBarProfileScope.key; a profile
    /// that never loaded a page has none. nil when a History is there but can't be read.
    nonisolated static func chromiumHistoryURLs(root: URL, folders: [(key: String, folder: String)]) -> [String: Set<String>]? {
        var out: [String: Set<String>] = [:]
        for (key, folder) in folders {
            let file = root.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("History")
            guard FileManager.default.fileExists(atPath: file.path) else { out[key] = []; continue }
            guard let db = SQLiteSnapshot(copying: file), db.columns(of: "urls").contains("url") else { return nil }
            out[key] = Set(db.rows("SELECT url FROM urls").compactMap { $0["url"] as? String })
        }
        return out
    }
}
