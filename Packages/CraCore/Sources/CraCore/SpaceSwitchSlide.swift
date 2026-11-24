import Foundation

/// Switching spaces with a click, a key or the wheel, as the Mac's pager shows it (SpacePagerView): the
/// strip of spaces settles on the new one with Arc's critically damped spring (`LibrarySwipe.omega`,
/// ~0.2 s), so the new space slides in from the side it sits on in the dock while the gradient's colours
/// cross-fade from the old space's to the new one's. A platform that draws one space at a time (Windows)
/// moves the new space's content from a page away to its place and blends the colours along the way.
public enum SpaceSwitchSlide {
    /// Which way the new space comes in: +1 from the right (a later space in the dock), -1 from the left,
    /// 0 for no slide (the first drawing, the same space, a space not in the dock).
    public static func direction(from old: Int?, to new: Int?) -> Int {
        guard let old, let new, old != new else { return 0 }
        return new > old ? 1 : -1
    }

    /// The slide `t` seconds in: how far the content still is from its place, in sidebar widths (1 at the
    /// start, settling to 0), how far the colours have come (0 old, 1 new), and whether it has settled.
    public static func frame(at t: Double, width: Double) -> (offset: Double, blend: Double, done: Bool) {
        let time = CGFloat(max(0, t))
        let x = Double(LibrarySwipe.settle(from: 1, velocity: 0, to: 0, at: time))
        let done = LibrarySwipe.isSettled(from: 1, velocity: 0, to: 0, at: time, width: CGFloat(max(1, width)))
        if done { return (0, 1, true) }
        let offset = max(0, min(1, x))
        return (offset, 1 - offset, false)
    }

    /// The gradient's colours `blend` of the way from `old` to `new`, stop by stop (the longer list's
    /// count; a shorter one holds its last colour).
    public static func colors(_ old: [RGB], _ new: [RGB], blend: Double) -> [RGB] {
        let k = max(0, min(1, blend))
        guard !old.isEmpty, k < 1 else { return new }
        guard !new.isEmpty else { return old }
        let n = max(old.count, new.count)
        return (0..<n).map { i in old[min(i, old.count - 1)].mixed(with: new[min(i, new.count - 1)], k) }
    }
}
