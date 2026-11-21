import Foundation

/// Arc's hover tips (the Mac's ArcTooltip.swift) as decisions a platform without AppKit can
/// follow: when a tip shows, where it hangs, how its label splits into text and key caps, and
/// its measurements. Measured on Arc 1.170 and 1.171 (see ArcTooltipController and
/// ArcTooltipLabel on the Mac).
public enum ArcTooltipRules {
    /// The pointer rests this long on a control before its tip shows.
    public static let idleDelay = 1.6
    /// Moving onto another control this soon after a tip closed shows its tip at once.
    public static let warmWindow = 0.5
    /// A tip pops in with no fade and fades out in this long.
    public static let fadeOutDuration = 0.06

    /// How long to wait before showing a tip for a control the pointer has just come onto (or
    /// moved on): none while another tip shows or one closed within `warmWindow`. Times are
    /// seconds on one steady clock; `lastHiddenAt` nil after a click or key, which makes the
    /// next tip wait the whole delay again.
    public static func delay(tipShowing: Bool, lastHiddenAt: Double?, now: Double, idleDelay: Double = idleDelay) -> Double {
        if tipShowing { return 0 }
        if let hidden = lastHiddenAt, now - hidden < warmWindow { return 0 }
        return idleDelay
    }

    /// "Copy URL (⇧⌘C)" → ("Copy URL", ["⇧", "⌘", "C"]), and Windows' "Copy URL (Ctrl+Shift+C)"
    /// → ("Copy URL", ["Ctrl", "Shift", "C"]). Help without a shortcut stays whole.
    public static func split(_ help: String) -> (text: String, keys: [String]) {
        guard help.hasSuffix(")"), let open = help.range(of: " (", options: .backwards) else { return (help, []) }
        let shortcut = String(help[open.upperBound..<help.index(before: help.endIndex)])
        let text = String(help[..<open.lowerBound])
        let glyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        if let first = shortcut.first, glyphs.contains(first), shortcut.count <= 6 {
            var caps = shortcut.prefix { glyphs.contains($0) }.map(String.init)
            let key = shortcut.drop { glyphs.contains($0) }
            if !key.isEmpty { caps.append(String(key)) }
            return (text, caps)
        }
        let windowsModifiers: Set<String> = ["Ctrl", "Alt", "Shift", "Win"]
        var parts = shortcut.components(separatedBy: "+")
        // "Ctrl++" names the plus key.
        if shortcut.hasSuffix("++") { parts = Array(parts.dropLast(2)) + ["+"] }
        if parts.count >= 2, parts.dropLast().allSatisfy({ windowsModifiers.contains($0) }), let key = parts.last,
           !key.isEmpty, key.count <= 5, !windowsModifiers.contains(key) {
            return (text, parts)
        }
        // A lone key in parentheses: "Exit the Library (Esc)", "Reload (F5)".
        let lone = ["Esc", "Enter", "Tab", "Del"].contains(shortcut)
            || (shortcut.hasPrefix("F") && Int(shortcut.dropFirst()).map { (1...24).contains($0) } == true)
        return lone ? (text, [shortcut]) : (help, [])
    }

    /// Where a tip goes beside its control (Arc's ArcTooltipConfiguration.preferredAnchor).
    public enum Placement: Equatable, Sendable {
        /// Off the bottom-trailing corner of a 16 pt box around the control's centre.
        case corner
        /// By the pointer, 13 pt right of and 14 pt below it (sidebar rows and tiles).
        case cursor
        /// Centred above, its bottom 19.75 pt above the centre (the space icons).
        case above
        /// Beside it, 19.5 pt right of its centre and centred on it (the Library button).
        case trailing
    }

    /// The tip's top-left corner in points, y down (Windows' screen coordinates), for a control
    /// centred at `centre`, the pointer at `pointer`, and a tip `size`, kept 4 pt inside
    /// `screen` (x, y, width, height). A tip that would run off the bottom goes above instead.
    public static func origin(placement: Placement, centre: (x: Double, y: Double), pointer: (x: Double, y: Double),
                              size: (width: Double, height: Double),
                              screen: (x: Double, y: Double, width: Double, height: Double)) -> (x: Double, y: Double) {
        var x: Double, y: Double
        switch placement {
        case .corner: (x, y) = (centre.x + 8, centre.y + 7)
        case .cursor: (x, y) = (pointer.x + 13, pointer.y + 14)
        case .above: (x, y) = (centre.x - size.width / 2, centre.y - 19.75 - size.height)
        case .trailing: (x, y) = (centre.x + 19.5, centre.y - size.height / 2)
        }
        x = min(max(x, screen.x + 4), screen.x + screen.width - size.width - 4)
        if y + size.height > screen.y + screen.height - 4 {
            let anchorY = placement == .cursor ? pointer.y : centre.y
            y = anchorY - 7 - size.height
        }
        y = max(y, screen.y + 4)
        return (x, y)
    }

