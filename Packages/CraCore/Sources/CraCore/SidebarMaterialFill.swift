import Foundation

/// The one flat colour a sidebar shows where nothing captures the desktop behind it (Windows: its
/// XAML column is opaque, no live blur under it). A theme Arc draws over its material
/// (`SpaceTheme.drawnOverMaterial`) comes out as Arc's would over a plain backdrop: the colour at
/// `solidAlpha(intensity)` over the material grey that `SidebarBackdrop` resolves, active or not.
/// Any other theme keeps its own first colour, as before.
public enum SidebarMaterialFill {
    /// What sits behind a Windows window's sidebar in place of the desktop capture: the window
    /// ground Windows 11 paints under Mica, #202020 in dark mode and #F3F3F3 in light.
    public static func windowGround(dark: Bool) -> Double { dark ? 32.0 / 255 : 243.0 / 255 }

    /// The material's grey (0...1) over a plain backdrop: the capture through the black dim, then the
    /// white lift. With no capture (`source == .none`) it is the lift alone.
    public static func grey(_ material: SidebarBackdrop, backdrop: Double) -> Double {
        let seen = material.source == .none ? 0 : backdrop * (1 - material.dim)
        return seen * (1 - material.liftTop) + material.liftTop
    }

    /// The sidebar's colour as "#RRGGBB". `systemDark` picks both the material Auto shows and the
    /// window ground; `reduceTransparency` is Windows' Transparency effects turned off.
    public static func hex(theme: SpaceTheme, active: Bool, systemDark: Bool, reduceTransparency: Bool) -> String {
        let first = theme.colors.first ?? "#1C242B"
        guard theme.drawnOverMaterial, let c = HexColor.components(first) else { return first }
        let material = SidebarBackdrop.resolve(
            solid: true, active: active, fullscreen: false, reduceTransparency: reduceTransparency,
            tintAvailable: false, vibrant: SidebarBackdrop.Vibrant(dim: 1, liftTop: 0, liftBottom: 0, dimInactive: 1, liftInactive: 0),
            lightMaterial: theme.usesLightMaterial(systemDark: systemDark),
            darkGradient: theme.drawnOverDarkGradientMaterial)
        let g = grey(material, backdrop: windowGround(dark: systemDark))
        let a = SpaceTheme.solidAlpha(intensity: theme.intensity)
        func channel(_ v: Double) -> String {
            let byte = Int((a * v + (1 - a) * g) * 255 + 0.5)
            return String(format: "%02X", max(0, min(255, byte)))
        }
        return "#" + channel(c.r) + channel(c.g) + channel(c.b)
    }
}
