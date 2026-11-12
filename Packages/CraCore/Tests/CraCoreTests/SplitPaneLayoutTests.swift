// CGFloat and CGRect come from Foundation off Apple platforms (Windows, Linux).
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import CraCore
import Testing

/// Arc's split panes (ARCUI.SplitViewControllerLayout): factors of the room left after the
/// 10 pt gaps, a 220 pt minimum, and dividers that snap to equal.
struct SplitPaneLayoutTests {
    private let a = UUID(), b = UUID(), c = UUID()

    private func layout(_ factors: [CGFloat], _ orientation: SplitOrientation = .horizontal,
                        size: CGSize = CGSize(width: 1010, height: 600), flipped: Bool = false) -> SplitPaneLayout {
        let ids = [a, b, c]
        let panes = factors.enumerated().map { SplitPaneLayout.Pane(id: ids[$0.offset], factor: $0.element) }
        return SplitPaneLayout(panes: panes, orientation: orientation, containerSize: size, backingScaleFactor: 1, flipped: flipped)
    }

    @Test func noPanesLayNothingOut() {
        let r = SplitPaneLayout(panes: [], orientation: .horizontal, containerSize: CGSize(width: 800, height: 600)).compute()
        #expect(r.frames.isEmpty)
        #expect(r.gaps.isEmpty)
    }

    @Test func twoEqualPanesSideBySide() {
        let r = layout([0.5, 0.5]).compute()
        #expect(r.frames[a] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(r.frames[b] == CGRect(x: 510, y: 0, width: 500, height: 600))
        #expect(r.gaps == [CGRect(x: 500, y: 0, width: 10, height: 600)])
        #expect(r.factors[a] == 0.5)
    }

    /// AppKit's y grows upward: the first stacked pane is the top one, at the largest y.
    @Test func stackedPanesStartAtTheTopInAppKit() {
        let r = layout([0.5, 0.5], .vertical, size: CGSize(width: 800, height: 610)).compute()
        #expect(r.frames[a] == CGRect(x: 0, y: 310, width: 800, height: 300))
        #expect(r.frames[b] == CGRect(x: 0, y: 0, width: 800, height: 300))
        #expect(r.gaps == [CGRect(x: 0, y: 300, width: 800, height: 10)])
    }

    /// Windows' y grows downward: the first stacked pane sits at y = 0.
    @Test func stackedPanesStartAtZeroWhenFlipped() {
        let r = layout([0.5, 0.5], .vertical, size: CGSize(width: 800, height: 610), flipped: true).compute()
        #expect(r.frames[a] == CGRect(x: 0, y: 0, width: 800, height: 300))
        #expect(r.frames[b] == CGRect(x: 0, y: 310, width: 800, height: 300))
        #expect(r.gaps == [CGRect(x: 0, y: 300, width: 800, height: 10)])
    }

    /// Side by side, flipped changes nothing.
    @Test func flippedSideBySideIsTheSame() {
        #expect(layout([0.3, 0.7], flipped: true).compute() == layout([0.3, 0.7]).compute())
    }

    @Test func aPaneBelowTheMinimumTakesFromTheOthers() {
        let r = layout([0.05, 0.95]).compute()
        #expect(r.frames[a]?.width == 220)
        #expect(r.frames[b]?.width == 780)
    }

    @Test func zeroFactorsShareEqually() {
        let r = layout([0, 0, 0], size: CGSize(width: 920, height: 600)).compute()
        #expect(r.frames[a]?.width == 300)
        #expect(r.frames[b]?.minX == 310)
        #expect(r.frames[c]?.maxX == 920)
        #expect(r.gaps.count == 2)
    }

    @Test func theLastPaneReachesTheEdgeAfterRounding() {
        let r = SplitPaneLayout(panes: [.init(id: a, factor: 1), .init(id: b, factor: 1), .init(id: c, factor: 1)],
                                orientation: .horizontal, containerSize: CGSize(width: 1001, height: 600), backingScaleFactor: 2).compute()
        #expect(r.frames[c]?.maxX == 1001)
    }

