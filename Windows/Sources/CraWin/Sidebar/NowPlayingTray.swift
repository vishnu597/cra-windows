import CraCore
import Foundation
import UWP
import WinUI

/// Arc's "now playing" player over the bottom of the tab list (issue #33, the Mac's
/// NowPlayingTray): a card for each tab that played sound and isn't on screen (NowPlayingList).
/// At rest only the newest card shows, 33 DIPs tall: the favicon (Back to Tab), previous,
/// play/pause and next. The pointer over it opens every card, oldest on top, 5 apart, each with
/// the tab's title, Picture in Picture for a video and ✕. Cards are 6 DIP rounded, in Arc's
/// `backgroundExtra` (a deep shade on dark spaces, near-white on light ones); glyphs are white
/// 66 % or black 50 %, a third of that when unavailable. Stock CEF reports no media session, so
/// previous and next are always unavailable, as on the Mac for a page without track handlers.
/// Left: Arc's volume drawer.
@MainActor
final class NowPlayingTray {
    struct Card: Equatable {
        let id: UUID
        let title: String
        let iconKey: String?
        let playing: Bool
        let hasVideo: Bool
    }

    /// Over the bottom of the tab list.
    let root = StackPanel()
    var onShowTab: (UUID) -> Void = { _ in }
    var onTogglePlayback: (UUID) -> Void = { _ in }
    var onPictureInPicture: (UUID) -> Void = { _ in }
    var onDismiss: (UUID) -> Void = { _ in }
    /// The room the resting player takes from the bottom of the tab list (0 with no card).
    var onRestingHeight: (Double) -> Void = { _ in }

    static let controlsHeight = 33.0
    static let titleHeight = 32.5
    static let gap = 5.0

    private let favicons: Favicons
    private var cards: [Card] = []
    private var dark = false
    private var expanded = false
    /// Each card's title row, and the cards behind the front one: shown while the player is open.
    private var titleRows: [FrameworkElement] = []
    private var backCards: [FrameworkElement] = []
    /// A WinRT control made in Swift is only a wrapper, freed once Swift lets go of it.
    private var kept: [AnyObject] = []

    init(favicons: Favicons = .shared) {
        self.favicons = favicons
        root.orientation = .vertical
        root.spacing = Self.gap
        root.verticalAlignment = .bottom
        root.margin = Thickness(left: 0, top: 0, right: 0, bottom: 6)
        root.visibility = .collapsed
        // A clear fill, so the gaps between open cards keep the pointer over the player.
        root.background = UI.clear
        root.pointerEntered.addHandler { [weak self] _, _ in self?.setExpanded(true) }
        root.pointerExited.addHandler { [weak self] _, _ in self?.setExpanded(false) }
    }

    /// Draws `cards` (oldest first) in the space's colours; nothing changes, nothing is redrawn.
    func show(_ cards: [Card], dark: Bool) {
        guard cards != self.cards || dark != self.dark else { return }
        self.cards = cards
        self.dark = dark
        root.children.clear()
        titleRows = []
        backCards = []
        kept = []
        if cards.isEmpty { expanded = false }
        for (i, card) in cards.enumerated() {
            let view = makeCard(card)
            if i < cards.count - 1 { backCards.append(view) }
            root.children.append(view)
        }
        root.visibility = cards.isEmpty ? .collapsed : .visible
        applyExpanded()
        onRestingHeight(cards.isEmpty ? 0 : Self.controlsHeight + root.margin.bottom + Self.gap)
    }

    private func setExpanded(_ open: Bool) {
        guard open != expanded, !cards.isEmpty || !open else { return }
        expanded = open
        applyExpanded()
    }

    private func applyExpanded() {
        for row in titleRows { row.visibility = expanded ? .visible : .collapsed }
        for card in backCards { card.visibility = expanded ? .visible : .collapsed }
    }

    // MARK: A card

    private var fill: Brush { dark ? UI.brush(0, 0, 0, alpha: 46) : UI.brush(255, 255, 255, alpha: 222) }
    private var ink: Brush { dark ? UI.brush(255, 255, 255, alpha: 168) : UI.brush(0, 0, 0, alpha: 128) }
    private var faintInk: Brush { dark ? UI.brush(255, 255, 255, alpha: 56) : UI.brush(0, 0, 0, alpha: 43) }

