import CraCore
import Foundation
import Testing

/// What the Windows app hands its page hook (cra_cef_set_page_top_drag): Windows' pages have no
/// toolbar over them, so the band is Arc's whole reach, and the setting is on unless turned off.
struct WindowsPageTopDragTests {
    @Test func windowsBandIsTheWholeReach() {
        #expect(PageTopDrag.band(barHeight: 0) == 60)
        #expect(PageTopDrag.trailingInset == 14)
        // The rule the hook mirrors: a plain single press, inside the band, clear of the scrollbar.
        #expect(PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 59, clickCount: 1, modifiers: false, distanceFromRight: 15))
        #expect(!PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 60, clickCount: 1, modifiers: false))
        #expect(!PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 10, clickCount: 2, modifiers: false))
        #expect(!PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 10, clickCount: 1, modifiers: true))
        #expect(!PageTopDrag.holds(enabled: true, barHeight: 0, depthIntoPage: 10, clickCount: 1, modifiers: false, distanceFromRight: 14))
    }

    @Test func settingIsOnUnlessTurnedOff() throws {
        #expect(AppSettings().pageTopWindowDrag)
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(empty.pageTopWindowDrag)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"pageTopWindowDrag":false}"#.utf8))
        #expect(!off.pageTopWindowDrag)
    }
}
