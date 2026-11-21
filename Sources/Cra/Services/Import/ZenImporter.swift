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
        return ZenImport.plan(sidebar: sidebar, bookmarks: FirefoxImporter.bookmarks(profile: profile)) { spaces in
            // Favicons from favicons.sqlite.
            ImportFavicons.attach(to: &spaces, folder: "cra-zen-favicons") { FirefoxImporter.favicons(root: root, hosts: $0) }
        }
    }

    /// A favicon as PNG, at most 64 px on its long side. Firefox's widest icon is often an SVG,
    /// which can declare any size: tiffRepresentation drew it at that size and ran a 0.1.43
    /// import out of memory.
    static func faviconPNG(_ img: NSImage, side: CGFloat = 64) -> Data? {
        guard img.size.width > 0, img.size.height > 0 else { return nil }
        let scale = min(1, side / max(img.size.width, img.size.height))
        let w = max(1, Int((img.size.width * scale).rounded())), h = max(1, Int((img.size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