    private func makeCard(_ card: Card) -> FrameworkElement {
        let id = card.id
        let border = Border()
        border.background = fill
        border.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        let stack = StackPanel()
        stack.orientation = .vertical
        border.child = stack

        // The title row: the page's own title (a click goes back to the tab), PiP for a video, ✕.
        let title = Grid()
        title.height = Self.titleHeight
        title.columnDefinitions.append(UI.column(UI.star))
        title.columnDefinitions.append(UI.column(UI.auto))
        title.columnDefinitions.append(UI.column(UI.auto))
        let name = UI.text(card.title, size: 13, color: dark ? UI.brush(255, 255, 255, alpha: 235) : UI.brush(0, 0, 0, alpha: 217))
        name.verticalAlignment = .center
        let nameButton = UI.button(name, padding: Thickness(left: 6, top: 2, right: 6, bottom: 2)) { [weak self] in self?.onShowTab(id) }
        nameButton.horizontalAlignment = .stretch
        nameButton.horizontalContentAlignment = .left
        nameButton.margin = Thickness(left: 8, top: 4, right: 0, bottom: 0)
        title.children.append(nameButton)
        if card.hasVideo {
            let pip = glyphButton("\u{E8A7}", size: 12, help: "Open Picture in Picture") { [weak self] in self?.onPictureInPicture(id) }
            title.children.append(pip)
            try? Grid.setColumn(pip, 1)
        }
        let close = glyphButton("\u{E711}", size: 12, help: "Close Mini Player") { [weak self] in self?.onDismiss(id) }
        close.margin = Thickness(left: 0, top: 4, right: 6, bottom: 0)
        title.children.append(close)
        try? Grid.setColumn(close, 2)
        titleRows.append(title)
        stack.children.append(title)

        // The controls, spread evenly as Arc's HStack.
        let controls = Grid()
        controls.height = Self.controlsHeight
        controls.padding = Thickness(left: 6, top: 0, right: 6, bottom: 0)
        for _ in 0..<4 { controls.columnDefinitions.append(UI.column(UI.star)) }
        let icon = UI.button(favicon(card.iconKey), padding: Thickness(left: 4, top: 4, right: 4, bottom: 4)) { [weak self] in self?.onShowTab(id) }
        try? ToolTipService.setToolTip(icon, "Back to Tab")
        let previous = glyphButton("\u{E892}", size: 13, help: nil, enabled: false) {}
        let play = glyphButton(card.playing ? "\u{E769}" : "\u{E768}", size: 13, help: card.playing ? "Pause" : "Play") { [weak self] in
            self?.onTogglePlayback(id)
        }
        let next = glyphButton("\u{E893}", size: 13, help: nil, enabled: false) {}
        for (i, part) in ([icon, previous, play, next] as [FrameworkElement]).enumerated() {
            part.horizontalAlignment = .center
            part.verticalAlignment = .center
            controls.children.append(part)
            try? Grid.setColumn(part, Int32(i))
        }
        stack.children.append(controls)
        kept.append(contentsOf: [border, stack, title, name, nameButton, close, controls, icon, previous, play, next] as [AnyObject])
        return border
    }

    private func glyphButton(_ glyph: String, size: Double, help: String?, enabled: Bool = true,
                             _ action: @escaping @MainActor () -> Void) -> Button {
        let icon = FontIcon()
        icon.glyph = glyph
        icon.fontSize = size
        icon.foreground = enabled ? ink : faintInk
        let button = UI.button(icon, padding: Thickness(left: 6, top: 5, right: 6, bottom: 5), action)
        button.verticalAlignment = .center
        // Unavailable: no hover, no tooltip (Arc's dimmed track buttons).
        button.isEnabled = enabled
        if let help { try? ToolTipService.setToolTip(button, help) }
        kept.append(icon)
        return button
    }

    private func favicon(_ key: String?) -> FrameworkElement {
        if let bitmap = favicons.bitmap(forKey: key, onDark: dark) { return UI.image(bitmap, size: 16) }
        let globe = FontIcon()
        globe.glyph = WinGlyph.code("globe")
        globe.fontSize = 13
        globe.width = 16
        globe.foreground = ink
        return globe
    }
}
