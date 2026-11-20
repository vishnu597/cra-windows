import CraCore
import Foundation
import Testing

/// Windows' tab sleeping pass (BrowserWindow.sleepIdleTabs) marks each page from Settings ▸ Tabs ▸
/// Always Keep Sites Active (#458), and the sheet adds what is typed into it.
struct WindowsKeepActiveSitesTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/458"))
    func aTypedSiteKeepsItsPagesAwakeOnTheTimer() throws {
        var settings = AppSettings()
        _ = try #require(settings.addKeepActiveSite("https://mail.example.com/inbox"))
        #expect(settings.addKeepActiveSite("mail.example.com") == nil, "the same site isn't listed twice")
        #expect(settings.addKeepActiveSite("not an address") == nil)

        let urls = ["https://mail.example.com/u/0", "https://news.test/"]
        let pages = urls.map { TabSleepPolicy.Page(id: UUID(), hiddenAt: now.addingTimeInterval(-9 * 3600),
                                                   keptActive: settings.keepsActive(url: $0)) }
        #expect(pages.map(\.keptActive) == [true, false])
        #expect(TabSleepPolicy.timer(.fifteenMinutes).candidates(pages, visible: [], now: now) == [pages[1].id])
    }
}