    /// The label's measurements (ArcTooltipLabel): a 28 pt capsule, 12 pt medium text 10 pt in,
    /// 19 pt key caps 6 pt after it, 3 pt apart and 10 pt from the end. Text past 280 pt wraps,
    /// and a wrapped tip is a rectangle with 10 pt corners and 6 pt above and below.
    public enum Metrics {
        public static let height = 28.0
        public static let fontSize = 12.0
        public static let leading = 10.0
        public static let trailing = 10.0
        public static let maxTextWidth = 280.0
        public static let cap = 19.0
        public static let capGap = 3.0
        public static let textToCaps = 6.0
        public static let capFontSize = 10.0
        public static let multilinePadding = 6.0
        public static let multilineCorner = 10.0
        /// A cap's face sits 1 pt in at the sides and top and 2.5 pt up from its darker edge.
        public static let capEdgeCorner = 4.5
        public static let capFaceCorner = 3.5
        /// The ring around the tip: its fill moved 10 % toward white.
        public static let ringMix = 0.1

        /// The tip's size for text `textWidth` × `textHeight` points wide and tall (measured by
        /// the platform at `fontSize`, wrapped at `maxTextWidth`), with `keys` caps of `capWidths`.
        public static func size(textWidth: Double, textHeight: Double, capWidths: [Double]) -> (width: Double, height: Double) {
            let multiline = textWidth > maxTextWidth || textHeight > fontSize * 1.9
            let text = min(textWidth, maxTextWidth)
            let caps = capWidths.isEmpty ? 0 : textToCaps + capWidths.reduce(0, +) + capGap * Double(capWidths.count - 1)
            let height = max(Self.height, max(textHeight, capWidths.isEmpty ? 0 : cap) + (multiline ? 2 * multilinePadding : 0))
            return ((leading + text + caps + trailing).rounded(.up), height.rounded(.up))
        }

        /// A cap is square for one character and grows for a word ("Ctrl", "Shift") by its
        /// text plus 5 pt each side.
        public static func capWidth(glyphWidth: Double, characters: Int) -> Double {
            characters <= 1 ? cap : max(cap, (glyphWidth + 10).rounded(.up))
        }

        /// The corner radius: a capsule on one line, a rounded rectangle when the text wraps.
        public static func cornerRadius(height: Double) -> Double {
            height > Self.height ? multilineCorner : Self.height / 2
        }
    }

    /// The tip's colours from the window's space tones (TooltipTones), or Little Arc's navy for
    /// a window with no space: fill, title, cap face, cap glyph and cap edge.
    public struct Colors: Equatable, Sendable {
        public var fill, title, cap, capGlyph, capEdge, ring: RGB

        public init(fill: RGB, title: RGB, cap: RGB, capGlyph: RGB, capEdge: RGB) {
            (self.fill, self.title, self.cap, self.capGlyph, self.capEdge) = (fill, title, cap, capGlyph, capEdge)
            ring = fill.mixed(with: .white, Metrics.ringMix)
        }

        public init(_ tones: TooltipTones) {
            self.init(fill: tones.fill, title: tones.title, cap: tones.badge, capGlyph: tones.ink, capEdge: tones.badge.mixed(with: tones.ink, 0.5))
        }

        /// Little Arc's tip (LittlePalette on the Mac).
        public static let little = Colors(fill: RGB(10 / 255, 13 / 255, 75 / 255), title: RGB(222 / 255, 223 / 255, 253 / 255),
                                          cap: RGB(211 / 255, 212 / 255, 253 / 255), capGlyph: RGB(40 / 255, 46 / 255, 252 / 255),
                                          capEdge: RGB(119 / 255, 122 / 255, 211 / 255))
    }
}
