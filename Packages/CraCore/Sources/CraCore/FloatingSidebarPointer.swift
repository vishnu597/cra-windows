#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// One look at the pointer for a window whose sidebar is hidden: whether the floating sidebar
/// comes out, goes, or stays as it is. The reveal strip, the wait in it, the pointer thrown past
/// the window's edge and the slack before it goes are FloatingSidebarGeometry's, as on the Mac
/// (FloatingSidebar.swift); the Windows app polls the pointer with it.
public struct FloatingSidebarPointer {
    public enum Step: Equatable, Sendable {
        case stay
        case reveal
        case hide
    }

    private var dwell = FloatingSidebarRevealDwell()
    private var offEdge = FloatingSidebarOffEdge()

    public init() {}

    /// - Parameters:
    ///   - point: the pointer in the window's coordinates (top-left origin, DIPs); nil when it
    ///     can't be read.
    ///   - bounds: the window's own area, in the same coordinates.
    ///   - isOut: the floating sidebar is out now.
    ///   - keptOut: something it opened is up (a menu, the Library): it doesn't go while that is.
    ///   - mayReveal: the window may bring it out now (it is the one in front).
    ///   - pressedMouseButtons: a drag or a held button keeps it as it is.
    public mutating func sample(_ point: CGPoint?, in bounds: CGRect, sidebarWidth: CGFloat, isOut: Bool,
                                presentation: SidebarPresentation, keptOut: Bool = false, mayReveal: Bool = true,
                                pressedMouseButtons: Int = 0, edgeToEdge: Bool = false, side: SidebarSide = .left,
                                at now: TimeInterval) -> Step {
        switch presentation.mode {
        case .docked:
            reset()
            return isOut ? .hide : .stay
        case .heldOpen:
            reset()
            return isOut ? .stay : .reveal
        case .hidden:
            break
        }
        guard let point else { return .stay }
        if isOut {
            reset()
            guard presentation.mayRetract, !keptOut else { return .stay }
            return FloatingSidebarGeometry.shouldHide(at: point, in: bounds, sidebarWidth: sidebarWidth,
                                                      pressedMouseButtons: pressedMouseButtons, edgeToEdge: edgeToEdge,
                                                      side: side) ? .hide : .stay
        }
        let inStrip = mayReveal && pressedMouseButtons == 0
            && FloatingSidebarGeometry.shouldReveal(at: point, in: bounds, edgeToEdge: edgeToEdge, side: side)
        let dwelt = dwell.sample(inStrip: inStrip, at: now)
        let thrown = offEdge.sample(point, in: bounds, sidebarWidth: sidebarWidth, side: side, at: now)
        guard mayReveal, pressedMouseButtons == 0, dwelt || thrown == .reveal else { return .stay }
        reset()
        return .reveal
    }

    public mutating func reset() {
        dwell.reset()
        offEdge.reset()
    }
}
