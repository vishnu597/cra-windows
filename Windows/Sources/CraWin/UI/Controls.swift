import CraCore
import Foundation
import UWP
import WindowsFoundation
import WinUI

/// Small builders for the code-made XAML (there is no markup in the Windows shell).
@MainActor
enum UI {
    static func text(_ string: String, size: Double = 13, color: Brush? = nil, trimmed: Bool = true) -> TextBlock {
        let t = TextBlock()
        t.text = string
        t.fontSize = size
        if let color { t.foreground = color }
        if trimmed { t.textTrimming = .characterEllipsis }
        return t
    }

    /// A borderless button whose content is `content`, filled with `fill` (transparent by default).
    static func button(_ content: UIElement, fill: Brush? = nil, padding: Thickness = Thickness(left: 8, top: 5, right: 8, bottom: 5),
                       _ action: @escaping @MainActor () -> Void) -> Button {
        let b = Button()
        b.content = content
        // On press: a click from a page moves Win32 focus into the XAML island, and the release
        // that would finish a release-mode click was lost.
        b.clickMode = .press
        b.background = fill ?? clear
        b.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        b.padding = padding
        b.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        b.click.addHandler { _, _ in action() }
        return b
    }

    static func button(_ title: String, color: Brush? = nil, _ action: @escaping @MainActor () -> Void) -> Button {
        button(text(title, color: color, trimmed: false), action)
    }

    static func menuItem(_ title: String, _ action: @escaping @MainActor () -> Void) -> MenuFlyoutItem {
        let item = MenuFlyoutItem()
        item.text = title
        item.click.addHandler { _, _ in action() }
        return item
    }

    /// A row for a KeyBindings command, its shortcut on the right as the Mac's context menus show it
    /// (MenuItems.add(_:action:), #89): the key the user set in Settings ▸ Shortcuts, nothing when
    /// the command has none on Windows.
    static func menuItem(_ title: String, action id: String, _ action: @escaping @MainActor () -> Void) -> MenuFlyoutItem {
        let item = menuItem(title, action)
        if let keys = WinKeyBindings.shared.action(id)?.primary?.windowsDisplay { item.keyboardAcceleratorTextOverride = keys }
        return item
    }

    static func column(_ length: GridLength) -> ColumnDefinition {
        let c = ColumnDefinition()
        c.width = length
        return c
    }

    static func row(_ length: GridLength) -> RowDefinition {
        let r = RowDefinition()
        r.height = length
        return r
    }

    static let auto = GridLength(value: 0, gridUnitType: .auto)
    static let star = GridLength(value: 1, gridUnitType: .star)
    static func pixels(_ n: Double) -> GridLength { GridLength(value: n, gridUnitType: .pixel) }

    static func brush(_ hex: String, alpha: UInt8 = 255) -> SolidColorBrush {
        let c = HexColor.components(hex) ?? (r: 0.5, g: 0.5, b: 0.5)
        return brush(UInt8(c.r * 255), UInt8(c.g * 255), UInt8(c.b * 255), alpha: alpha)
    }

    static func brush(_ r: UInt8, _ g: UInt8, _ b: UInt8, alpha: UInt8 = 255) -> SolidColorBrush {
        SolidColorBrush(UWP.Color(a: alpha, r: r, g: g, b: b))
    }

    static let clear = brush(0, 0, 0, alpha: 0)

    /// A CraCore colour, 0...1 a channel.
    static func color(_ c: RGB, alpha: UInt8 = 255) -> UWP.Color {
        func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        return UWP.Color(a: alpha, r: byte(c.r), g: byte(c.g), b: byte(c.b))
    }

    static func brush(_ c: RGB, alpha: UInt8 = 255) -> SolidColorBrush { SolidColorBrush(color(c, alpha: alpha)) }

    /// A sidebar tone: white or black at its opacity.
    static func brush(_ tone: SidebarTones.Tone) -> SolidColorBrush {
        let v: UInt8 = tone.white ? 255 : 0
        return brush(v, v, v, alpha: UInt8((min(max(tone.alpha, 0), 1) * 255).rounded()))
    }
}

/// The sidebar's colours for a space, from its theme as the app shows it (an Auto theme's light or
/// dark half by Windows' app mode or View ▸ Appearance): CraCore's SidebarSurface, the Mac's
/// SpacePalette. Windows has no live material behind the sidebar, so a see-through theme is drawn
/// as it reads over Arc's, active or not (`flatStops(over:)` with SidebarMaterialFill's grey).
@MainActor
struct SidebarPalette {
    /// The sidebar's gradient, top to bottom.
    let fill: Brush
    /// Its top colour, opaque: a glyph or a line in the space's colour, the page area's ground.
    let top: RGB
    let ground: Brush
    let text: Brush
    let secondaryText: Brush
    /// The open tab's row and a hovered row.
    let selected: Brush
    /// The URL pill and a favorite tile at rest (SidebarTones.pill).
    let tile: Brush
    /// The fill is dark: one-colour favicons are drawn white on it (FaviconView).
    let isDark: Bool

    /// `active` is the window's active look (HostWindow.activeLook): a theme Arc draws over its
    /// material goes to the material's flat inactive grey under its colours (SidebarMaterialFill).
    init(_ theme: SpaceTheme, active: Bool = true) {
        let dark = WinAppearance.isDark
        let colors = SidebarSurface.shown(theme, systemDark: dark)
        let grey = SidebarMaterialFill.grey(theme: theme, active: active, systemDark: dark,
                                            reduceTransparency: WinAppearance.reduceTransparency)
        let stops = colors.flatStops(over: grey)
        isDark = colors.dark
        top = stops.first ?? .black
        fill = Self.gradient(stops)
        ground = UI.brush(top)
        if colors.dark {
            text = UI.brush(255, 255, 255, alpha: 235)
            secondaryText = UI.brush(255, 255, 255, alpha: 153)
            selected = UI.brush(255, 255, 255, alpha: 33)
        } else {
            // Arc's light themes: titles in the theme's ink, the open tab a near-white pill.
            text = UI.brush(colors.ink)
            secondaryText = UI.brush(0, 0, 0, alpha: 128)
            selected = UI.brush(255, 255, 255, alpha: 189)
        }
        tile = UI.brush(SidebarTones.pill(dark: colors.dark))
    }

    private static func gradient(_ stops: [RGB]) -> Brush {
        guard stops.count > 1, stops.contains(where: { $0 != stops[0] }) else { return UI.brush(stops.first ?? .black) }
        let brush = LinearGradientBrush()
        brush.startPoint = WindowsFoundation.Point(x: 0.5, y: 0)
        brush.endPoint = WindowsFoundation.Point(x: 0.5, y: 1)
        for (i, c) in stops.enumerated() {
            let stop = GradientStop()
            stop.color = UI.color(c)
            stop.offset = Double(i) / Double(stops.count - 1)
            brush.gradientStops.append(stop)
        }
        return brush
    }
}
