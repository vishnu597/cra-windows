import CraCore
import Foundation
import Testing

/// Back on Windows (BrowserWindow.goBack, LittleWindow's "goBack"): a tab a link or a popup opened
/// closes to the tab it came from once its page has nothing behind (#273), and a Little Window
/// with nothing behind closes (#495).
@MainActor
struct WindowsBackToReferrerTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func aPopupsTabClosesBackToTheTabItCameFrom() {
        let f = StoreFixture()
        let source = f.store.createTab(url: "https://mail.example", select: true)
        // BrowserWindow's popup host (target=_blank, window.open): the tab keeps its source.
        let popup = f.store.createTab(url: "https://docs.example", select: true, referrer: source.id)
        #expect(f.store.backStep(popup.id, canGoBack: true) == .history, "its own pages first")
        #expect(f.store.backStep(popup.id, canGoBack: false) == .close(returnTo: source.id))
        f.store.closeToReferrer(popup.id, referrer: source.id, window: nil)
        #expect(f.store.selectedTabID == source.id)
        #expect(!f.today().contains(popup.id), "the popup's tab is archived")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func aTabTypedInHasNoBackOnceItsPagesRunOut() {
        let f = StoreFixture()
        let typed = f.store.createTab(url: "https://news.example", select: true)
        #expect(f.store.backStep(typed.id, canGoBack: false) == .none, "the toolbar's Back is off")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/495"))
    func aLittleWindowWithNothingBehindCloses() {
        #expect(LittleWindowBack.step(pageCanGoBack: false, hasPage: true, peek: false) == .close)
        #expect(LittleWindowBack.step(pageCanGoBack: true, hasPage: true, peek: false) == .history)
        #expect(LittleWindowBack.step(pageCanGoBack: false, hasPage: true, peek: true) == .none, "a Peek keeps to its history")
        #expect(LittleWindowBack.step(pageCanGoBack: false, hasPage: false, peek: false) == .none)
    }
}
