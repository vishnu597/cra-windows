import Foundation

/// Click pairs belong to the sidebar item, not the control drawing it: selecting a tab or
/// folding a folder can replace that control between the two presses. Times and distances
/// come from the platform's mouse settings; a drag or a keyboard invocation cancels the pair.
public struct SidebarClick: Sendable {
    public enum Target: Equatable, Sendable {
        case item(UUID), space(UUID)
    }

    private struct Press: Sendable {
        var target: Target
        var time: Double
        var x: Double
        var y: Double
        var modifiers: Int
    }
    private var previous: Press?

    public init() {}

    public mutating func press(_ target: Target, at time: Double, x: Double, y: Double,
                               modifiers: Int = 0, interval: Double, distanceX: Double, distanceY: Double) -> Int {
        let now = Press(target: target, time: time, x: x, y: y, modifiers: modifiers)
        if let previous, previous.target == target, previous.modifiers == modifiers,
           time >= previous.time, time - previous.time <= interval,
           abs(x - previous.x) <= distanceX, abs(y - previous.y) <= distanceY {
            self.previous = nil
            return 2
        }
        previous = now
        return 1
    }

    public mutating func cancel() { previous = nil }
}
