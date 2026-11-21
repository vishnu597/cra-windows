import Foundation

/// A favorite tile's own background (its "Tile Color" menu, `Tab.tileColor`): the presets the menu
/// offers, the entries it lists for a tile, and the tone a coloured tile draws its icon, dot and
/// hover shade in. The Mac's `TileColor` and the Windows sidebar both read it.
public enum FavoriteTileColors {
    public struct Preset: Equatable, Sendable {
        public let name: String
        public let hex: String

        public init(name: String, hex: String) {
            self.name = name
            self.hex = hex
        }
    }

    /// The menu's colours, in its order.
    public static let presets: [Preset] = [
        Preset(name: "White", hex: "#FFFFFF"), Preset(name: "Light Gray", hex: "#D9D9DE"),
        Preset(name: "Graphite", hex: "#48484A"), Preset(name: "Black", hex: "#000000"),
        Preset(name: "Red", hex: "#FF453A"), Preset(name: "Orange", hex: "#FF9F0A"),
        Preset(name: "Yellow", hex: "#FFD60A"), Preset(name: "Green", hex: "#30D158"),
        Preset(name: "Teal", hex: "#40C8E0"), Preset(name: "Blue", hex: "#0A84FF"),
        Preset(name: "Purple", hex: "#BF5AF2"), Preset(name: "Pink", hex: "#FF375F"),
    ]

    /// One line of the Tile Color menu before Other Color…: `hex` nil is Default.
    public struct Choice: Equatable, Sendable {
        public let title: String
        public let hex: String?
        public let checked: Bool

        public init(title: String, hex: String?, checked: Bool) {
            self.title = title
            self.hex = hex
            self.checked = checked
        }
    }

    /// Default, the presets, and Custom when the tile has a colour none of them is. The tile's
    /// own colour is checked.
    public static func choices(current: String?) -> [Choice] {
        var out = [Choice(title: "Default", hex: nil, checked: current == nil)]
        out += presets.map { Choice(title: $0.name, hex: $0.hex, checked: same($0.hex, current)) }
        if let current, !presets.contains(where: { same($0.hex, current) }) {
            out.append(Choice(title: "Custom", hex: current, checked: true))
        }
        return out
    }

    /// A tile with `tileColor` draws its icon and shade as on a dark fill: a colour darker than
    /// half luminance, or the space's own tone with no colour (or one that doesn't parse).
    public static func isDark(tileColor: String?, spaceIsDark: Bool) -> Bool {
        tileColor.flatMap(HexColor.luminance).map { $0 < 0.5 } ?? spaceIsDark
    }

    /// The veil over a coloured tile while it's open or hovered: white at 12 % on a dark tile,
    /// black at 7 % on a light one (the Mac's FavoriteTileView `shade`); nil otherwise.
    public static func shade(dark: Bool, selected: Bool, hovered: Bool) -> (white: Bool, alpha: Double)? {
        guard selected || hovered else { return nil }
        return dark ? (true, 0.12) : (false, 0.07)
    }

    /// A coloured tile's fill with its shade laid over it, for a toolkit that paints one colour
    /// (Windows' button): `tileColor` itself at rest, nil with no colour or one that doesn't parse.
    public static func fill(tileColor: String?, selected: Bool, hovered: Bool) -> String? {
        guard let tileColor, let c = HexColor.components(tileColor) else { return nil }
        let dark = isDark(tileColor: tileColor, spaceIsDark: false)
        guard let veil = shade(dark: dark, selected: selected, hovered: hovered) else { return hex(c) }
        let over = veil.white ? 1.0 : 0.0
        func mix(_ v: Double) -> Double { v * (1 - veil.alpha) + over * veil.alpha }
        return hex((mix(c.r), mix(c.g), mix(c.b)))
    }

    private static func hex(_ c: (r: Double, g: Double, b: Double)) -> String {
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return hex(red: byte(c.r), green: byte(c.g), blue: byte(c.b))
    }

    /// `#RRGGBB` for 8-bit channels, as the colour panel saves it.
    public static func hex(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    private static func same(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}
