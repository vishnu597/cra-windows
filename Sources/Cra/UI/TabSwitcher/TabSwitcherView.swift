import AppKit
import SwiftUI

/// Arc 1.170's tab switcher measurements, shared with Windows (CraCore's TabSwitcherLayout).
typealias TabSwitcherMetrics = TabSwitcherLayout

/// The switcher panel: a dark rounded slab of cards, each a page thumbnail over its favicon
/// and title, the selected one on the space's highlight.
@MainActor
final class TabSwitcherView: NSView {
    private typealias M = TabSwitcherMetrics
    private let switcher: TabSwitcher
    private let favicons: FaviconCache
    private let panel = NSView()
    private let innerLine = CALayer()
    private var cards: [TabSwitcherCardView] = []

    init(switcher: TabSwitcher, favicons: FaviconCache) {
        self.switcher = switcher
        self.favicons = favicons
        super.init(frame: .zero)
        wantsLayer = true
        panel.wantsLayer = true
        if let l = panel.layer {
            l.cornerRadius = M.cornerRadius
            l.cornerCurve = .continuous
            l.borderWidth = 1
            l.shadowColor = NSColor.black.cgColor
            l.shadowRadius = 24
            l.shadowOffset = CGSize(width: 0, height: -10)
            innerLine.borderWidth = 1
            innerLine.cornerRadius = M.cornerRadius - 1
            innerLine.cornerCurve = .continuous
            l.addSublayer(innerLine)
        }
        addSubview(panel)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func observe() {
        let (items, selected, dark, highlight) = withObservationTracking {
            (switcher.items, switcher.selectedIndex, switcher.isDark, switcher.highlight)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if let l = panel.layer {
            // Arc: #1C1B1A inside a near-black outer line and a 23% white inner line.
            l.backgroundColor = (dark ? NSColor(red: 28 / 255, green: 27 / 255, blue: 26 / 255, alpha: 1) : NSColor(white: 0.97, alpha: 1)).cgColor
            l.borderColor = NSColor.black.withAlphaComponent(dark ? 0.92 : 0.12).cgColor
            l.shadowOpacity = dark ? 0.3 : 0.18
            innerLine.borderColor = NSColor.white.withAlphaComponent(dark ? 0.23 : 0.8).cgColor
        }
        while cards.count < items.count {
            let c = TabSwitcherCardView()
            c.onHover = { [weak self, weak c] in
                guard let self, let c, let i = self.cards.firstIndex(where: { $0 === c }) else { return }
                self.switcher.hover(i)
            }
            c.onClick = { [weak self, weak c] in
                guard let self, let c, let i = self.cards.firstIndex(where: { $0 === c }) else { return }
                self.switcher.click(i)
            }
            cards.append(c)
            panel.addSubview(c)
        }
        while cards.count > items.count { cards.removeLast().removeFromSuperview() }
        let fill = NSColor(highlight)
        let showsIcons = switcher.palette != nil
        let look: (String?) -> TabSwitcherCardView.Icon = { [favicons] key in
            let icon = key.flatMap { favicons.image(forKey: $0) }
            let flip = icon != nil && favicons.glyphIsDark(forKey: key) == dark
            return TabSwitcherCardView.Icon(image: showsIcons ? icon : nil, flip: flip)
        }
        for (i, (c, item)) in zip(cards, items).enumerated() {
            c.show(item, icon: look(item.iconKey), paneIcons: item.panes.map { look($0.iconKey) }, selected: i == selected, highlight: fill, dark: dark)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let p = bounds.insetBy(dx: M.shadowMargin, dy: M.shadowMargin)
        panel.frame = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        innerLine.frame = panel.bounds.insetBy(dx: 1, dy: 1)
        CATransaction.commit()
        for (i, c) in cards.enumerated() {
            c.frame = NSRect(x: M.paddingH + CGFloat(i) * (M.card.width + M.cardSpacing), y: M.paddingV,
                             width: M.card.width, height: M.card.height)
        }
    }
}

private final class TabSwitcherCardView: NSView {
    private typealias M = TabSwitcherMetrics
    struct Icon {
        var image: NSImage?
        /// A dark glyph on a dark switcher (or light on light): drawn as a template in the ink.
        var flip: Bool
    }
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}
    private let lift = CALayer()
    private let thumb = CALayer()
    private let favicon = NSImageView()
    private let placeholder = NSView()
    private let title = NSTextField.sidebarLabel(size: 14, weight: .medium)
    /// ⌃⌥Tab's space name over the thumbnail's corner, in the pill of Arc's hover tooltips.
    private let spacePill = NSView()
    private let spaceIcon = NSImageView()
    private let spaceTitle = NSTextField.sidebarLabel(size: 11, weight: .medium)
    /// A split's panes (#554): a thumbnail each inside the frame, a favicon each under it.
    private var paneThumbs: [CALayer] = []
    private var paneIcons: [(icon: NSImageView, placeholder: NSView)] = []
    private var paneWidths: [CGFloat] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = M.cardCornerRadius
        layer?.cornerCurve = .continuous
        lift.shadowColor = NSColor.black.cgColor
        lift.shadowRadius = 7
        lift.shadowOffset = CGSize(width: 0, height: -3)
        lift.cornerRadius = M.thumbnailCornerRadius
        lift.cornerCurve = .continuous
        thumb.cornerRadius = M.thumbnailCornerRadius
        thumb.cornerCurve = .continuous
        thumb.masksToBounds = true
        thumb.contentsGravity = .resizeAspectFill
        lift.addSublayer(thumb)
        layer?.addSublayer(lift)
        Self.styleIcon(favicon, placeholder: placeholder)
        addSubview(favicon)
        addSubview(placeholder)
        addSubview(title)
        spacePill.wantsLayer = true
        spacePill.layer?.cornerRadius = 6
        spacePill.layer?.cornerCurve = .continuous
        spaceIcon.imageScaling = .scaleProportionallyUpOrDown
        spaceTitle.lineBreakMode = .byTruncatingTail
        spacePill.addSubview(spaceIcon)
        spacePill.addSubview(spaceTitle)
        addSubview(spacePill)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ item: TabSwitcher.Item, icon: Icon, paneIcons icons: [Icon], selected: Bool, highlight: NSColor, dark: Bool) {
        let split = !item.panes.isEmpty
        let scale = window?.backingScaleFactor ?? 2
        // A tab never seen since launch: Arc shows an empty #1C1C1C card.
        let empty = (dark ? NSColor(white: 28 / 255, alpha: 1) : NSColor(white: 0.9, alpha: 1)).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = selected ? highlight.cgColor : nil
        lift.shadowOpacity = dark ? 0.4 : 0.15
        if split {
            // Arc's split frame measured #161616 on the dark switcher, selected or not.
            thumb.contents = nil
            thumb.backgroundColor = (dark ? NSColor(white: 22 / 255, alpha: 1) : NSColor(white: 0.82, alpha: 1)).cgColor
        } else if let image = item.snapshot {
            thumb.contents = image.layerContents(forContentsScale: scale)
            thumb.backgroundColor = nil
        } else {
            thumb.contents = nil
            thumb.backgroundColor = empty
        }
        while paneThumbs.count < item.panes.count {
            let l = CALayer()
            l.cornerRadius = M.paneCornerRadius
            l.cornerCurve = .continuous
            l.masksToBounds = true
            l.contentsGravity = .resizeAspectFill
            thumb.addSublayer(l)
            paneThumbs.append(l)
        }
        while paneThumbs.count > item.panes.count { paneThumbs.removeLast().removeFromSuperlayer() }
        for (l, pane) in zip(paneThumbs, item.panes) {
            l.contents = pane.snapshot?.layerContents(forContentsScale: scale)
            l.backgroundColor = pane.snapshot == nil ? empty : nil
        }
        CATransaction.commit()
        paneWidths = item.panes.map(\.width)
        while paneIcons.count < item.panes.count {
            let (i, p) = (NSImageView(), NSView())
            Self.styleIcon(i, placeholder: p)
            addSubview(i)
            addSubview(p)
            paneIcons.append((i, p))
        }
        while paneIcons.count > item.panes.count {
            let last = paneIcons.removeLast()
            last.icon.removeFromSuperview()
            last.placeholder.removeFromSuperview()
        }
        for (views, look) in zip(paneIcons, icons) { Self.apply(look, to: views.icon, placeholder: views.placeholder, dark: dark) }
        // A split's row is only its panes' favicons, no title (Arc).
        title.isHidden = split
        if split {
            favicon.isHidden = true
            placeholder.isHidden = true
        } else {
            Self.apply(icon, to: favicon, placeholder: placeholder, dark: dark)
        }
        // Arc's titles measure as SF 14 medium (ink width and cap height match).
        title.stringValue = item.title
        title.textColor = dark ? .white : NSColor.black.withAlphaComponent(0.85)
        spacePill.isHidden = item.space == nil
        if let space = item.space {
            let ink = dark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.85)
            spacePill.layer?.backgroundColor = (dark ? NSColor(white: 0.1, alpha: 0.85) : NSColor(white: 1, alpha: 0.9)).cgColor
            spaceIcon.image = space.icon
            spaceIcon.isHidden = space.icon == nil
            spaceIcon.contentTintColor = ink
            spaceTitle.stringValue = space.title
            spaceTitle.textColor = ink
        }
        needsLayout = true
    }

