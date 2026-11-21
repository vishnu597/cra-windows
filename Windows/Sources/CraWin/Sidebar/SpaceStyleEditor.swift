import CraCore
import Foundation
import UWP
import WinUI

/// Arc's theme editor (the Mac's SpaceStyleEditor), which Edit Theme Color… opens beside the
/// sidebar: the colour pad with Auto / Light / Dark on top and − / + at the bottom, nine preset
/// swatches between paging arrows (SpaceColorPresets), the intensity and the grain. Every change
/// shows in the space at once (SidebarStore.previewTheme) and is written when the editor closes,
/// as in Arc. The theme comes from the pad's state through SpaceThemeVariants, as on the Mac.
/// Every control is kept here (a WinRT control made in Swift is only a wrapper).
@MainActor
final class SpaceStyleEditorView {
    static let padSide = 340.0
    /// The page shown last (Arc: currentThemeEditorPresetPage) while Cra runs.
    private static var lastPage = 0

    let flyout = Flyout()
    private let card = Border()
    private let column = StackPanel()
    private let pad = Grid()
    private let padFill = Border()
    private let knobs = Canvas()
    private let hint = TextBlock()
    private let appearanceRow = StackPanel()
    private var appearanceButtons: [(value: String, button: Button)] = []
    private let minus = Button()
    private let plus = Button()
    private let swatchRow = StackPanel()
    private let previous = Button()
    private let next = Button()
    private let swatches = StackPanel()
    private var intensity: ThemeSlider!
    private var grain: ThemeSlider!
    private var labels: [TextBlock] = []
    private var icons: [FontIcon] = []
    private var knobViews: [WinUI.Ellipse] = []

    /// Each change, drawn at once (a space's previewTheme, or the Create a Space draft), and the
    /// editor closing.
    private let onChange: @MainActor (SpaceTheme) -> Void
    private let onClose: @MainActor () -> Void
    private var key: [String]
    /// Where + , − and a drag put the second and third colours (Arc's `wheel`, #632).
    private var wheel: SpaceColorWheel.Wheel
    private var appearance: String
    private var page: Int
    /// The knob a press holds (0 is the main colour).
    private var held: Int?

    /// The editor on a space: it wears each change (SidebarStore.previewTheme), which is written
    /// when the editor closes.
    convenience init(store: SidebarStore, space: Space) {
        let id = space.id
        self.init(theme: space.theme) { theme in
            store.previewTheme(theme, forSpace: id)
        } onClose: {
            store.endThemePreview(forSpace: id, keep: true)
        }
    }

