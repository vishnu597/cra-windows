import Foundation

/// Arc's download flight (DownloadsUI.DownloadToLibrary, the Mac's DownloadFlight), as numbers a
/// window without Core Animation draws frame by frame: a navy glyph thrown from the pointer as a
/// download starts, rising `apexHeight` above the higher end, then falling under `gravity` at a
/// constant horizontal speed onto the downloads button. Measured on Arc 1.170 at 60 fps: 32 at
/// launch, 48 at the apex, 10 on arrival; it fades in over the climb and its arrow turns from ↘
/// to ↓ over the first half. Points or DIPs, top-left origin, y down.
public struct DownloadFlightPath: Equatable, Sendable {
    public static let gravity = 2630.0
    public static let apexHeight = 90.0
    public static let launchDiameter = 32.0
    public static let maxDiameter = 48.0
    public static let arrivalDiameter = 10.0
    /// The blue glow around it (the Mac's shadow radius).
    public static let glowRadius = 9.0

    public let start: CGPoint
    public let end: CGPoint
    public let apexTime: Double
    public let duration: Double
    public let vx: Double
    public let vy: Double

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
        let apexY = Double(min(start.y, end.y)) - Self.apexHeight
        apexTime = (2 * (Double(start.y) - apexY) / Self.gravity).squareRoot()
        duration = apexTime + (2 * (Double(end.y) - apexY) / Self.gravity).squareRoot()
        vy = -Self.gravity * apexTime
        vx = Double(end.x - start.x) / duration
    }

    public func point(at t: Double) -> CGPoint {
        CGPoint(x: Double(start.x) + vx * t, y: Double(start.y) + vy * t + Self.gravity * t * t / 2)
    }

    public struct Frame: Equatable, Sendable {
        public var center: CGPoint
        public var diameter: Double
        /// The arrow's turn, radians in y-down coordinates: -π/4 points it ↘, 0 ↓.
        public var angle: Double
        public var opacity: Double
    }

    /// The glyph `t` seconds after launch (clamped to the flight).
    public func frame(at t: Double) -> Frame {
        let t = min(max(0, t), duration)
        let p = duration > 0 ? t / duration : 1
        let apexP = duration > 0 ? apexTime / duration : 0
        let diameter: Double
        if p < apexP {
            diameter = Self.launchDiameter + (Self.maxDiameter - Self.launchDiameter) * p / apexP
        } else {
            diameter = Self.maxDiameter - (Self.maxDiameter - Self.arrivalDiameter) * (p - apexP) / max(1e-9, 1 - apexP)
        }
        let turn = min(1, p / 0.5)
        let angle = -(1 - turn * turn * (3 - 2 * turn)) * (Double.pi / 4)
        let opacity = apexP > 0 ? min(1, p / apexP) : 1
        return Frame(center: point(at: t), diameter: diameter, angle: angle, opacity: opacity)
    }
}
