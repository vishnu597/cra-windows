import Foundation

/// Arc's space gradient for a window that can't paint its whole background with it (Windows: the
/// sidebar is a XAML column beside Chromium's pages). Arc runs the gradient across the window at 45°
/// from its top left, blended in Oklab (`SpaceGradient`, #669); the column shows its own slice of that,
/// so the colour at any point of it is the colour the Mac's window has there.
public enum WindowGradientSlice {
    /// Colours along the gradient a straight-blending brush needs to follow Arc's Oklab curve
    /// (the Mac's `SpaceBackgroundView.sampleCount`).
    public static let sampleCount = 9

    /// The gradient's start and end in a part's own points, for a part of a `windowWidth`×`windowHeight`
    /// window whose top left is at `originX`, `originY` in the window (both in the same units).
    public static func axis(windowWidth: Double, windowHeight: Double, originX: Double, originY: Double)
        -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let a = SpaceGradient.axis(width: windowWidth, height: windowHeight)
        return ((a.start.x - originX, a.start.y - originY), (a.end.x - originX, a.end.y - originY))
    }

    /// The sidebar's opaque colours along the gradient, first to last: `SidebarSurface.flatStops(over:)`
    /// blended in Oklab as Arc's are, `count` of them spread evenly.
    public static func colors(_ surface: SidebarSurface, over grey: Double, count: Int = sampleCount) -> [RGB] {
        let stops = surface.flatStops(over: grey).map { SpaceGradient.RGBA(r: $0.r, g: $0.g, b: $0.b) }
        guard stops.count > 1, stops.contains(where: { $0 != stops[0] }) else {
            return stops.prefix(1).map { RGB($0.r, $0.g, $0.b) }
        }
        return SpaceGradient.samples(stops, count: count).map { RGB($0.r, $0.g, $0.b) }
    }

    /// The end of a relative (unit-space) brush across a frame with no window around it (a Manage Spaces
    /// card): 45° in points from its top left, as `SpaceGradient.unitEnd`.
    public static func unitEnd(width: Double, height: Double) -> (x: Double, y: Double) {
        SpaceGradient.unitEnd(width: width, height: height)
    }
}
