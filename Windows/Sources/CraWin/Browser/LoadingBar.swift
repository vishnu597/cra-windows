import CraCEFWin
import CraCore
import Foundation
import WinAppSDK
import WindowsFoundation
import WinSDK

/// Arc's loading bar at the top middle of a browser window (the Mac's LoadingIndicatorView):
/// the page's phase drives CraCore's LoadingIndicator.Clock, and a timer draws its frames into a
/// window the mouse goes through (cra_loading_bar_*), over the page's top or the developer bar.
@MainActor
final class LoadingBar {
    private let bar: UInt
    private let dispatcher: WinAppSDK.DispatcherQueue
    private var clock = LoadingIndicator.Clock()
    private var timer: WinAppSDK.DispatcherQueueTimer?
    /// The window's place on screen (physical pixels) and its pixels a DIP.
    private var origin = POINT(x: 0, y: 0)
    private var scale = 1.0
    private var lightInk = true
    private var visible = true

    init(owner: UInt, dispatcher: WinAppSDK.DispatcherQueue) {
        bar = UInt(cra_loading_bar_create(UInt(owner)))
        self.dispatcher = dispatcher
    }

    var phase: LoadingIndicator.Phase { clock.phase }

    /// `animated` false skips the widening, fade-in and flash, as on the Mac when another tab
    /// comes to the front.
    func set(_ phase: LoadingIndicator.Phase, animated: Bool) {
        guard phase != clock.phase else { return }
        clock.set(phase, animated: animated, at: Self.now)
        draw()
    }

    /// The band's top centre (screen pixels), `scale`, and whether it draws white (`lightInk`).
    /// `visible` false (minimized, HTML full screen) hides it.
    func place(centreX: Int32, top: Int32, scale: Double, lightInk: Bool, visible: Bool) {
        let width = Int32(((LoadingIndicator.trackWidth + 2) * scale).rounded())
        origin = POINT(x: centreX - width / 2, y: top)
        self.scale = scale
        self.lightInk = lightInk
        self.visible = visible
        draw()
    }

    func close() {
        stopTimer()
        cra_loading_bar_destroy(UInt(bar))
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private func draw() {
        let now = Self.now
        guard visible, let frame = clock.frame(at: now) else {
            cra_loading_bar_hide(UInt(bar))
            if !clock.isRunning(at: now) { stopTimer() }
            return
        }
        let width = Int32(((LoadingIndicator.trackWidth + 2) * scale).rounded())
        let height = Int32((LoadingIndicator.topBand * scale).rounded())
        cra_loading_bar_draw(UInt(bar), origin.x, origin.y, width, height, scale, frame.width, LoadingIndicator.height,
                             frame.opacity, frame.lit ? 1 : 0, frame.segmentStart ?? -1, frame.segmentEnd ?? -1,
                             lightInk ? 0xFFFFFF : 0x000000, LoadingIndicator.brightAlpha, LoadingIndicator.trackAlpha)
        startTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = try? dispatcher.createTimer()
        timer?.interval = TimeSpan(duration: 16 * 10_000)  // about 60 frames a second
        timer?.isRepeating = true
        timer?.tick.addHandler { [weak self] _, _ in self?.draw() }
        try? timer?.start()
    }

    private func stopTimer() {
        try? timer?.stop()
        timer = nil
    }
}
