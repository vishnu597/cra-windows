import CraCore
import Foundation
import Testing

struct SidebarClickTests {
    private let a = UUID(), b = UUID()

    private func press(_ clicks: inout SidebarClick, _ id: UUID, at time: Double, x: Double = 100,
                       y: Double = 100, modifiers: Int = 0) -> Int {
        clicks.press(.item(id), at: time, x: x, y: y, modifiers: modifiers,
                     interval: 0.5, distanceX: 2, distanceY: 2)
    }

    @Test func theSecondPressSurvivesARebuiltRow() {
        var clicks = SidebarClick()
        #expect(press(&clicks, a, at: 10) == 1)
        // The old Button has gone; the replacement still names the same model item.
        #expect(press(&clicks, a, at: 10.2, x: 101) == 2)
        #expect(press(&clicks, a, at: 10.3) == 1, "a third press starts a new pair")
    }

    @Test func anotherRowOrDistantPressStartsAnotherPair() {
        var clicks = SidebarClick()
        #expect(press(&clicks, a, at: 10) == 1)
        #expect(press(&clicks, b, at: 10.1) == 1)
        #expect(press(&clicks, b, at: 10.2, x: 103) == 1)
        #expect(press(&clicks, b, at: 10.3, x: 103, y: 103) == 1)
        #expect(press(&clicks, b, at: 11) == 1)
    }

    @Test func modifiersAndSpaceHeadersDoNotBorrowAnItemsPress() {
        var clicks = SidebarClick()
        #expect(press(&clicks, a, at: 10, modifiers: 1) == 1)
        #expect(press(&clicks, a, at: 10.1) == 1)
        #expect(clicks.press(.space(a), at: 10.2, x: 100, y: 100, interval: 0.5,
                             distanceX: 2, distanceY: 2) == 1)
    }

    @Test func aDragOrKeyboardActionCancelsThePendingPair() {
        var clicks = SidebarClick()
        #expect(press(&clicks, a, at: 10) == 1)
        clicks.cancel()
        #expect(press(&clicks, a, at: 10.1) == 1)
        clicks.cancel()
        #expect(press(&clicks, a, at: 10.2) == 1)
    }

    @Test func aPinnedIconsDoublePressStillGoesHomeOnlyOnce() {
        var clicks = SidebarClick()
        let first = PinnedIconClick.action(clickCount: press(&clicks, a, at: 10), onIcon: true,
                                           navigatedAway: true, command: false, previousWentBack: false)
        #expect(first == .backToPinnedPage)
        let second = PinnedIconClick.action(clickCount: press(&clicks, a, at: 10.1), onIcon: false,
                                            navigatedAway: false, command: false, previousWentBack: first.wentBack)
        #expect(second == .nothing)
    }
}
