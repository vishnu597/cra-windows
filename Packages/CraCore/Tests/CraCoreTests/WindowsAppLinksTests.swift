import CraCore
import Testing

/// Windows' new-tab and popup requests ask AppLinks first (#207): another app's link opens no tab.
struct WindowsAppLinksTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/207"))
    func appLinksThatAskForATabOpenNone() {
        for url in ["zoommtg://zoom.us/join?confno=1", "slack://open", "msteams:/l/meetup-join/x", "spotify:track:1"] {
            #expect(AppLinks.kind(of: url) == .asksFirst, "\(url)")
        }
        #expect(AppLinks.kind(of: "mailto:a@b.test") == .opens)
        #expect(AppLinks.kind(of: "cra://open?space=1") == .refused, "never handed to the installed Cra")
        #expect(AppLinks.kind(of: "https://zoom.us/j/1") == .page)
        #expect(AppLinks.kind(of: "about:blank") == .page, "a popup host's first page is still a tab")
    }
}
