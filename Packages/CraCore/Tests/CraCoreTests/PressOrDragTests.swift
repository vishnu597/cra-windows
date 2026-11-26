import CraCore
import Testing

/// A Media tile or download row: a click opens it, a drag hands the file out.
struct PressOrDragTests {
    @Test func letGoInPlaceIsAClick() {
        #expect(PressOrDrag.classify(dx: 1, dy: 1, buttonDown: false, slopX: 2, slopY: 2) == .click)
    }

    @Test func heldWithinTheSlopWaits() {
        #expect(PressOrDrag.classify(dx: 2, dy: -2, buttonDown: true, slopX: 2, slopY: 2) == .waiting)
    }

    @Test func movedPastTheSlopIsADrag() {
        #expect(PressOrDrag.classify(dx: 3, dy: 0, buttonDown: true, slopX: 2, slopY: 2) == .drag)
        #expect(PressOrDrag.classify(dx: 0, dy: -3, buttonDown: true, slopX: 2, slopY: 2) == .drag)
    }
}