    @Test func dividerHitsCountTheOutset() {
        let r = layout([0.5, 0.5]).compute()
        #expect(r.divider(at: CGPoint(x: 505, y: 300)) == 0)
        #expect(r.divider(at: CGPoint(x: 497, y: 300)) == 0)  // 3 pt left of the gap
        #expect(r.divider(at: CGPoint(x: 494, y: 300)) == nil)
        #expect(r.divider(at: CGPoint(x: 505, y: 300), outset: 0) == 0)
        #expect(r.divider(at: CGPoint(x: 499, y: 300), outset: 0) == nil)
        let three = layout([1, 1, 1], size: CGSize(width: 920, height: 600)).compute()
        #expect(three.divider(at: CGPoint(x: 615, y: 10)) == 1)
    }

    @Test func draggingMovesTheDividerAndStopsAtTheMinimum() {
        let l = layout([0.5, 0.5])
        let moved = l.dragging(dividerAfter: 0, by: 100)
        #expect(moved.factors[a] == 0.6)
        #expect(moved.factors[b] == 0.4)
        #expect(!moved.snapped)
        let far = l.dragging(dividerAfter: 0, by: 1000)
        #expect(far.factors[b] == 0.22)
    }

    @Test func draggingNearTheMiddleSnaps() {
        let r = layout([0.3, 0.7]).dragging(dividerAfter: 0, by: 197)
        #expect(r.snapped)
        #expect(r.factors[a] == 0.5)
        let three = layout([0.2, 0.4, 0.4], size: CGSize(width: 1220, height: 600)).dragging(dividerAfter: 0, by: 118)
        #expect(three.snapped)
        #expect(three.factors[a] == three.factors[b])
    }

    @Test func draggingAMissingDividerChangesNothing() {
        let l = layout([0.5, 0.5])
        #expect(l.dragging(dividerAfter: 1, by: 50).factors == [a: 0.5, b: 0.5])
        #expect(l.dragging(dividerAfter: -1, by: 50).factors == [a: 0.5, b: 0.5])
        let tiny = SplitPaneLayout(panes: [.init(id: a, factor: 0.5), .init(id: b, factor: 0.5)], orientation: .horizontal,
                                   containerSize: CGSize(width: 5, height: 5))
        #expect(!tiny.dragging(dividerAfter: 0, by: 1).snapped)
    }

    @Test func storedFactorsAreNormalized() {
        #expect(SplitPaneLayout.normalizedFactors(ids: [], stored: [:]).isEmpty)
        #expect(SplitPaneLayout.normalizedFactors(ids: [a, b], stored: [:]) == [a: 0.5, b: 0.5])
        #expect(SplitPaneLayout.normalizedFactors(ids: [a, b], stored: [a: 1, b: 3]) == [a: 0.25, b: 0.75])
        // Arc stores only dragged panes: the new one gets what's left.
        #expect(SplitPaneLayout.normalizedFactors(ids: [a, b, c], stored: [a: 0.5]) == [a: 0.5, b: 0.25, c: 0.25])
    }

    @Test func nextAndPreviousPaneWrap() {
        #expect(SplitPaneLayout.pane(1, from: a, in: [a, b, c]) == b)
        #expect(SplitPaneLayout.pane(1, from: c, in: [a, b, c]) == a)
        #expect(SplitPaneLayout.pane(-1, from: a, in: [a, b, c]) == c)
        #expect(SplitPaneLayout.pane(1, from: a, in: [a]) == nil)
        #expect(SplitPaneLayout.pane(1, from: c, in: [a, b]) == nil)
    }
}

/// Split pane layout and Arc's View ▸ Expand Current Split, measured on Arc 1.172.2 (11 Nov 2026) in a
/// window 1728 pt wide with the sidebar hidden: the panes share a 1708 pt content area, 10 pt apart.
struct SplitPaneExpandTests {
    let a = UUID(), b = UUID(), c = UUID()

    func lengths(_ ids: [UUID], factors: [UUID: CGFloat], width: CGFloat = 1708, orientation: SplitOrientation = .horizontal) -> [CGFloat] {
        let size = orientation == .horizontal ? CGSize(width: width, height: 1032) : CGSize(width: 1708, height: width)
        let layout = SplitPaneLayout(panes: ids.map { .init(id: $0, factor: factors[$0] ?? 0) }, orientation: orientation, containerSize: size)
        let frames = layout.compute().frames
        return ids.map { orientation == .horizontal ? frames[$0]!.width : frames[$0]!.height }
    }

