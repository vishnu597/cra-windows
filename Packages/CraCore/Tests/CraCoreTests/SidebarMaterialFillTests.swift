import CraCore
import Foundation
import Testing

/// A one-colour or editor-made space on Windows: Arc's colour over its material, flat, active or not.
struct SidebarMaterialFillTests {
    func solid(_ hex: String, intensity: Double = 0.5, appearance: String = "dark") -> SpaceTheme {
        var t = SpaceTheme(colors: [hex], intensity: intensity, noise: 0, appearance: appearance)
        t.solid = true
        return t
    }

    func bytes(_ hex: String) -> [Int] {
        let c = HexColor.components(hex)!
        return [c.r, c.g, c.b].map { Int(($0 * 255).rounded()) }
    }

    @Test func greyMatchesArcsMaterialOverAPlainBackdrop() {
        // Dark active: 66 + 0.518 · backdrop; inactive flat 212; Reduce Transparency flat 160.
        #expect(abs(SidebarMaterialFill.grey(.solidActive, backdrop: 0) * 255 - 66.3) < 0.1)
        #expect(abs(SidebarMaterialFill.grey(.solidActive, backdrop: 1) * 255 - 198.4) < 0.1)
        #expect(abs(SidebarMaterialFill.grey(.solidInactive, backdrop: 0.5) * 255 - 211.65) < 0.1)
        #expect(abs(SidebarMaterialFill.grey(.solidReduced, backdrop: 1) * 255 - 160.65) < 0.1)
    }

    @Test func activeSolidSpaceIsItsColourOverTheDarkMaterial() {
        // α = 0.19 + 0.55 · 0.5 = 0.465 over 66.3 + 0.518 · 32 = 82.9: black reads 44.
        #expect(bytes(SidebarMaterialFill.hex(theme: solid("#000000"), active: true, systemDark: true, reduceTransparency: false)) == [44, 44, 44])
        // White at full intensity (α 0.74): 0.74 · 255 + 0.26 · 82.9 = 210.
        #expect(bytes(SidebarMaterialFill.hex(theme: solid("#FFFFFF", intensity: 1), active: true, systemDark: true, reduceTransparency: false)) == [210, 210, 210])
    }

    @Test func inactiveWindowGoesToTheFlatGrey() {
        let red = solid("#FF0000")
        let active = bytes(SidebarMaterialFill.hex(theme: red, active: true, systemDark: true, reduceTransparency: false))
        let inactive = bytes(SidebarMaterialFill.hex(theme: red, active: false, systemDark: true, reduceTransparency: false))
        // 0.465 · 255 + 0.535 · 211.65 = 231.8; green and blue are the grey's share alone, 113.
        #expect(inactive == [232, 113, 113])
        #expect(active != inactive)
        // Light material inactive is flat 252.
        let light = solid("#000000", appearance: "light")
        #expect(bytes(SidebarMaterialFill.hex(theme: light, active: false, systemDark: false, reduceTransparency: false)) == [135, 135, 135])
    }

    @Test func reduceTransparencyIsTheSameActiveOrNot() {
        let t = solid("#3366CC")
        let a = SidebarMaterialFill.hex(theme: t, active: true, systemDark: true, reduceTransparency: true)
        let b = SidebarMaterialFill.hex(theme: t, active: false, systemDark: true, reduceTransparency: true)
        #expect(a == b)
    }

    @Test func themesNotDrawnOverTheMaterialKeepTheirColour() {
        let preset = SpaceTheme.presets[0]
        #expect(SidebarMaterialFill.hex(theme: preset, active: false, systemDark: true, reduceTransparency: false) == "#1C242B")
    }

    @Test func autoFollowsWindowsForTheMaterial() {
        let auto = solid("#808080", appearance: "auto")
        let dark = SidebarMaterialFill.hex(theme: auto, active: true, systemDark: true, reduceTransparency: false)
        let light = SidebarMaterialFill.hex(theme: auto, active: true, systemDark: false, reduceTransparency: false)
        #expect(bytes(light)[0] > bytes(dark)[0])
    }
}
