import CraCore
import Foundation
import Testing

/// Windows' sidebar draws its slice of Arc's window gradient (#669): 45° from the window's top left, in Oklab.
struct WindowGradientSliceTests {
    /// The left column's slice is the window's own axis; a column docked on the right starts part way along it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func aColumnShowsItsPartOfTheWindowsAxis() {
        let left = WindowGradientSlice.axis(windowWidth: 1200, windowHeight: 800, originX: 0, originY: 0)
        let window = SpaceGradient.axis(width: 1200, height: 800)
        #expect(left.start.x == 0 && left.start.y == 0)
        #expect(left.end.x == window.end.x && left.end.y == window.end.y)
        let right = WindowGradientSlice.axis(windowWidth: 1200, windowHeight: 800, originX: 900, originY: 0)
        #expect(right.start.x == -900 && right.start.y == 0)
        #expect(right.end.x == window.end.x - 900 && right.end.y == window.end.y)
        // Still 45°: the axis runs as far down as across.
        #expect(abs((right.end.x - right.start.x) - (right.end.y - right.start.y)) < 1e-12)
    }

    /// The colours blend in Oklab, not straight: the middle sample of a red to teal theme is Oklab's
    /// middle, which is not the sRGB average.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func colorsFollowTheOklabCurve() {
        let surface = SidebarSurface(resolved: opaque(["#E0303A", "#20B0A8"]), lightMaterial: false)
        let flat = surface.flatStops(over: 0.2)
        let samples = WindowGradientSlice.colors(surface, over: 0.2)
        #expect(samples.count == WindowGradientSlice.sampleCount)
        #expect(samples.first == flat.first)
        #expect(samples.last.map { abs($0.r - flat[1].r) < 1e-6 && abs($0.g - flat[1].g) < 1e-6 } == true)
        let mid = samples[WindowGradientSlice.sampleCount / 2]
        let oklab = SpaceGradient.mix(SpaceGradient.RGBA(r: flat[0].r, g: flat[0].g, b: flat[0].b),
                                      SpaceGradient.RGBA(r: flat[1].r, g: flat[1].g, b: flat[1].b), 0.5)
        #expect(abs(mid.r - oklab.r) < 1e-9 && abs(mid.g - oklab.g) < 1e-9 && abs(mid.b - oklab.b) < 1e-9)
        let straight = flat[0].mixed(with: flat[1], 0.5)
        #expect(abs(mid.g - straight.g) > 0.01)
    }

    /// One flat colour stays one colour (a solid brush, no gradient).
    @Test
    func aFlatThemeIsOneColour() {
        let surface = SidebarSurface(resolved: opaque(["#333333", "#333333"]), lightMaterial: false)
        let colors = WindowGradientSlice.colors(surface, over: 0.2)
        #expect(colors.count == 1)
        #expect(colors.first == surface.stops.first)
    }

    /// A dark, opaque theme at full intensity: its stops are its colours.
    private func opaque(_ colors: [String]) -> SpaceTheme {
        var theme = SpaceTheme.presets[0]
        theme.colors = colors
        theme.intensity = 1
        theme.appearance = "dark"
        theme.vibrant = false
        theme.solid = false
        theme.accent = nil
        theme.dark = nil
        theme.key = nil
        return theme
    }
}
