import Foundation

/// The ring on the download bin while downloads run (#272, the Mac's DownloadProgressBadgeView):
/// which of its looks shows, so a window without AppKit draws the same badge. Running, the ring
/// follows every running download together; when the last one ends with its file a check takes
/// the arrow's place for `doneFor`, and a failed, cancelled or stuck one makes the badge just go.
public struct DownloadBadge: Equatable, Sendable {
    public enum Look: Equatable, Sendable {
        case hidden
        /// The ring, 0…1, with the arrow in it.
        case running(Double)
        /// The ring full and gone, a check in its place.
        case done
    }

    /// How long the check shows before the badge fades (the Mac's 1.2 s).
    public static let doneFor: TimeInterval = 1.2
    /// The fades in and out and the check's arrival (the Mac's 0.2 s).
    public static let fade: TimeInterval = 0.2
    /// The scale the badge grows from as it shows (the check grows from 0.4).
    public static let popFrom = 0.6
    public static let checkPopFrom = 0.4

    public private(set) var look: Look = .hidden
    /// The downloads the ring followed, to tell at the end whether they finished.
    private var following: Set<UInt32> = []

    public init() {}

    /// The badge for `live` (DownloadHistory.live) at `now`; returns whether the look changed.
    @discardableResult
    public mutating func update(_ live: [DownloadList.Live], now: Date) -> Bool {
        let before = look
        if let progress = DownloadList.progress(live), DownloadList.holdsBin(live, now: now) {
            following.formUnion(live.filter(\.running).map(\.id))
            look = .running(progress)
        } else if case .running = look {
            // A finished download leaves `live`; a failed or cancelled one stays in it, ended.
            let finished = !following.isEmpty && following.allSatisfy { id in !live.contains { $0.id == id } }
            look = finished ? .done : .hidden
            following = []
        }
        return look != before
    }

    /// After `doneFor`: the check fades. A download that started meanwhile keeps its ring.
    public mutating func doneShown() {
        if look == .done { look = .hidden }
    }
}
