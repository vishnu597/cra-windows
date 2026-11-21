import CraCore
import Foundation
import UWP
import WinSDK
import WindowsFoundation
import WinUI

/// Arc's Help ▸ Essential Keyboard Shortcuts on Windows (the Mac's EssentialShortcutsWindow): a dark
/// 475 × 462 card at the top right of the screen, "Essential Keyboard Shortcuts" with View All, and
/// Arc's five rows (CraCore EssentialShortcuts) with the user's own keys as blue caps. It stays up
/// behind other windows until closed (✕, Escape or Alt+F4); View All opens Settings ▸ Shortcuts.
@MainActor
final class EssentialShortcutsCard {
    var onViewAll: () -> Void = {}

    private let root = Grid()
    private let rowsPanel = StackPanel()
    /// Takes the keyboard when the card shows, so Escape reaches the card.
    private var viewAll: Button?
    private var window: FloatingWindow?

    private static let background = UI.brush(0x16, 0x1C, 0x2F)
    private static let hairline = UI.brush(0x21, 0x27, 0x39)
    private static let rim = UI.brush(0x2F, 0x6F, 0xE8)
    private static let lip = UI.brush(0x2B, 0x60, 0xC4)
    private static let face = UI.brush(0xE4, 0xEC, 0xF8)

    init() {
        build()
    }

    /// Shows the card over `owner`'s screen, at its top right, with the keys as they are now.
    func show(over owner: HostWindow) {
        render()
        do {
            if window == nil {
                let w = try FloatingWindow(owner: owner, content: root)
                w.onClose = { [weak self] in self?.hide() }
                window = w
            }
        } catch {
            print("The Essential Keyboard Shortcuts card could not be made: \(error)")
            return
        }
        guard let window else { return }
        let scale = owner.scale
        let width = EssentialShortcuts.width * scale, height = EssentialShortcuts.height * scale
        let area = owner.workArea ?? owner.frame
        window.place(origin: PointInt32(x: Int32((area.x + area.width - width - 10 * scale).rounded()),
                                        y: Int32((area.y + 10 * scale).rounded())),
                     size: SizeInt32(width: Int32(width.rounded()), height: Int32(height.rounded())))
        window.show { [weak self] in _ = try? self?.viewAll?.focus(.programmatic) }
    }

    func hide() {
        window?.hide()
    }

    // MARK: Drawing

    private func build() {
        root.background = Self.background
        root.requestedTheme = .dark
        root.padding = Thickness(left: 30, top: 0, right: 30, bottom: 0)
        root.keyDown.addHandler { [weak self] _, args in
            guard let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x1B else { return }  // Escape
            args.handled = true
            self?.hide()
        }
        for height in [UI.pixels(31), UI.pixels(28), UI.star] { root.rowDefinitions.append(UI.row(height)) }

        // The window has no title bar: a ✕ at the top right stands in for the Mac's traffic lights.
        let closeGlyph = FontIcon()
        closeGlyph.glyph = "\u{E711}"  // Cancel
        closeGlyph.fontSize = 10
        closeGlyph.foreground = UI.brush(255, 255, 255, alpha: 150)
        let close = UI.button(closeGlyph, padding: Thickness(left: 8, top: 6, right: 8, bottom: 6)) { [weak self] in self?.hide() }
        close.clickMode = .release
        close.horizontalAlignment = .right
        close.verticalAlignment = .bottom
        close.margin = Thickness(left: 0, top: 0, right: -22, bottom: 0)
        root.children.append(close)

        let header = Grid()
        for width in [UI.star, UI.auto] { header.columnDefinitions.append(UI.column(width)) }
        let title = UI.text("Essential Keyboard Shortcuts", size: 20.5, color: UI.brush(255, 255, 255), trimmed: false)
        title.fontWeight = UWP.FontWeight(weight: 800)
        title.verticalAlignment = .center
        header.children.append(title)
        let viewAllLabel = StackPanel()
        viewAllLabel.orientation = .horizontal
        viewAllLabel.spacing = 8
        viewAllLabel.children.append(UI.text("View All", size: 14, color: UI.brush(255, 255, 255, alpha: 235), trimmed: false))
        let arrow = FontIcon()
        arrow.glyph = "\u{E8A7}"  // OpenInNewWindow
        arrow.fontSize = 11
        arrow.foreground = UI.brush(255, 255, 255, alpha: 235)
        viewAllLabel.children.append(arrow)
        let viewAll = UI.button(viewAllLabel, fill: UI.brush(0x28, 0x2D, 0x3F)) { [weak self] in
            self?.hide()
            self?.onViewAll()
        }
        viewAll.clickMode = .release
        viewAll.width = 96
        viewAll.height = 28
        viewAll.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        viewAll.borderBrush = UI.brush(255, 255, 255, alpha: 26)
        self.viewAll = viewAll
        header.children.append(viewAll)
        try? Grid.setColumn(viewAll, 1)
        root.children.append(header)
        try? Grid.setRow(header, 1)

        rowsPanel.orientation = .vertical
        rowsPanel.margin = Thickness(left: 0, top: 3, right: 0, bottom: 0)
        root.children.append(rowsPanel)
        try? Grid.setRow(rowsPanel, 2)
    }

    /// The rows with the keys Settings ▸ Shortcuts has now.
    private func render() {
        rowsPanel.children.clear()
        for (i, row) in EssentialShortcuts.rows.enumerated() {
            if i > 0 {
                let line = Border()
                line.height = 1
                line.background = Self.hairline
                rowsPanel.children.append(line)
            }
            let grid = Grid()
            grid.height = 72
            for width in [UI.star, UI.auto] { grid.columnDefinitions.append(UI.column(width)) }
            let texts = StackPanel()
            texts.spacing = 2.5
            texts.verticalAlignment = .center
            texts.children.append(UI.text(row.title, size: 15, color: UI.brush(255, 255, 255)))
            texts.children.append(UI.text(row.detail, size: 12, color: UI.brush(255, 255, 255, alpha: 158)))
            grid.children.append(texts)
            let caps = StackPanel()
            caps.orientation = .horizontal
            caps.spacing = 3
            caps.verticalAlignment = .center
            caps.margin = Thickness(left: 12, top: 0, right: 0, bottom: 0)
            for cap in WinKeyBindings.shared.action(row.action)?.primary?.windowsCaps ?? [] { caps.children.append(Self.cap(cap)) }
            grid.children.append(caps)
            try? Grid.setColumn(caps, 1)
            rowsPanel.children.append(grid)
        }
    }

    /// One key cap, as Arc draws it: a light blue face in a blue rim, on a darker blue lip.
    private static func cap(_ text: String) -> UIElement {
        let lipBorder = Border()
        lipBorder.background = lip
        lipBorder.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        lipBorder.padding = Thickness(left: 0, top: 0, right: 0, bottom: 3)
        let rimBorder = Border()
        rimBorder.background = face
        rimBorder.borderBrush = rim
        rimBorder.borderThickness = Thickness(left: 1.5, top: 1.5, right: 1.5, bottom: 1.5)
        rimBorder.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        rimBorder.minWidth = 28
        rimBorder.height = 26
        rimBorder.padding = Thickness(left: 6, top: 0, right: 6, bottom: 0)
        let label = UI.text(text.count > 1 ? text.uppercased() : text, size: text.count > 1 ? 10.5 : 15, color: rim, trimmed: false)
        label.fontWeight = UWP.FontWeight(weight: 700)
        label.horizontalAlignment = .center
        label.verticalAlignment = .center
        rimBorder.child = label
        lipBorder.child = rimBorder
        return lipBorder
    }
}