    @Test func equalPanesShareTheContent() {
        // Arc: two 849 pt panes.
        #expect(lengths([a, b], factors: [a: 0.5, b: 0.5]) == [849, 849])
    }

    @Test func expandGivesTheOtherPanesTheMinimumAndTheFocusedOneTheRest() {
        // Arc: the focused right pane 1478 pt, the left one 220 pt.
        let f = SplitPaneLayout.expanding(b, in: [a, b])
        #expect(f == [a: 0, b: 1])
        #expect(lengths([a, b], factors: f) == [220, 1478])
        // Three panes: 220 + 1248 + 220, whichever is focused.
        #expect(lengths([a, b, c], factors: SplitPaneLayout.expanding(b, in: [a, b, c])) == [220, 1248, 220])
        #expect(lengths([a, b, c], factors: SplitPaneLayout.expanding(c, in: [a, b, c])) == [220, 220, 1248])
    }

    @Test func expandingAgainChangesNothingAndAnotherPaneSwaps() {
        // Arc keeps one menu title and no toggle: a second Expand leaves the panes where they are.
        let once = SplitPaneLayout.expanding(b, in: [a, b])
        #expect(SplitPaneLayout.expanding(b, in: [a, b]) == once)
        // Expanding the small pane makes it the big one.
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(a, in: [a, b])) == [1478, 220])
    }

    @Test func anExpandedSplitKeepsTheMinimumWhenTheWindowNarrows() {
        // Arc at a 1200 pt window: the focused pane 950, the other still 220 (not its share of the width).
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(a, in: [a, b]), width: 1180) == [950, 220])
    }

    @Test func expandInAVerticalSplitCountsTheDividerBelowAPaneInItsMinimum() {
        // Arc, stacked in a 1064 pt high content area with the middle pane focused: 210 | 614 | 220.
        // A pane above a divider keeps 220 with it, the bottom pane 220 of its own.
        let three = SplitPaneLayout.expanding(b, in: [a, b, c])
        #expect(lengths([a, b, c], factors: three, width: 1064, orientation: .vertical) == [210, 614, 220])
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(a, in: [a, b]), width: 1064, orientation: .vertical) == [834, 220])
        #expect(lengths([a, b], factors: SplitPaneLayout.expanding(b, in: [a, b]), width: 1064, orientation: .vertical) == [210, 844])
    }

    @Test func storedFactorsOfAnExpandedSplitSurviveNormalizing() {
        // sidebar.json keeps 1 and 0, as Arc's itemWidthFactors do; the layout applies the minimum.
        let n = SplitPaneLayout.normalizedFactors(ids: [a, b, c], stored: [a: 0, b: 1, c: 0])
        #expect(n == [a: 0, b: 1, c: 0])
    }

    @Test func aDividerDragFromAnExpandedSplitStartsWhereThePanesAre() {
        // Dragging the divider 30 pt right from 220 | 1478 gives 250 | 1448, not a jump.
        let layout = SplitPaneLayout(panes: [.init(id: a, factor: 0), .init(id: b, factor: 1)], orientation: .horizontal,
                                     containerSize: CGSize(width: 1708, height: 1032))
        let dragged = layout.dragging(dividerAfter: 0, by: 30).factors
        #expect(lengths([a, b], factors: dragged) == [250, 1448])
        // Dragging it left stops at the minimum.
        let left = layout.dragging(dividerAfter: 0, by: -100).factors
        #expect(lengths([a, b], factors: left) == [220, 1478])
    }

    @Test func aPaneWithNoRoomForTheMinimumGetsAnEqualShare() {
        // Four panes in 700 pt: each gets 167.5 pt, below Arc's 220 minimum.
        let ids = [a, b, c, UUID()]
        let f = SplitPaneLayout.expanding(a, in: ids)
        #expect(lengths(ids, factors: f, width: 700).allSatisfy { abs($0 - 167.5) <= 0.5 })
    }
}
