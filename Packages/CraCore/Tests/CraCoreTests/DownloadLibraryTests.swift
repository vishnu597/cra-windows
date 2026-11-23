import CraCore
import Foundation
import Testing

/// PC test findings on Windows' downloads (22 Nov 2026).
@MainActor
struct DownloadLibraryTests {
    let t0 = Date(timeIntervalSince1970: 1_794_063_600)

    /// Library ▸ Downloads listed only finished files: a running one wasn't there.
    @Test func libraryListsARunningDownloadUnderToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let h = DownloadHistory(file: nil, fileExists: { _ in true })
        h.report(id: 7, name: "big.iso", path: "C:\\Users\\me\\Downloads\\big.iso", received: 10, total: 100, percent: 10,
                 complete: false, cancelled: false, failed: false, now: t0)
        let sections = LibraryList.downloads(h.library(query: ""), now: t0, calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(sections.map(\.title) == ["Today"])
        let row = try #require(sections.first?.items.first)
        #expect(row.id == "live-7")
        #expect(row.name == "big.iso")
    }

    /// A cancelled download's report comes with no name and no path: its row kept showing nothing.
    @Test func aCancelledRowKeepsItsName() throws {
        let h = DownloadHistory(file: nil, fileExists: { _ in true })
        h.report(id: 3, name: "setup.exe", path: "C:\\d\\setup.exe", received: 5, total: 100, percent: 5,
                 complete: false, cancelled: false, failed: false, now: t0)
        h.report(id: 3, name: "", path: "", received: 5, total: 100, percent: 5,
                 complete: false, cancelled: true, failed: false, now: t0.addingTimeInterval(1))
        let row = try #require(h.live.first)
        #expect(row.name == "setup.exe")
        #expect(row.path == "C:\\d\\setup.exe")
        #expect(row.cancelled)
    }
}
