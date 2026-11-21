import CraCore
import Foundation
import UWP
import WinAppSDK
import WinSDK
import WindowsFoundation
import WinUI

/// Arc's "+" past the last space (the Mac's NewSpacePlusView, on CraCore's NewSpaceSwipe): a
/// 30 DIP disc that comes in from past the sidebar's right edge as a sideways swipe pulls on the
/// last space, its ring filling, turned over in Arc's accent once full. Windows has no swipe
/// gesture, so a touchpad's sideways wheel drives it (NewSpaceWheelPull), and a pause is the
/// lift. Here the disc follows the pull directly, without the Mac's spring or bulge. Every
/// control is kept here.
@MainActor
final class NewSpacePlusView {
    let root = Grid()
    private let disc = WinUI.Ellipse()  // not GDI's Ellipse
    private let ring = WinUI.Ellipse()
    private let plus = FontIcon()
    private let dashes = DoubleCollection()
    private var activated = false
    private var coloured = false

    init() {
        let side = Double(NewSpaceSwipe.disc)
        root.width = side
        root.height = side
        root.horizontalAlignment = .right
        root.verticalAlignment = .center
        root.isHitTestVisible = false
        root.visibility = .collapsed
        for e in [disc, ring] {
            e.width = side
            e.height = side
            root.children.append(e)
        }
        ring.strokeThickness = Double(NewSpaceSwipe.ring)
        ring.fill = UI.clear
        ring.strokeDashArray = dashes
        plus.glyph = WinGlyph.code("plus")
        plus.fontSize = Double(NewSpaceSwipe.glyph)
        plus.horizontalAlignment = .center
        plus.verticalAlignment = .center
        root.children.append(plus)
    }

    /// The list is `overscroll` DIPs past the last space: the disc's place, its fade and its ring
    /// (NewSpaceSwipe.shown, discAlpha, progress), and Arc's colours for the app's appearance.
    func show(overscroll: CGFloat) {
        guard overscroll > 0 else { return hide() }
        let shown = NewSpaceSwipe.shown(overscroll: overscroll)
        let side = Double(NewSpaceSwipe.disc)
        // Its right edge from discStartPast outside the sidebar to discRestGap inside it.
        let start = -Double(NewSpaceSwipe.discStartPast) - side, rest = Double(NewSpaceSwipe.discRestGap)
        root.margin = Thickness(left: 0, top: 0, right: start + Double(shown) * (rest - start), bottom: 0)
        root.opacity = Double(NewSpaceSwipe.discAlpha(shown: shown))
        root.visibility = .visible
        let progress = Double(NewSpaceSwipe.progress(overscroll: overscroll))
        let isActivated = NewSpaceSwipe.isActivated(overscroll: overscroll)
        // The ring's dash, in stroke widths, round the ellipse's path from three o'clock.
        let thickness = Double(NewSpaceSwipe.ring)
        let round = Double.pi * (side - thickness) / thickness
        dashes.replaceAll(progress >= 1 ? [round + 1, 0] : [progress * round, round + 1])
        if isActivated != activated || !coloured { colour(activated: isActivated) }
        coloured = true
        activated = isActivated
    }

    func hide() {
        root.visibility = .collapsed
        activated = false
    }

    private func colour(activated: Bool) {
        let look = NewSpaceSwipe.look(activated: activated, dark: WinAppearance.isDark)
        func brush(_ c: NewSpaceSwipe.Color) -> Brush {
            func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(Double(v), 0), 1) * 255).rounded()) }
            return UI.brush(byte(c.red), byte(c.green), byte(c.blue), alpha: byte(c.alpha))
        }
        disc.fill = brush(look.fill)
        ring.stroke = brush(look.ring)
        plus.foreground = brush(look.plus)
    }
}

// MARK: The pull, from the sidebar's wheel

extension SidebarView {
    /// A sideways wheel event on the last space, toward the next one (or back, while the "+" is
    /// out): the pull goes on, and returns whether it took the event. Anywhere else, or with a
    /// window that has no spaces of its own, the wheel switches spaces as before.
    func pullNewSpace(lines: CGFloat, onLastSpace: Bool) -> Bool {
        guard onLastSpace, creationPage == nil, NewSpaceSwipe.isOffered(standalone: store.isStandalone(window: windowID)),
              lines < 0 || newSpacePull.travel > 0 else { return false }
        let now = Double(GetTickCount64()) / 1000
        let overscroll = newSpacePull.pull(lines: lines, width: CGFloat(favoritesWidth), at: now)
        newSpacePlus.show(overscroll: overscroll)
        watchForLift()
        return true
    }

    /// No end event comes: a timer looks for the wheel going quiet (NewSpaceWheelPull.isLifted).
    private func watchForLift() {
        guard newSpaceLiftTimer == nil,
              let queue = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil, let timer = try? queue.createTimer()
        else { return }
        timer.interval = TimeSpan(duration: 30 * 10_000)
        timer.isRepeating = true
        timer.tick.addHandler { [weak self] _, _ in self?.liftTick() }
        try? timer.start()
        newSpaceLiftTimer = timer
    }

    private func liftTick() {
        guard newSpacePull.isLifted(at: Double(GetTickCount64()) / 1000) || newSpacePull.travel == 0 else { return }
        try? newSpaceLiftTimer?.stop()
        newSpaceLiftTimer = nil
        newSpacePlus.hide()
        // The ring held full long enough: Arc's Create a Space page comes in.
        if newSpacePull.lift() { beginSpaceCreation() }
    }
}
