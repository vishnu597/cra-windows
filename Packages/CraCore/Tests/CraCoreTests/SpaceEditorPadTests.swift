import CraCore
import Testing

/// The theme editor's pad, as both editors draw it: a colour's place and a press's colour, and
/// the colours a stored theme puts on the pad.
struct SpaceEditorPadTests {
    /// A full red sits `reach` to the right of the centre, a full green 120° round (y down), grey
    /// at the centre.
    @Test
    func coloursSitByHueAndSaturation() {
        let red = SpaceColorWheel.padOffset(of: "#FF0000")
        #expect(abs(red.dx - SpaceColorWheel.reach) < 0.001 && abs(red.dy) < 0.001)
        let green = SpaceColorWheel.padOffset(of: "#00FF00", reach: 100)
        #expect(abs(green.dx + 50) < 0.01 && abs(green.dy - 86.6) < 0.01)
        let grey = SpaceColorWheel.padOffset(of: "#808080")
        #expect(grey.dx == 0 && grey.dy == 0)
    }

    /// A press gives back the hue and saturation of the place it lands on, full past `reach`.
    @Test
    func aPressPicksItsPlace() {
        let below = SpaceColorWheel.padPick(dx: 0, dy: 76.5)
        #expect(abs(below.hue - 90) < 0.001 && abs(below.saturation - 0.5) < 0.001)
        #expect(SpaceColorWheel.padPick(dx: -400, dy: 0).saturation == 1)
        let green = SpaceColorWheel.padOffset(of: "#00FF00")
        let back = SpaceColorWheel.padPick(dx: green.dx, dy: green.dy)
        #expect(abs(back.hue - 120) < 0.01 && abs(back.saturation - 1) < 0.001)
    }

    /// The pad shows a theme's key; a flat fill (its colour twice, or `solid`) is one handle.
    @Test
    func aStoredThemesPadColours() {
        let keyed = SpaceTheme(colors: ["#111111", "#222222"], intensity: 0.5, noise: 0, appearance: "dark", key: ["#FF0000"])
        #expect(SpaceThemeVariants.padKey(of: keyed) == ["#FF0000"])
        let flat = SpaceTheme(colors: ["#3366FF", "#3366FF"], intensity: 0.5, noise: 0, appearance: "auto")
        #expect(SpaceThemeVariants.padKey(of: flat) == ["#3366FF"])
        let solid = SpaceTheme(colors: ["#3366FF", "#FFFFFF"], intensity: 0.5, noise: 0, appearance: "auto", solid: true)
        #expect(SpaceThemeVariants.padKey(of: solid) == ["#3366FF"])
        let gradient = SpaceTheme(colors: ["#3366FF", "#FF6633"], intensity: 0.5, noise: 0, appearance: "auto")
        #expect(SpaceThemeVariants.padKey(of: gradient) == ["#3366FF", "#FF6633"])
    }
}
