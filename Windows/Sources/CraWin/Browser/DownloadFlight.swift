import CraCEFWin
import CraCore
import Foundation
import WinAppSDK
import WindowsFoundation
import WinSDK

/// Arc's download flight (the Mac's DownloadFlight): as a download starts, a navy glyph is thrown
/// from the pointer onto the sidebar's downloads button. CraCore's DownloadFlightPath gives each
/// frame; a 60 Hz timer draws it into a small window the mouse goes through (cra_download_flight_*).
@MainActor
final class DownloadFlight {
    private let window: UInt
    private let path: DownloadFlightPath
    private let scale: Double
    private let started = ProcessInfo.processInfo.systemUptime
    private var timer: WinAppSDK.DispatcherQueueTimer?
    /// The flights in the air, kept until they land.
    private static var flights: [DownloadFlight] = []

    /// Flies from `from` to `to` (screen pixels) over `owner` (an HWND), `scale` pixels a DIP.
    @discardableResult
    static func launch(owner: UInt, from: POINT, to: POINT, scale: Double, dispatcher: WinAppSDK.DispatcherQueue) -> TimeInterval {
        let flight = DownloadFlight(owner: owner, from: from, to: to, scale: scale)
        flights.append(flight)
        flight.start(dispatcher)
        return flight.path.duration
    }

    private init(owner: UInt, from: POINT, to: POINT, scale: Double) {
        window = UInt(cra_download_flight_create(UInt(owner)))
        self.scale = max(0.5, scale)
        // In DIPs, so the Mac's gravity and sizes hold at any scaling.
        path = DownloadFlightPath(start: CGPoint(x: Double(from.x) / self.scale, y: Double(from.y) / self.scale),
                                  end: CGPoint(x: Double(to.x) / self.scale, y: Double(to.y) / self.scale))
    }

    private func start(_ dispatcher: WinAppSDK.DispatcherQueue) {
        draw()
        guard Self.flights.contains(where: { $0 === self }) else { return }
        timer = try? dispatcher.createTimer()
        timer?.interval = TimeSpan(duration: 16 * 10_000)
        timer?.isRepeating = true
        timer?.tick.addHandler { [weak self] _, _ in self?.draw() }
        try? timer?.start()
    }

    private func draw() {
        let t = ProcessInfo.processInfo.systemUptime - started
        guard window != 0, t < path.duration else { return land() }
        let frame = path.frame(at: t)
        cra_download_flight_draw(UInt(window), Int32((Double(frame.center.x) * scale).rounded()),
                                 Int32((Double(frame.center.y) * scale).rounded()), frame.diameter * scale, frame.angle,
                                 frame.opacity, DownloadFlightPath.glowRadius * scale)
    }

    private func land() {
        try? timer?.stop()
        timer = nil
        if window != 0 { cra_download_flight_destroy(UInt(window)) }
        Self.flights.removeAll { $0 === self }
    }
}
