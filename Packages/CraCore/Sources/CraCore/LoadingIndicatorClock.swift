/// The loading bar's animation as values at a time, for a platform that draws every frame itself
/// (Windows) rather than handing Core Animation keyframes as LoadingIndicatorView does on the Mac.
/// It follows that view step for step: the waiting pill's pulse, its widening into the track, the
/// sweep, and the flash that shrinks away, with Core Animation's ease curves.
public extension LoadingIndicator {
    /// What to draw: the track `width` points wide (centred), at `opacity`, all of it bright
    /// (`lit`) or dim under a bright segment from `segment.start` to `segment.end` (0...1 of the
    /// track).
    struct Frame: Equatable, Sendable {
        public var width: Double
        public var opacity: Double
        public var lit: Bool
        public var segmentStart: Double?
        public var segmentEnd: Double?

        public init(width: Double, opacity: Double, lit: Bool, segmentStart: Double? = nil, segmentEnd: Double? = nil) {
            self.width = width
            self.opacity = opacity
            self.lit = lit
            self.segmentStart = segmentStart
            self.segmentEnd = segmentEnd
        }
    }

    /// Times are seconds on any steady clock the caller keeps.
    struct Clock: Sendable {
        public private(set) var phase: Phase = .hidden
        private var step: Step = .idle
        private var since: Double = 0

        private enum Step: Sendable {
            case idle
            case pulse
            case expand(fromWidth: Double, fromOpacity: Double)
            case sweep(offset: Double, fadeIn: Bool)
            case finish(fromWidth: Double, fromOpacity: Double, wasLoading: Bool)
        }

        /// The fade-in of a track that appears, and of a widening pill to full opacity.
        public static let fadeInDuration = 0.15
        /// The fade of a pill that never got an answer.
        public static let waitingFadeDuration = 0.2

        public init() {}

        /// The page's phase changed. `animated` false (another tab came to the front, or a new
        /// tab's first load) skips the widening, the fade-in and the flash.
        public mutating func set(_ new: Phase, animated: Bool, at now: Double) {
            guard new != phase else { return }
            let old = phase
            let current = frame(at: now)
            phase = new
            since = now
            switch new {
            case .hidden:
                step = animated ? .finish(fromWidth: current?.width ?? LoadingIndicator.trackWidth, fromOpacity: current?.opacity ?? 0,
                                          wasLoading: old == .loading) : .idle
            case .waiting:
                step = .pulse
            case .loading:
                if old == .waiting, animated {
                    step = .expand(fromWidth: current?.width ?? LoadingIndicator.pillWidth, fromOpacity: current?.opacity ?? 0)
                } else {
                    step = .sweep(offset: 0, fadeIn: animated && old == .hidden)
                }
            }
        }

        /// Whether anything still moves or shows: false once the bar is gone, so the caller can
        /// stop its timer and hide its window.
        public func isRunning(at now: Double) -> Bool { frame(at: now) != nil }

        /// The bar at `now`; nil when there is nothing to draw.
        public func frame(at now: Double) -> Frame? {
            let elapsed = max(0, now - since)
            switch step {
            case .idle:
                return nil
            case .pulse:
                return Frame(width: LoadingIndicator.pillWidth, opacity: Self.pulseOpacity(at: elapsed), lit: true)
            case .expand(let fromWidth, let fromOpacity):
                guard elapsed < LoadingIndicator.expandDuration else {
                    return Self.sweepFrame(elapsed: elapsed - LoadingIndicator.expandDuration, offset: LoadingIndicator.sweepTailStart, fadeIn: false)
                }
                let grow = LoadingIndicator.Ease.easeOut(elapsed / LoadingIndicator.expandDuration)
                let fade = min(1, elapsed / Self.fadeInDuration)
                return Frame(width: fromWidth + (LoadingIndicator.trackWidth - fromWidth) * grow, opacity: fromOpacity + (1 - fromOpacity) * fade, lit: true)
            case .sweep(let offset, let fadeIn):
                return Self.sweepFrame(elapsed: elapsed, offset: offset, fadeIn: fadeIn)
            case .finish(let fromWidth, let fromOpacity, let wasLoading):
                let duration = wasLoading ? LoadingIndicator.finishDuration : Self.waitingFadeDuration
                guard elapsed < duration else { return nil }
                let p = LoadingIndicator.Ease.easeIn(elapsed / duration)
                let start = wasLoading ? 1 : fromOpacity
                let width = wasLoading ? fromWidth + (LoadingIndicator.finishWidth - fromWidth) * p : fromWidth
                return Frame(width: width, opacity: start * (1 - p), lit: true)
            }
        }

        private static func sweepFrame(elapsed: Double, offset: Double, fadeIn: Bool) -> Frame {
            let ends = LoadingIndicator.sweep(at: elapsed + offset * LoadingIndicator.sweepPeriod)
            let opacity = fadeIn ? min(1, elapsed / fadeInDuration) : 1
            return Frame(width: LoadingIndicator.trackWidth, opacity: opacity, lit: false, segmentStart: ends.start, segmentEnd: ends.end)
        }

        /// The waiting pill's opacity through `LoadingIndicator.pulseKeyframes`, eased in and out between them.
        static func pulseOpacity(at elapsed: Double) -> Double {
            let t = (elapsed / LoadingIndicator.pulsePeriod).truncatingRemainder(dividingBy: 1)
            let k = LoadingIndicator.pulseKeyframes
            for i in 1..<k.count where t <= k[i].time {
                let f = (t - k[i - 1].time) / (k[i].time - k[i - 1].time)
                return k[i - 1].opacity + (k[i].opacity - k[i - 1].opacity) * LoadingIndicator.Ease.easeInOut(f)
            }
            return k[k.count - 1].opacity
        }
    }

    /// Core Animation's named timing functions, as cubic Béziers from (0, 0) to (1, 1).
    enum Ease {
        public static func easeIn(_ t: Double) -> Double { bezier(t, 0.42, 0, 1, 1) }
        public static func easeOut(_ t: Double) -> Double { bezier(t, 0, 0, 0.58, 1) }
        public static func easeInOut(_ t: Double) -> Double { bezier(t, 0.42, 0, 0.58, 1) }

        /// y at x = `t` on the curve with control points (x1, y1) and (x2, y2).
        static func bezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
            let x = min(1, max(0, t))
            func coordinate(_ s: Double, _ a: Double, _ b: Double) -> Double {
                let u = 1 - s
                return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
            }
            // x(s) only rises, so halving finds s for x.
            var lo = 0.0, hi = 1.0
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                if coordinate(mid, x1, x2) < x { lo = mid } else { hi = mid }
            }
            return coordinate((lo + hi) / 2, y1, y2)
        }
    }
}
