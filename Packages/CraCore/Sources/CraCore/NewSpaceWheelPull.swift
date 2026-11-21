// CGFloat comes from Foundation off Apple platforms (Windows, Linux).
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Arc's "+" past the last space (NewSpaceSwipe) from a wheel's sideways events, for Windows,
/// where a precision touchpad's two-finger swipe arrives as WM_MOUSEHWHEEL deltas with no
/// gesture's begin or end. The fingers' travel past the last space is the wheel's lines toward
/// the next space at `pointsPerLine`; it drives the same rubber band, ring and hold as the Mac's
/// swipe. With no end event, the fingers count as lifted once the wheel has been quiet for
/// `liftPause`, and the ring's hold is measured to the last event, when they last moved.
public struct NewSpaceWheelPull: Equatable, Sendable {
    /// Travel per wheel line (120 of a WM_MOUSEHWHEEL delta): Windows scrolls 3 lines a notch,
    /// some 40 DIPs of a page per line.
    public static let pointsPerLine: CGFloat = 40
    /// Quiet this long and the fingers have lifted: past a touchpad's gaps between events,
    /// short of a pause a person would notice.
    public static let liftPause: TimeInterval = 0.15

    /// The fingers' travel past the last space, in points.
    public private(set) var travel: CGFloat = 0
    /// When the ring became full, while it is.
    public private(set) var fullSince: TimeInterval?
    public private(set) var lastEventTime: TimeInterval = -.infinity

    public init() {}

    /// One sideways wheel event of `lines` on the last space (signed as
    /// WheelSpaceSwitch.lines(windowsDelta:horizontal:): negative toward the next space) at
    /// `time`, in a sidebar `width` points wide. Returns the overscroll the "+" shows. An event
    /// after a lift starts a new pull; lines back toward the last space take travel off.
    @discardableResult
    public mutating func pull(lines: CGFloat, width: CGFloat, at time: TimeInterval) -> CGFloat {
        if time - lastEventTime > Self.liftPause { self = Self() }
        lastEventTime = time
        travel = max(0, travel - lines * Self.pointsPerLine)
        let pulled = overscroll(width: width)
        if !NewSpaceSwipe.isActivated(overscroll: pulled) { fullSince = nil } else if fullSince == nil { fullSince = time }
        return pulled
    }

    /// The rubber band's overscroll for the travel so far (NewSpaceSwipe.overscroll).
    public func overscroll(width: CGFloat) -> CGFloat {
        NewSpaceSwipe.overscroll(travel: travel, page: width)
    }

    /// Whether the "+" is out and the wheel has been quiet long enough to count as a lift.
    public func isLifted(at time: TimeInterval) -> Bool {
        travel > 0 && time - lastEventTime > Self.liftPause
    }

    /// The fingers lifted: whether Arc's Create a Space page comes in (the ring was full for
    /// NewSpaceSwipe.holdBeforeLift). The "+" goes back and the pull starts over.
    public mutating func lift() -> Bool {
        let creates = NewSpaceSwipe.createsOnLift(fullFor: fullSince.map { lastEventTime - $0 })
        self = Self()
        return creates
    }
}
