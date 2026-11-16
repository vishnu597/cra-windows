import Foundation

/// Settings ▸ Advanced ▸ Export spaces and pinned tabs: every space's favorites, pinned tabs and
/// folders as a Netscape bookmark file, the format Chrome, Safari, Firefox and Cra's Safari import
/// all read, and a plain nested list when opened in a browser. A space is a folder, its favorites
/// a "Favorites" folder inside it; split views give their panes to the folder they are in. Today
/// tabs are left out, as Arc archives them. The Mac and Windows both write it; the save dialog is
/// each platform's.
@MainActor
public enum BookmarksExport {
    /// The file. `exportedOn` names the moment in the header comment, as the platform writes dates.
    public static func html(_ store: SidebarStore, exportedOn: String) -> String {
        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- Spaces and pinned tabs exported from Cra on \(exportedOn). -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Cra Spaces</TITLE>
        <H1>Cra Spaces</H1>
        <DL><p>

        """
        func line(_ depth: Int, _ s: String) { out += String(repeating: "    ", count: depth) + s + "\n" }
        func folder(_ name: String, created: Date, depth: Int, _ body: () -> Void) {
            line(depth, "<DT><H3 ADD_DATE=\"\(stamp(created))\">\(escape(name))</H3>")
            line(depth, "<DL><p>")
            body()
            line(depth, "</DL><p>")
        }
        func items(under id: UUID, depth: Int) {
            for item in store.children(of: id) {
                if let tab = item.tab {
                    guard !item.isEmptyTab else { continue }
                    let url = tab.savedURL.isEmpty ? tab.url : tab.savedURL
                    line(depth, "<DT><A HREF=\"\(escape(url))\" ADD_DATE=\"\(stamp(item.createdAt))\">\(escape(item.displayTitle))</A>")
                } else if item.isSplit {
                    items(under: item.id, depth: depth)
                } else if item.isFolder {
                    folder(item.displayTitle, created: item.createdAt, depth: depth) { items(under: item.id, depth: depth + 1) }
                }
            }
        }
        for space in store.orderedSpaces {
            folder(space.labeled, created: space.createdAt, depth: 1) {
                if !store.tabs(under: space.favoritesContainerID).isEmpty {
                    folder("Favorites", created: space.createdAt, depth: 2) { items(under: space.favoritesContainerID, depth: 3) }
                }
                items(under: space.pinnedContainerID, depth: 2)
            }
        }
        out += "</DL><p>\n"
        return out
    }

    /// The name the save dialog suggests: "Cra Spaces 2026-11-16.html", the day in `timeZone`.
    public nonisolated static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "Cra Spaces %04d-%02d-%02d.html", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    nonisolated static func stamp(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    nonisolated static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
