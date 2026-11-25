import Foundation

/// Zen's favicons from its favicons.sqlite, attached to an import as the Mac's ImportFavicons does
/// (`ZenImporter`): each tab's host gets the largest icon the browser kept, written as a file
/// under a temporary folder, where `SidebarStore.apply` copies it into Cra's favicon cache. The
/// Mac decodes the bytes with NSImage and redraws them as a 64 px PNG; Windows' decoder (WIC)
/// reads Firefox's PNG bytes as they are but can't draw an SVG, so it asks for bitmaps only.
public enum FirefoxFavicons {
    /// The file beside places.sqlite.
    public static let fileName = "favicons.sqlite"

    /// The width Firefox stores an SVG icon with (UINT16_MAX).
    public static let svgWidth = 65535

    /// The query for `host`'s largest icon, on the site or its www. name. With `bitmapsOnly`
    /// SVG icons are left out.
    public static func query(host: String, bitmapsOnly: Bool) -> String {
        let h = host.replacingOccurrences(of: "'", with: "")
        let bitmaps = bitmapsOnly ? " AND i.width < \(svgWidth)" : ""
        return """
            SELECT i.data FROM moz_icons i JOIN moz_icons_to_pages ip ON ip.icon_id = i.id JOIN moz_pages_w_icons p ON p.id = ip.page_id
            WHERE (p.page_url LIKE 'https://\(h)/%' OR p.page_url LIKE 'https://www.\(h)/%')\(bitmaps) ORDER BY i.width DESC LIMIT 1
            """
    }

    /// The favicon cache's key for a page: its lowercased host.
    public static func host(_ url: String) -> String? {
        URL(string: url)?.host.flatMap { $0.isEmpty ? nil : $0.lowercased() }
    }

    /// Every tab's host in the spaces (favorites, pinned and Today, inside folders too), once each, sorted.
    public static func hosts(in spaces: [ImportedSpace]) -> [String] {
        func hosts(_ items: [ImportedItem]) -> [String] {
            items.flatMap { $0.isFolder ? hosts($0.children) : [$0.url.flatMap(host)].compactMap { $0 } }
        }
        return Set(spaces.flatMap { hosts($0.favorites) + hosts($0.pinned) + hosts($0.today) }).sorted()
    }

    /// Each host's icon (the `data` of `rows(query)`) written into `folder` as it came; the files by
    /// host. Hosts without an icon are left out, and the folder is made only when one has.
    public static func write(hosts: [String], into folder: URL, bitmapsOnly: Bool,
                             rows: (String) -> [[String: Any]]) -> [String: String] {
        var files: [String: String] = [:]
        var madeFolder = false
        for host in hosts {
            guard let data = rows(query(host: host, bitmapsOnly: bitmapsOnly)).first?["data"] as? Data, !data.isEmpty else { continue }
            if !madeFolder {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                madeFolder = true
            }
            let file = folder.appendingPathComponent("\(files.count).png")
            if (try? data.write(to: file, options: .atomic)) != nil { files[host] = file.path }
        }
        return files
    }

    /// Sets each tab's `faviconPath` to its host's file, keeping the one it had when there's none.
    public static func attach(_ files: [String: String], to spaces: inout [ImportedSpace]) {
        guard !files.isEmpty else { return }
        func withIcons(_ items: [ImportedItem]) -> [ImportedItem] {
            items.map {
                var it = $0
                it.children = withIcons(it.children)
                it.faviconPath = it.url.flatMap(host).flatMap { files[$0] } ?? it.faviconPath
                return it
            }
        }
        for i in spaces.indices {
            spaces[i].favorites = withIcons(spaces[i].favorites)
            spaces[i].pinned = withIcons(spaces[i].pinned)
            spaces[i].today = withIcons(spaces[i].today)
        }
    }
}
