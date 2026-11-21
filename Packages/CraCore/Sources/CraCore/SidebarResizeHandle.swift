import Foundation

/// Where the docked sidebar's edge takes a drag, and how fast the drag reads, as the Mac's
/// ShellView and ResizeHandleView have them, for a platform that hit-tests and times the drag
/// itself (Windows). `SidebarResize` then turns the drag into a width.
public enum SidebarResizeHandle {
    /// The strip reaches this far either side of the sidebar's edge.
    public static let outset: Double = 4

    /// The strip's x and width for a docked sidebar `sidebarWidth` points wide (ShellView's
    /// `frames.handle`: `width - 4`, 8 wide).
    public static func strip(sidebarWidth: Double) -> (x: Double, width: Double) {
        (sidebarWidth - outset, 2 * outset)
    }

    /// The pointer's speed in points a second after a move of `dx` points in `dt` seconds,
    /// smoothed like a pan recognizer's velocity so one quick event doesn't read as a fling:
    /// half the speed before, half this move's.
    public static func smoothedSpeed(_ previous: Double, dx: Double, dt: Double) -> Double {
        dt > 0 ? previous * 0.5 + dx / dt * 0.5 : previous
    }

    /// The width a window opens with from the saved one (`WindowPrefs.sidebarWidth`), held in
    /// Arc's range.
    public static func restored(_ saved: Double) -> Double {
        saved.isFinite ? SidebarWidth.clamped(saved) : WindowPrefs().sidebarWidth
    }
}
