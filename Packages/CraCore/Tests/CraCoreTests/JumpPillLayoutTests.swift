import CraCore
import Foundation
import Testing

struct JumpPillLayoutTests {
    /// The pill shows only while the whole row is past an edge: a row partly in sight is
    /// still reachable by eye.
    @Test func showsOnlyWhileTheRowIsWhollyPastAnEdge() {
        let edge = { (top: CGFloat, bottom: CGFloat) in
            JumpPillLayout.edge(rowTop: top, rowBottom: bottom, visibleTop: 100, visibleBottom: 400)
        }
        #expect(edge(40, 70) == .top)
        #expect(edge(70, 100) == .top)
        #expect(edge(80, 110) == nil)
        #expect(edge(200, 230) == nil)
        #expect(edge(390, 420) == nil)
        #expect(edge(400, 430) == .bottom)
        #expect(edge(600, 630) == .bottom)
    }

    @Test func hidesBeforeTheListHasAHeight() {
        #expect(JumpPillLayout.edge(rowTop: 40, rowBottom: 70, visibleTop: 0, visibleBottom: 0) == nil)
    }

    /// Dia's capsule is 51 pt wide with one favicon; a split's further favicons add 11 pt each,
    /// up to three.
    @Test func widthFollowsTheFavicons() {
        #expect(JumpPillLayout.width(icons: 1) == 51)
        #expect(JumpPillLayout.width(icons: 0) == 51)
        #expect(JumpPillLayout.width(icons: 2) == 62)
        #expect(JumpPillLayout.width(icons: 3) == 73)
        #expect(JumpPillLayout.width(icons: 5) == 73)
    }

    /// A click puts the row's middle at the list's middle, but never scrolls past either end.
    @Test func scrollCentresTheRowWithinTheContent() {
        let target = { (top: CGFloat) in
            JumpPillLayout.scrollTarget(rowTop: top, rowBottom: top + 30, visibleHeight: 300, contentHeight: 1000)
        }
        #expect(target(500) == 365)
        #expect(target(20) == 0)
        #expect(target(960) == 700)
        #expect(JumpPillLayout.scrollTarget(rowTop: 100, rowBottom: 130, visibleHeight: 300, contentHeight: 200) == 0)
    }
}
