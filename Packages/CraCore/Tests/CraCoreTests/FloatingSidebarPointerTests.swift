#if canImport(CoreGraphics)
import CoreGraphics
#endif
import CraCore
import Foundation
import Testing

/// The Windows app's hidden sidebar: the pointer brings it out at the window's edge and lets it
/// go past its far side, as FloatingSidebarGeometry decides on the Mac.
struct FloatingSidebarPointerTests {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let hidden = SidebarPresentation(sidebarVisible: false, hasSelectedTab: true)

    @Test func theEdgeBringsItOutAfterTheDwell() {
        var pointer = FloatingSidebarPointer()
        let edge = CGPoint(x: 2, y: 300)
        #expect(pointer.sample(edge, in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden, edgeToEdge: true, at: 0) == .stay)
        #expect(pointer.sample(edge, in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden, edgeToEdge: true, at: 0.05) == .stay)
        #expect(pointer.sample(edge, in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden, edgeToEdge: true,
                               at: FloatingSidebarGeometry.revealDwell) == .reveal)
    }

    @Test func brushingTheEdgeOrHoldingAButtonBringsNothing() {
        var pointer = FloatingSidebarPointer()
        #expect(pointer.sample(CGPoint(x: 2, y: 300), in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden, edgeToEdge: true, at: 0) == .stay)
        #expect(pointer.sample(CGPoint(x: 400, y: 300), in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden, edgeToEdge: true, at: 0.05) == .stay)
        #expect(pointer.sample(CGPoint(x: 2, y: 300), in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden, edgeToEdge: true, at: 0.1) == .stay)
        var dragging = FloatingSidebarPointer()
        for t in [0, 0.05, 0.1, 0.2] {
            #expect(dragging.sample(CGPoint(x: 2, y: 300), in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden,
                                    pressedMouseButtons: 1, edgeToEdge: true, at: t) == .stay)
        }
    }

    @Test func aWindowBehindAnotherBringsNothing() {
        var pointer = FloatingSidebarPointer()
        for t in [0, 0.05, 0.1, 0.2] {
            #expect(pointer.sample(CGPoint(x: 2, y: 300), in: bounds, sidebarWidth: 280, isOut: false, presentation: hidden,
                                   mayReveal: false, edgeToEdge: true, at: t) == .stay)
        }
    }

    @Test func itGoesOnlyPastTheSlackAndNotWhileKeptOut() {
        var pointer = FloatingSidebarPointer()
        let near = CGPoint(x: 280 + FloatingSidebarGeometry.margin + FloatingSidebarGeometry.leaveSlack - 1, y: 300)
        let far = CGPoint(x: 280 + FloatingSidebarGeometry.margin + FloatingSidebarGeometry.leaveSlack + 1, y: 300)
        #expect(pointer.sample(near, in: bounds, sidebarWidth: 280, isOut: true, presentation: hidden, at: 0) == .stay)
        #expect(pointer.sample(far, in: bounds, sidebarWidth: 280, isOut: true, presentation: hidden, keptOut: true, at: 0.1) == .stay)
        #expect(pointer.sample(far, in: bounds, sidebarWidth: 280, isOut: true, presentation: hidden, pressedMouseButtons: 1, at: 0.2) == .stay)
        #expect(pointer.sample(far, in: bounds, sidebarWidth: 280, isOut: true, presentation: hidden, at: 0.3) == .hide)
    }

    @Test func anEmptyWindowHoldsItOutAndADockedOneHasNone() {
        var pointer = FloatingSidebarPointer()
        let empty = SidebarPresentation(sidebarVisible: false, hasSelectedTab: false)
        let far = CGPoint(x: 900, y: 300)
        #expect(pointer.sample(far, in: bounds, sidebarWidth: 280, isOut: false, presentation: empty, at: 0) == .reveal)
        #expect(pointer.sample(far, in: bounds, sidebarWidth: 280, isOut: true, presentation: empty, at: 0.1) == .stay)
        let docked = SidebarPresentation(sidebarVisible: true, hasSelectedTab: true)
        #expect(pointer.sample(far, in: bounds, sidebarWidth: 280, isOut: true, presentation: docked, at: 0.2) == .hide)
        #expect(pointer.sample(CGPoint(x: 2, y: 300), in: bounds, sidebarWidth: 280, isOut: false, presentation: docked, at: 0.3) == .stay)
    }

    @Test func ctrlSHidesTheSidebarOnWindows() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["toggleSidebar"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+S"])
    }
}
