import CraCore
import Foundation
import Testing

/// The sidebar's colours for a space, shared by the Mac's SpacePalette and Windows' flat sidebar.
struct SidebarSurfaceTests {
    private func bytes(_ c: RGB) -> [Int] { [c.r, c.g, c.b].map { Int(($0 * 255).rounded()) } }

    @Test
    func toolbarAndInkMatchArcOnVictor() {
        // Arc's toolbar on Victor's #F8D558 is #72601D; Cra's rule gives #725F1D.
        #expect(bytes(SidebarSurface.toolbar("#F8D558", dark: false)) == [114, 95, 29])
        // Arc's row titles on Victor sample 32/26/0.
        #expect(bytes(SidebarSurface.ink("#F8D558")) == [33, 28, 9])
    }

    /// Settings ▸ Tabs ▸ "Translucent sidebar" (upstream cc6d026f, Ideas #366): every theme, an opaque
    /// preset too, is its raw colours thin over the glass, at SidebarGlass's opacity.
    @Test
    func translucentSidebarMakesEveryThemeThinGlass() {
        let ink = SpaceTheme.presets[0]
        let c = SidebarSurface(resolved: ink, lightMaterial: false, glass: true)
        #expect(c.overMaterial)
        #expect(c.alphaTop == SidebarGlass.alpha(intensity: ink.intensity) && c.alphaBottom == c.alphaTop)
        let first = HexColor.components("#1C242B")!
        #expect(abs(c.stops[0].r - first.r) < 1e-9, "no pull toward black under the glass")
        #expect(SidebarSurface(resolved: ink, lightMaterial: false) == SidebarSurface(resolved: ink, lightMaterial: false, glass: false))
    }

    @Test
    func anOpaqueThemeIsItsColoursPulledByIntensity() {
        let ink = SpaceTheme.presets[0]  // #1C242B / #3A3660 at 0.85, dark
        let c = SidebarSurface(resolved: ink, lightMaterial: false)
        #expect(c.dark)
        #expect(!c.overMaterial)
        #expect(c.alphaTop == 1 && c.alphaBottom == 1)
        #expect(c.stops.count == 2)
        // 0.15 short of full intensity pulls a dark theme 0.15 · 0.35 toward black.
        let first = HexColor.components("#1C242B")!
        #expect(abs(c.stops[0].r - first.r * (1 - 0.0525)) < 1e-9)
        #expect(c.flatStops(over: 0.2) == c.stops)
    }

    @Test
    func oneColourGetsASecondStopAShadeFurther() {
        let t = SpaceTheme(colors: ["#F4F1EA"], intensity: 0.6, noise: 0, appearance: "light")
        let c = SidebarSurface(resolved: t, lightMaterial: true)
        #expect(c.stops.count == 2)
        #expect(c.stops[1].r > c.stops[0].r)
    }

    @Test
    func aSolidColourReadsOverArcsLightOrDarkMaterial() {
        var t = SpaceTheme(colors: ["#3366CC"], intensity: 0.5, noise: 0, appearance: "light")
        t.solid = true
        let light = SidebarSurface(resolved: t, lightMaterial: true)
        #expect(light.overMaterial)
        #expect(abs(light.alphaTop - SpaceTheme.solidAlpha(intensity: 0.5)) < 1e-9)
        // α 0.465 of the colour over a 75 % grey, and over a 20 % one.
        #expect(bytes(light.flatStops(over: 0.75)[0]) == [126, 150, 197])
        #expect(bytes(light.flatStops(over: 0.2)[0]) == [51, 75, 122])
        #expect(!SidebarSurface(resolved: t, lightMaterial: false).lightMaterial)
        // A solid theme isn't pulled: its stops are the colour itself.
        #expect(bytes(light.stops[0]) == [51, 102, 204])
    }

    @Test
    func shownTakesAnAutoThemesHalfAndItsMaterial() {
        var t = SpaceTheme(colors: ["#F8D558"], intensity: 0.5, noise: 0, appearance: "auto")
        t.dark = .init(colors: ["#2A2310"], intensity: 0.5, noise: 0)
        let night = SidebarSurface.shown(t, systemDark: true)
        #expect(night.dark)
        #expect(!night.lightMaterial)
        #expect(night == SidebarSurface(resolved: t.resolved(systemDark: true), lightMaterial: false))
        let day = SidebarSurface.shown(t, systemDark: false)
        #expect(!day.dark)
        #expect(day.lightMaterial)
    }

    @Test
    func overWindowsMaterialGreyTheTopIsSidebarMaterialFillsColour() {
        var t = SpaceTheme(colors: ["#3366CC"], intensity: 0.5, noise: 0, appearance: "dark")
        t.solid = true
        for active in [true, false] {
            let grey = SidebarMaterialFill.grey(theme: t, active: active, systemDark: true, reduceTransparency: false)
            let top = SidebarSurface.shown(t, systemDark: true).flatStops(over: grey)[0]
            let hex = SidebarMaterialFill.hex(theme: t, active: active, systemDark: true, reduceTransparency: false)
            let c = HexColor.components(hex)!
            #expect(bytes(top) == bytes(RGB(c.r, c.g, c.b)))
        }
    }

    @Test
    func anEditorGradientIsFlattenedTopToBottom() {
        var t = SpaceTheme(colors: ["#6CBAD9", "#7F7EDC"], intensity: 0.8, noise: 0, appearance: "dark", vibrant: true)
        t.key = ["#6CBAD9", "#7F7EDC"]
        let c = SidebarSurface.shown(t, systemDark: true)
        #expect(c.overMaterial)
        let grey = SidebarMaterialFill.grey(theme: t, active: true, systemDark: true, reduceTransparency: false)
        let flat = c.flatStops(over: grey)
        #expect(flat.count == 2)
        #expect(flat[0] != flat[1])
        // Each stop is solidAlpha(0.8) of its colour over the grey.
        let a = SpaceTheme.solidAlpha(intensity: 0.8)
        #expect(abs(flat[1].b - (grey + (c.stops[1].b - grey) * a)) < 1e-9)
    }
}
