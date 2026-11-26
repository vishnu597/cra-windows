import AppKit

// Zen is Firefox with Arc's sidebar: spaces, Essentials, pinned tabs and folders.
// Since Zen 1.15 one file holds that sidebar for every window,
// <profile>/zen-sessions.jsonlz4 = {spaces, tabs, folders, groups, splitViewData}
// (src/zen/sessionstore/ZenSessionManager.sys.mjs, read against 1.23.4b). Older
// profiles keep spaces in places.sqlite (zen_workspaces) and the tabs, with the
// same zen* fields, in Firefox's session store.

enum ZenImporter {
    /// The sidebar and plan are CraCore's ZenImport (shared with Windows); favicons are the Mac's.
    static func plan(root: URL) throws -> ImportPlan {
        guard let profile = FirefoxImporter.defaultProfile(root: root) else { throw ImportError.notFound("Zen") }
        let sidebar = ZenImport.sidebar(profile: profile) {
            SQLiteSnapshot(copying: profile.appendingPathComponent("places.sqlite"))?.rows(ZenImport.workspacesQuery) ?? []
        }
        var skipped: [ImportSkip] = []
        let marks = FirefoxImporter.bookmarks(profile: profile, skip: { skipped.append($0) })
        var plan = ZenImport.plan(sidebar: sidebar, bookmarks: marks, bookmarksSkipped: skipped)
        // Favicons from favicons.sqlite.
        ImportFavicons.attach(to: &plan, folder: "cra-zen-favicons", from: ImportSource.Kind.zen.iconStores(dataDir: root))
        return plan
    }

    /// FaviconCache.png(_:side:), under the name the crash-zen-favicon-size and #673 tests lock.
    static func faviconPNG(_ img: NSImage, side: CGFloat = 64) -> Data? { FaviconCache.png(img, side: side) }
}
