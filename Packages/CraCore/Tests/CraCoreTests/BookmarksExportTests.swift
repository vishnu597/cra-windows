import CraCore
import Foundation
import Testing

/// Export spaces and pinned tabs, which the Mac and Windows both write.
@MainActor
struct BookmarksExportTests {
    @Test func spacesFavoritesPinnedTabsAndFoldersNestWithoutToday() {
        let f = StoreFixture()
        let space = f.space
        let favorite = f.store.createTab(url: "https://mail.example/", title: "Mail")
        f.store.addToFavorites(favorite.id)
        _ = f.store.createTab(url: "https://docs.example/?a=1&b=<2>", title: "Docs \"A\"", pinned: true)
        let folder = f.store.createFolder(named: "Reading", in: space.pinnedContainerID)
        _ = f.store.createTab(url: "https://read.example/", title: "Read", parent: folder.id)
        _ = f.store.createTab(url: "https://today.example/", title: "Today only")
        _ = f.store.createTab(url: "", title: "Empty", pinned: true)

        let html = BookmarksExport.html(f.store, exportedOn: "16 November 2026")
        #expect(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<!-- Spaces and pinned tabs exported from Cra on 16 November 2026. -->"))
        #expect(html.contains("<DT><H3 ADD_DATE=\"\(Int(space.createdAt.timeIntervalSince1970))\">\(space.labeled)</H3>"))
        #expect(html.contains(">Favorites</H3>"))
        #expect(html.contains("            <DT><A HREF=\"https://mail.example/\""))  // inside Favorites, depth 3
        #expect(html.contains("HREF=\"https://docs.example/?a=1&amp;b=&lt;2&gt;\""))
        #expect(html.contains(">Docs &quot;A&quot;</A>"))
        #expect(html.contains(">Reading</H3>"))
        #expect(html.contains("            <DT><A HREF=\"https://read.example/\""))  // inside the folder
        #expect(!html.contains("today.example"))
        #expect(!html.contains("Empty"))
        #expect(html.hasSuffix("</DL><p>\n"))
    }

    @Test func fileNameIsTheDayInTheZone() throws {
        let date = Date(timeIntervalSince1970: 1_794_787_200)  // 2026-11-16 00:00 UTC
        #expect(BookmarksExport.fileName(at: date, timeZone: try #require(TimeZone(identifier: "UTC"))) == "Cra Spaces 2026-11-16.html")
        #expect(BookmarksExport.fileName(at: date, timeZone: try #require(TimeZone(identifier: "America/New_York"))) == "Cra Spaces 2026-11-15.html")
    }
}