    private static func styleIcon(_ icon: NSImageView, placeholder: NSView) {
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = M.favicon * 0.22
        icon.layer?.cornerCurve = .continuous
        icon.layer?.masksToBounds = true
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = 4.5
        placeholder.layer?.cornerCurve = .continuous
    }

    /// Arc's switcher draws a missing favicon as a faint rounded square, not a globe.
    private static func apply(_ look: Icon, to view: NSImageView, placeholder: NSView, dark: Bool) {
        if let icon = look.image {
            view.isHidden = false
            placeholder.isHidden = true
            if look.flip {
                let t = icon.copy() as! NSImage
                t.isTemplate = true
                view.image = t
                view.contentTintColor = dark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.85)
            } else {
                view.image = icon
                view.contentTintColor = nil
            }
        } else {
            view.isHidden = true
            placeholder.isHidden = false
            placeholder.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.1)).cgColor
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lift.frame = NSRect(x: M.thumbnailOrigin.x, y: h - M.thumbnailOrigin.y - M.thumbnail.height,
                              width: M.thumbnail.width, height: M.thumbnail.height)
        lift.shadowPath = CGPath(roundedRect: lift.bounds, cornerWidth: M.thumbnailCornerRadius, cornerHeight: M.thumbnailCornerRadius, transform: nil)
        thumb.frame = lift.bounds
        let panes = SwitcherSplitLayout.paneFrames(in: M.thumbnail, widths: paneWidths)
        for (l, f) in zip(paneThumbs, panes) {
            l.frame = CGRect(x: f.minX, y: M.thumbnail.height - f.maxY, width: f.width, height: f.height)
        }
        CATransaction.commit()
        // The title row fills what is left under the thumbnail, centred.
        let rowTop = M.thumbnailOrigin.y + M.thumbnail.height
        let mid = h - (rowTop + (h - rowTop) / 2)
        let f = NSRect(x: 13.5, y: mid - M.favicon / 2, width: M.favicon, height: M.favicon)
        favicon.frame = f
        placeholder.frame = f
        // Under a split, each pane's favicon centred under its thumbnail.
        for (views, p) in zip(paneIcons, panes) {
            let r = NSRect(x: M.thumbnailOrigin.x + p.midX - M.favicon / 2, y: f.minY, width: M.favicon, height: M.favicon)
            views.icon.frame = r
            views.placeholder.frame = r
        }
        let tx = 13.5 + M.favicon + 8
        title.frame = NSRect(x: tx - SidebarText.inset, y: mid - 17 / 2, width: bounds.width - tx - 10.5 + 2 * SidebarText.inset, height: 17)
        if !spacePill.isHidden {
            let pad: CGFloat = 6, icon: CGFloat = spaceIcon.isHidden ? 0 : 12, gap: CGFloat = spaceIcon.isHidden ? 0 : 4
            let maxText = M.thumbnail.width - 2 * pad - 2 * 7 - icon - gap
            let measured = (spaceTitle.stringValue as NSString).size(withAttributes: [.font: spaceTitle.font ?? .systemFont(ofSize: 11, weight: .medium)]).width
            let text = min(ceil(measured) + 1, maxText)
            let size = NSSize(width: 7 + icon + gap + text + 7, height: 20)
            spacePill.frame = NSRect(x: M.thumbnailOrigin.x + pad, y: h - M.thumbnailOrigin.y - pad - size.height, width: size.width, height: size.height)
            spaceIcon.frame = NSRect(x: 7, y: (size.height - icon) / 2, width: icon, height: icon)
            spaceTitle.frame = NSRect(x: 7 + icon + gap - SidebarText.inset, y: (size.height - 14) / 2, width: text + 2 * SidebarText.inset, height: 14)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseMoved(with event: NSEvent) { onHover() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

extension SpaceTheme {
    /// The selected card: Arc's semantic "hover" colour. In Arc's own data (JYSK and Victor
    /// spaces) the dark one sits at OKLab lightness ≈ 0.60 in the theme's hue, close to the
    /// most saturated colour sRGB has there, at 48% opacity; the light one is opaque at ≈ 0.885.
    func switcherHighlight(dark: Bool) -> Color {
        let c = switcherHighlightRGBA(dark: dark)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    /// Arc's developer-mode toolbar (CraCore's SpaceTheme.developerBar, which has the measurements).
    var developerBarColor: NSColor { NSColor(developerBar) }

    /// Arc's foregroundSecondary: the developer bar's dividers at 45%, its selected text at 60%.
    var developerSecondaryColor: NSColor { NSColor(developerSecondary) }
}
