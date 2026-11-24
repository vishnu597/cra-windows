import CraCore
import Foundation
import Testing

@MainActor
struct FolderPreviewListTests {
    /// Every tab under the folder, nested folders and splits included, the one used last first;
    /// an unread background tab carries its badge.
    @Test func listsEveryTabUnderTheFolderMostRecentlyUsedFirst() {
        let f = StoreFixture()
        let folder = f.store.createFolder(named: "Work", in: f.space.pinnedContainerID)
        let inner = f.store.createFolder(named: "Inner", in: folder.id)
        let a = f.store.createTab(url: "https://a.test/", title: "A", select: false, parent: folder.id)
        f.clock.advance(by: 10)
        let b = f.store.createTab(url: "https://b.test/", title: "B", select: false, parent: inner.id)
        f.clock.advance(by: 10)
        let c = f.store.createTab(url: "https://c.test/", title: "C", select: false, parent: folder.id)
        let outside = f.store.createTab(url: "https://out.test/", select: false)
        f.clock.advance(by: 10)
        f.store.selectTab(a.id)
        let entries = f.store.folderPreviewEntries(folder.id)
        #expect(entries.map(\.id) == [a.id, c.id, b.id])
        #expect(!entries.map(\.id).contains(outside.id))
        let nested = entries.first(where: { $0.id == b.id })
        #expect(nested?.badged == true && nested?.title == "B" && nested?.url == "https://b.test/")
    }

    /// Each word typed has to be in the title or the address, in any case.
    @Test func theSearchKeepsRowsHoldingEveryWord() {
        func entry(_ title: String, _ url: String) -> FolderPreviewList.Entry {
            FolderPreviewList.Entry(id: UUID(), title: title, url: url, iconKey: nil, lastVisit: Date(), badged: false)
        }
        let mail = entry("Inbox – Mail", "https://mail.example.com/")
        let docs = entry("Quarterly plan", "https://docs.example.com/plan")
        let all = [mail, docs]
        #expect(FolderPreviewList.filter(all, query: "") == all)
        #expect(FolderPreviewList.filter(all, query: "  ") == all)
        #expect(FolderPreviewList.filter(all, query: "INBOX") == [mail])
        #expect(FolderPreviewList.filter(all, query: "docs plan") == [docs])
        #expect(FolderPreviewList.filter(all, query: "example") == all)
        #expect(FolderPreviewList.filter(all, query: "mail plan").isEmpty)
    }

    /// One row is 98 pt; six and more stop at 320 and scroll.
    @Test func theCardGrowsWithItsRowsUpTo320() {
        #expect(FolderPreviewList.height(rows: 0) == 98)
        #expect(FolderPreviewList.height(rows: 1) == 98)
        #expect(FolderPreviewList.height(rows: 3) == 188)
        #expect(FolderPreviewList.height(rows: 5) == 278)
        #expect(FolderPreviewList.height(rows: 6) == 320)
        #expect(FolderPreviewList.height(rows: 40) == 320)
    }

    /// Centred on the folder's row, but never closer than 18 pt to the window's top or bottom.
    @Test func theCardCentresOnTheRowInsideTheWindow() {
        #expect(FolderPreviewList.top(rowMidY: 400, height: 200, windowTop: 0, windowBottom: 900) == 300)
        #expect(FolderPreviewList.top(rowMidY: 50, height: 200, windowTop: 0, windowBottom: 900) == 18)
        #expect(FolderPreviewList.top(rowMidY: 880, height: 200, windowTop: 0, windowBottom: 900) == 682)
    }

    @Test func agesReadAsArcWordsThem() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        func age(_ seconds: TimeInterval) -> String { FolderPreviewList.age(of: now.addingTimeInterval(-seconds), now: now) }
        #expect(age(5) == "Just now")
        #expect(age(-30) == "Just now")
        #expect(age(60) == "1 minute ago")
        #expect(age(150) == "2 minutes ago")
        #expect(age(15 * 3600) == "15 hours ago")
        #expect(age(86400) == "1 day ago")
        #expect(age(8 * 86400) == "1 week ago")
        #expect(age(45 * 86400) == "1 month ago")
        #expect(age(800 * 86400) == "2 years ago")
    }
}
