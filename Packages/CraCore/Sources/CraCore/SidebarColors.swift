import Foundation

/// The sidebar's colours for a space, as both apps draw them: the gradient's stops and their
/// opacity top and bottom, the opaque colour they read as over the material behind them, the
/// light themes' ink and the toolbar band. The Mac paints the stops at their opacity over a live
/// material (SpacePalette, ShellView); a window with no live material (Windows) paints
/// `flatStops(over:)` with the material's grey (SidebarMaterialFill).
public struct SidebarColors: Equatable, Sendable {
    /// The theme reads dark: white text over it.
    public var dark: Bool
    /// The gradient's colours, top to bottom (one colour gets a second a shade further on).
    public var stops: [RGB]
    /// The stops' opacity at the top and the bottom (1 when the theme is opaque).
    public var alphaTop: Double
    public var alphaBottom: Double
    /// One colour or an editor gradient over Arc's material (SpaceTheme.drawnOverMaterial).
    public var overMaterial: Bool
    /// That material is Arc's light one (SpaceTheme.usesLightMaterial, #455).
    public var lightMaterial: Bool
    /// Light themes' text: the palette colour pushed to 13.5 % brightness (Arc's row titles).
    public var ink: RGB
    /// Arc's toolbar band.
    public var toolbar: RGB

    /// The theme as the app shows it now: an Auto theme's light or dark half, over the material its
    /// appearance picks.
    public static func shown(_ theme: SpaceTheme, systemDark: Bool) -> SidebarColors {
        SidebarColors(resolved: theme.resolved(systemDark: systemDark),
                      lightMaterial: theme.usesLightMaterial(systemDark: systemDark))
    }

    /// The colours of a resolved theme (its appearance is light or dark, or judged by colour).
    public init(resolved theme: SpaceTheme, lightMaterial: Bool) {
        let dark = theme.isDark
        let base = theme.colors.isEmpty ? ["#DDDDDD"] : theme.colors
        let source = theme.accent ?? base[0]
        // Over Arc's material (one colour, or a gradient made in the editor, #643): the colours at
        // Arc's one-colour opacity. Vibrant (an imported Arc theme): its stops at `intensity` over the
        // blur. Opaque: intensity 1 = the raw colours; lower pulls toward white (light) or black (dark).
        let overMaterial = theme.drawnOverMaterial
        let intensity = theme.intensity
        let pull = theme.vibrant || theme.solid ? 0 : (1 - intensity) * (dark ? 0.35 : 0.6)
        let toward = dark ? RGB.black : RGB.white
        func mixed(_ hex: String, _ amount: Double) -> RGB {
            Self.rgb(hex).mixed(with: toward, max(0, min(1, amount)))
        }
        var stops = base.map { mixed($0, pull) }
        if stops.count == 1 { stops.append(mixed(base[0], pull + 0.15)) }
        let top: Double, bottom: Double
        if overMaterial {
            top = SpaceTheme.solidAlpha(intensity: intensity)
            bottom = top
        } else if theme.vibrant {
            top = dark ? max(0.35, min(0.9, intensity * 2.2)) : min(0.95, intensity * 1.70)
            bottom = dark ? max(0.35, min(0.9, intensity * 2.2)) : min(0.95, intensity * 2.35)
        } else {
            (top, bottom) = (1, 1)
        }
        self.dark = dark
        self.stops = stops
        alphaTop = top
        alphaBottom = bottom
        self.overMaterial = overMaterial
        self.lightMaterial = lightMaterial
        ink = Self.ink(source)
        toolbar = Self.toolbar(source, dark: dark)
    }

    /// The stops at their opacity, top to bottom, over a flat `grey` (0...1): what the sidebar reads
    /// as where nothing behind it shows through. An opaque theme's stops come back as they are.
    public func flatStops(over grey: Double) -> [RGB] {
        let material = RGB(grey, grey, grey), n = stops.count
        return stops.enumerated().map { i, c in
            let t = n > 1 ? Double(i) / Double(n - 1) : 0
            let a = min(1, alphaTop + (alphaBottom - alphaTop) * t)
            return a < 1 ? material.mixed(with: c, a) : c
        }
    }

    /// Arc's light-theme ink: the colour pushed to ~13 % brightness, saturation +0.10
    /// (Victor #F8D558 → ≈#201A0C; Arc's row titles sample 32/26/0).
    public static func ink(_ hex: String) -> RGB {
        let c = rgb(hex)
        var (h, s, v) = SpaceTheme.hsb(c.r, c.g, c.b)
        s = min(1, s + 0.10)
        v *= 0.135
        let o = SpaceTheme.rgb(h: h, s: s, v: v)
        return RGB(o.0, o.1, o.2)
    }

    /// Arc's toolbar band: the colour pushed to a dark, fully saturated shade on light themes
    /// (46 % brightness, saturation +0.10: Victor #F8D558 → #725F1D, Arc #72601D) and a muted,
    /// slightly darker one on dark themes (60 % saturation, 80 % brightness: JYSK #010220 →
    /// #0A0B19, Arc #0E0B16).
    public static func toolbar(_ hex: String, dark: Bool) -> RGB {
        let c = rgb(hex)
        var (h, s, v) = SpaceTheme.hsb(c.r, c.g, c.b)
        if dark { s *= 0.6; v *= 0.8 } else { s = min(1, s + 0.10); v *= 0.46 }
        let o = SpaceTheme.rgb(h: h, s: s, v: v)
        return RGB(o.0, o.1, o.2)
    }

    private static func rgb(_ hex: String) -> RGB {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        return RGB(c.r, c.g, c.b)
    }
}