    init(theme: SpaceTheme, onChange: @escaping @MainActor (SpaceTheme) -> Void, onClose: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        self.onClose = onClose
        key = SpaceThemeVariants.padKey(of: theme)
        wheel = theme.wheel ?? SpaceColorPresets.wheel(of: key)
        appearance = theme.appearance
        page = SpaceColorPresets.page(of: key) ?? (SpaceColorPresets.pages.indices.contains(Self.lastPage) ? Self.lastPage : 0)

        column.orientation = .vertical
        column.spacing = 14
        column.width = 355
        column.padding = Thickness(left: 7.5, top: 9, right: 7.5, bottom: 16)

        // The pad: a rounded field, the knobs over it, the appearance toggles and − / +.
        pad.width = Self.padSide
        pad.height = Self.padSide
        padFill.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        pad.children.append(padFill)
        hint.text = "Tap to pick a color for this space"
        hint.fontSize = 13
        hint.horizontalAlignment = .center
        hint.verticalAlignment = .center
        hint.isHitTestVisible = false
        pad.children.append(hint)
        knobs.background = UI.clear
        knobs.width = Self.padSide
        knobs.height = Self.padSide
        pad.children.append(knobs)
        knobs.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(self.knobs),
                  (try? self.knobs.capturePointer(args.pointer)) == true else { return }
            args.handled = true
            let at = (x: Double(point.position.x), y: Double(point.position.y))
            self.held = self.knob(at: at)
            self.place(at: at)
        }
        knobs.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.held != nil, let args, let point = try? args.getCurrentPoint(self.knobs) else { return }
            args.handled = true
            self.place(at: (Double(point.position.x), Double(point.position.y)))
        }
        knobs.pointerReleased.addHandler { [weak self] _, args in
            args?.handled = true
            self?.held = nil
        }
        knobs.pointerCaptureLost.addHandler { [weak self] _, _ in self?.held = nil }

        appearanceRow.orientation = .horizontal
        appearanceRow.spacing = 7.5
        appearanceRow.horizontalAlignment = .center
        appearanceRow.verticalAlignment = .top
        appearanceRow.margin = Thickness(left: 0, top: 24, right: 0, bottom: 0)
        for (value, glyph, name) in [("auto", "", "Auto"), ("light", "\u{E706}", "Light"), ("dark", "\u{E708}", "Dark")] {
            let content: UIElement
            if glyph.isEmpty { content = label("A", size: 13) } else { content = icon(glyph) }
            let b = UI.button(content, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
                self?.appearance = value
                self?.changed()
            }
            b.width = 32
            b.height = 32
            b.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
            try? ToolTipService.setToolTip(b, name)
            try? AutomationProperties.setName(b, name)
            appearanceButtons.append((value, b))
            appearanceRow.children.append(b)
        }
        pad.children.append(appearanceRow)

        let padButtons = StackPanel()
        padButtons.orientation = .horizontal
        padButtons.spacing = 16
        padButtons.horizontalAlignment = .center
        padButtons.verticalAlignment = .bottom
        padButtons.margin = Thickness(left: 0, top: 0, right: 0, bottom: 20)
        for (b, glyph, name) in [(minus, "\u{E738}", "Remove a color"), (plus, "\u{E710}", "Add a color")] {
            b.content = icon(glyph)
            b.background = UI.clear
            b.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            try? AutomationProperties.setName(b, name)
            padButtons.children.append(b)
        }
        // − takes the last colour too: an empty pad is Arc's colourless theme (#300).
        minus.click.addHandler { [weak self] _, _ in
            guard let self, SpaceColorWheel.canRemove(self.key.count) else { return }
            self.key = SpaceColorWheel.removing(from: self.key, wheel: self.wheel)
            self.changed()
        }
        plus.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            (self.key, self.wheel) = SpaceColorWheel.adding(to: self.key, wheel: self.wheel)
            self.changed()
        }
        pad.children.append(padButtons)
        column.children.append(pad)

        // Nine swatches between the paging arrows.
        swatchRow.orientation = .horizontal
        swatchRow.horizontalAlignment = .center
        swatches.orientation = .horizontal
        swatches.spacing = 5.5
        swatches.verticalAlignment = .center
        for (b, glyph, name, step) in [(previous, "\u{E76B}", "Move to previous preset page.", -1), (next, "\u{E76C}", "Move to next preset page.", 1)] {
            b.content = icon(glyph, size: 13)
            b.background = UI.clear
            b.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
            b.width = 36
            try? AutomationProperties.setName(b, name)
            b.click.addHandler { [weak self] _, _ in self?.turnPage(by: step) }
        }
        swatchRow.children.append(previous)
        swatchRow.children.append(swatches)
        swatchRow.children.append(next)
        column.children.append(swatchRow)

        // The intensity and the grain.
        intensity = ThemeSlider(value: theme.intensity) { [weak self] in self?.changed() }
        grain = ThemeSlider(value: theme.noise) { [weak self] in self?.changed() }
        for (slider, name) in [(intensity!, "Intensity"), (grain!, "Grain")] {
            let row = Grid()
            row.columnDefinitions.append(UI.column(UI.pixels(70)))
            row.columnDefinitions.append(UI.column(UI.star))
            let title = label(name, size: 12)
            title.verticalAlignment = .center
            row.children.append(title)
            try? AutomationProperties.setName(slider.root, name)
            row.children.append(slider.root)
            try? Grid.setColumn(slider.root, 1)
            row.margin = Thickness(left: 10, top: 0, right: 10, bottom: 0)
            column.children.append(row)
        }

        card.child = column
        card.cornerRadius = CornerRadius(topLeft: 22, topRight: 22, bottomRight: 22, bottomLeft: 22)
        flyout.content = card
        flyout.placement = .rightEdgeAlignedTop
        // A windowed popup: over the page's own window, which XAML inside the island would sit under.
        flyout.shouldConstrainToRootBounds = false
        flyout.closed.addHandler { [weak self] _, _ in self?.onClose() }
        fillSwatches()
        refresh(theme)
    }

    /// Opens beside `anchor` (the sidebar), the editor's card against its edge.
    func show(beside anchor: FrameworkElement) {
        try? flyout.showAt(anchor)
    }

    // MARK: Changes

    /// The pad's state as a theme (SpaceThemeVariants), shown in the space at once.
    private func changed() {
        let theme = SpaceThemeVariants.theme(key: key, intensity: intensity.value, noise: grain.value, appearance: appearance,
                                             wheel: wheel)
        onChange(theme)
        refresh(theme)
    }

    /// Knob `held` goes under the pointer; the others keep their places round it
    /// (SpaceColorWheel.placed).
    private func place(at p: (x: Double, y: Double)) {
        let c = Self.padSide / 2
        let pick = SpaceColorWheel.padPick(dx: p.x - c, dy: p.y - c)
        key = SpaceColorWheel.placed(key, handle: held ?? 0, hue: pick.hue, saturation: pick.saturation, wheel: wheel)
        changed()
    }

    /// The knob under a press, else the main one (Arc: a press anywhere brings it there).
    private func knob(at p: (x: Double, y: Double)) -> Int {
        let c = Self.padSide / 2
        for (i, hex) in key.prefix(3).enumerated().reversed() {
            let o = SpaceColorWheel.padOffset(of: hex)
            let r = i == 0 ? 22.0 : 13.5
            let dx = p.x - (c + o.dx), dy = p.y - (c + o.dy)
            if dx * dx + dy * dy <= r * r { return i }
        }
        return 0
    }

    private func turnPage(by step: Int) {
        let to = page + step
        guard SpaceColorPresets.pages.indices.contains(to) else { return }
        page = to
        Self.lastPage = to
        fillSwatches()
    }

    // MARK: Drawing

    /// Arc's card: the space's colour darkened ~58% on Dark, a near-white tint of it on Light, the
    /// controls white or black on it (#455). Auto follows Windows' app mode.
    private func refresh(_ theme: SpaceTheme) {
        let light = SpaceTheme.isLight(appearance, systemDark: WinAppearance.isDark)
        let base = HexColor.components(theme.colors.first ?? "#1C242B") ?? (0.11, 0.14, 0.17)
        func mix(_ v: Double, _ to: Double, _ t: Double) -> UInt8 { UInt8(((v * (1 - t) + to * t) * 255).rounded()) }
        let (to, t) = light ? (1.0, 0.92) : (0.0, 0.58)
        card.background = UI.brush(mix(base.r, to, t), mix(base.g, to, t), mix(base.b, to, t))
        let rgb: UInt8 = light ? 0 : 255
        func ink(_ alpha: Double) -> Brush { UI.brush(rgb, rgb, rgb, alpha: UInt8(alpha * 255)) }
        padFill.background = ink(0.04)
        hint.foreground = ink(0.85)
        hint.visibility = key.isEmpty ? .visible : .collapsed
        for t in labels { t.foreground = ink(0.85) }
        for i in icons { i.foreground = ink(0.75) }
        for (value, b) in appearanceButtons { b.background = value == appearance ? ink(0.12) : UI.clear }
        for slider in [intensity, grain] { slider?.apply(track: ink(0.15), fill: ink(0.6)) }
        minus.isEnabled = SpaceColorWheel.canRemove(key.count)
        plus.isEnabled = SpaceColorWheel.canAdd(key)
        minus.opacity = minus.isEnabled ? 1 : 0.3
        plus.opacity = plus.isEnabled ? 1 : 0.3
        drawKnobs()
    }

    private func drawKnobs() {
        knobs.children.clear()
        knobViews = []
        let c = Self.padSide / 2
        for (i, hex) in key.prefix(3).enumerated() {
            let side = i == 0 ? 44.0 : 27.0
            let k = WinUI.Ellipse()
            k.width = side
            k.height = side
            k.fill = UI.brush(hex)
            k.stroke = UI.brush(255, 255, 255)
            k.strokeThickness = i == 0 ? 4.5 : 2.5
            k.isHitTestVisible = false
            let o = SpaceColorWheel.padOffset(of: hex)
            try? Canvas.setLeft(k, c + o.dx - side / 2)
            try? Canvas.setTop(k, c + o.dy - side / 2)
            knobViews.append(k)
            knobs.children.append(k)
        }
    }

    private func fillSwatches() {
        swatches.children.clear()
        let page = SpaceColorPresets.pages[self.page]
        for (i, colors) in page.swatches.enumerated() {
            let dot = WinUI.Ellipse()
            dot.width = 24
            dot.height = 24
            dot.fill = Self.gradient(colors)
            let b = UI.button(dot, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
                // A page-2 swatch is three colours on the analogous wheel, any other one colour
                // that + takes across the wheel (#632).
                self?.key = colors
                self?.wheel = page.wheel
                self?.changed()
            }
            b.cornerRadius = CornerRadius(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
            // Arc: "Set space color to Catalog color: … ColorPickerBrandN".
            try? AutomationProperties.setName(b, "Set space color to \(page.name(i))")
            swatches.children.append(b)
        }
        previous.isEnabled = self.page > 0
        next.isEnabled = self.page < SpaceColorPresets.pages.count - 1
        previous.opacity = previous.isEnabled ? 1 : 0.35
        next.opacity = next.isEnabled ? 1 : 0.35
    }

    /// A swatch's colours top left to bottom right.
    private static func gradient(_ colors: [String]) -> Brush {
        guard colors.count > 1 else { return UI.brush(colors.first ?? "#808080") }
        let brush = LinearGradientBrush()
        for (i, hex) in colors.enumerated() {
            let stop = GradientStop()
            stop.color = (UI.brush(hex)).color
            stop.offset = Double(i) / Double(colors.count - 1)
            brush.gradientStops.append(stop)
        }
        return brush
    }

    private func label(_ text: String, size: Double) -> TextBlock {
        let t = UI.text(text, size: size, trimmed: false)
        labels.append(t)
        return t
    }

    private func icon(_ glyph: String, size: Double = 15) -> FontIcon {
        let i = FontIcon()
        i.glyph = glyph
        i.fontSize = size
        icons.append(i)
        return i
    }
}
