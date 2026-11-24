import Foundation

/// Sidebar tones Cra takes from Arc as an ink and its opacity over the space's colour: white on dark
/// themes, black on light ones. Measured on Arc 1.172.1 at 1x and 2x, 9 Nov 2026 (GitHub #293), in a
/// light vibrant space and a dark one.
public enum SidebarTones {
    /// White (dark themes) or black (light themes) at `alpha`.
    public struct Tone: Equatable, Sendable {
        public var white: Bool
        public var alpha: Double

        public init(white: Bool, alpha: Double) {
            self.white = white
            self.alpha = alpha
        }
    }

    /// The space header's title and a tab group's name: dimmer than the rest of the secondary text.
    /// Arc: white 0.45 over a dark theme, black 0.46 over a light one (Cra had 0.5).
    public static func sectionTitle(dark: Bool) -> Tone {
        Tone(white: dark, alpha: dark ? 0.45 : 0.46)
    }

    /// The sidebar URL pill and a favorite tile at rest. Arc: black 0.045 on light themes, white 0.095 on
    /// dark ones (Cra had 0.08 there).
    public static func pill(dark: Bool) -> Tone {
        Tone(white: dark, alpha: dark ? 0.095 : 0.045)
    }

    /// The pill and the tiles under the pointer, one hover for both: a shade darker on light themes and
    /// lighter on dark ones. Arc: black 0.09 and white 0.145. Cra's pill turned white 0.74 on light themes.
    public static func pillHover(dark: Bool) -> Tone {
        Tone(white: dark, alpha: dark ? 0.145 : 0.09)
    }
}

extension SidebarTones {
    /// A favorite tile with no colour of its own (the Mac's FavoriteTileView): open, white at 13 %
    /// on a dark theme and 38 % on a light one; under the pointer, the pill's hover; at rest, the pill.
    public static func favoriteTile(dark: Bool, selected: Bool, hovered: Bool) -> Tone {
        if selected { return Tone(white: true, alpha: dark ? 0.13 : 0.38) }
        return hovered ? pillHover(dark: dark) : pill(dark: dark)
    }

    /// The open favorite's 2 pt rim (Arc's neutral one, with the logo outline off): white at 14 %
    /// on a dark tile, black at 17 % on a light one.
    public static func favoriteRim(dark: Bool) -> Tone {
        Tone(white: dark, alpha: dark ? 0.14 : 0.17)
    }

    /// The logo outline's opacity over the tile.
    public static let favoriteLogoRimOpacity = 0.72
}
