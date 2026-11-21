import CraCore
import Foundation
import UWP
import WinAppSDK
import WindowsFoundation
import WinUI

/// Dia's "back to the open tab" pill (the Mac's SidebarJumpPill, its geometry in CraCore's
/// JumpPillLayout): while the selected tab's row is scrolled out of the list, a dark capsule with
/// its favicon (a split's, up to three) and an arrow pointing at it sits 7 DIPs inside that edge
/// of the list. A click scrolls the row to the list's middle.
@MainActor
final class SidebarJumpPill {
    let body = Border()
    private let content = StackPanel()
    private let arrow = FontIcon()
    /// The rings round a split's further favicons, drawn in the pill's fill.
    private var rings: [Border] = []
    private(set) var edge: JumpPillLayout.Edge?
    /// What the favicons show: each key and whether its icon had loaded.
    private var shown: [String] = []
    private var hovering = false
    var onClick: () -> Void = {}

    init() {
        let radius = Double(JumpPillLayout.height) / 2
        body.height = Double(JumpPillLayout.height)
        body.cornerRadius = CornerRadius(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
        body.borderThickness = Thickness(left: 0.5, top: 0.5, right: 0.5, bottom: 0.5)
        body.borderBrush = UI.brush(0, 0, 0, alpha: 115)
        let padding = Double(JumpPillLayout.padding) - 0.5
        body.padding = Thickness(left: padding, top: 0, right: padding, bottom: 0)
        body.horizontalAlignment = .center
        body.visibility = .collapsed
        content.orientation = .horizontal
        content.verticalAlignment = .center
        arrow.fontSize = 9
        arrow.width = Double(JumpPillLayout.arrowWidth)
        arrow.margin = Thickness(left: Double(JumpPillLayout.gap), top: 0, right: 0, bottom: 0)
        arrow.foreground = Self.brush(JumpPillLayout.arrowColor)
        body.child = content
        refreshFill()
        body.pointerEntered.addHandler { [weak self] _, _ in self?.setHovering(true) }
        body.pointerExited.addHandler { [weak self] _, _ in self?.setHovering(false) }
        body.pointerPressed.addHandler { _, args in args?.handled = true }
        body.pointerReleased.addHandler { [weak self] _, args in
            args?.handled = true
            self?.onClick()
        }
        try? ToolTipService.setToolTip(body, "Scroll to the open tab")
    }

    /// Shows the pill at `edge` with these tabs' favicons, or hides it (nil).
    func show(edge newEdge: JumpPillLayout.Edge?, keys: [String?], favicons: Favicons) {
        if let newEdge {
            let signature = keys.prefix(JumpPillLayout.maxIcons).map { "\($0 ?? "-")|\(favicons.bitmap(forKey: $0, onDark: true) != nil)" }
            if signature != shown { setIcons(keys, favicons: favicons, signature: signature) }
            arrow.glyph = newEdge == .top ? "\u{E74A}" : "\u{E74B}"  // Up, Down
            let inset = Double(JumpPillLayout.inset)
            body.verticalAlignment = newEdge == .top ? .top : .bottom
            body.margin = newEdge == .top
                ? Thickness(left: 0, top: inset, right: 0, bottom: 0)
                : Thickness(left: 0, top: 0, right: 0, bottom: inset)
        }
        guard newEdge != edge else { return }
        edge = newEdge
        body.visibility = newEdge == nil ? .collapsed : .visible
        if newEdge == nil { setHovering(false) }
    }

    private func setIcons(_ keys: [String?], favicons: Favicons, signature: [String]) {
        content.children.clear()
        rings = []
        let size = Double(JumpPillLayout.icon)
        for (i, key) in keys.prefix(JumpPillLayout.maxIcons).enumerated() {
            let icon: FrameworkElement
            if let bitmap = favicons.bitmap(forKey: key, onDark: true) {
                icon = UI.image(bitmap, size: size)
            } else {
                // The globe, white at half strength on the dark pill (Dia's mono glyphs flip).
                let globe = FontIcon()
                globe.glyph = WinGlyph.code("globe")
                globe.fontSize = 13
                globe.width = size
                globe.height = size
                globe.foreground = UI.brush(255, 255, 255, alpha: 128)
                icon = globe
            }
            guard i > 0 else {
                content.children.append(icon)
                continue
            }
            // Each further favicon overlaps the one before, ringed in the pill's fill.
            let ring = Border()
            ring.borderThickness = Thickness(left: 1.5, top: 1.5, right: 1.5, bottom: 1.5)
            ring.cornerRadius = CornerRadius(topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4)
            ring.margin = Thickness(left: -Double(JumpPillLayout.overlap) - 1.5, top: -1.5, right: -1.5, bottom: -1.5)
            ring.child = icon
            rings.append(ring)
            content.children.append(ring)
        }
        content.children.append(arrow)
        shown = signature
        refreshFill()
    }

    private func setHovering(_ on: Bool) {
        guard on != hovering else { return }
        hovering = on
        refreshFill()
    }

    private func refreshFill() {
        let fill = Self.brush(hovering ? JumpPillLayout.fillHovered : JumpPillLayout.fill)
        body.background = fill
        for ring in rings {
            ring.borderBrush = fill
            ring.background = fill
        }
    }

    private static func brush(_ rgb: UInt32) -> SolidColorBrush {
        UI.brush(UInt8((rgb >> 16) & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8(rgb & 0xFF))
    }
}

extension SidebarView {
    /// The selected tab's row (its split's, when it's in one) and the tabs whose favicons stand
    /// for it. A tab inside a closed folder that isn't listed under it has the folder stand in.
    private func jumpPillRow() -> (element: FrameworkElement, tabs: [UUID])? {
        guard let tab = store.selectedTabID(window: windowID) else { return nil }
        if let split = store.splitContaining(tab) {
            guard let meta = rowMeta.first(where: { $0.itemID == split.id }) else { return nil }
            return (meta.element, store.children(of: split.id).filter(\.isTab).map(\.id))
        }
        if let meta = rowMeta.first(where: { $0.itemID == tab }) { return (meta.element, [tab]) }
        var parent = store.item(tab)?.parentID
        while let p = parent {
            if let row = folderRow(p) { return (row, [tab]) }
            parent = store.item(p)?.parentID
        }
        return nil
    }

    /// The row's top and bottom in the list's own coordinates; nil before it has been laid out.
    private func listSpan(of element: FrameworkElement) -> (top: Double, bottom: Double)? {
        guard element.actualHeight > 0, let t = try? element.transformToVisual(list),
              let o = try? t.transformPoint(WindowsFoundation.Point(x: 0, y: 0)) else { return nil }
        return (Double(o.y), Double(o.y) + element.actualHeight)
    }

    /// Dia's TabOverflowGeometryTracker: the pill shows while the selected row is wholly past an
    /// edge of the visible list, at that edge. Runs on a scroll, a resize and once the selected
    /// row of a new build has its size.
    func updateJumpPill() {
        guard let (element, tabs) = jumpPillRow() else {
            jumpPill.show(edge: nil, keys: [], favicons: favicons)
            return
        }
        guard let span = listSpan(of: element) else { return }
        let top = scroll.verticalOffset
        let edge = JumpPillLayout.edge(rowTop: CGFloat(span.top), rowBottom: CGFloat(span.bottom),
                                       visibleTop: CGFloat(top), visibleBottom: CGFloat(top + scroll.viewportHeight))
        jumpPill.show(edge: edge, keys: tabs.map { store.item($0)?.tab?.iconKey }, favicons: favicons)
    }

    /// After a build: the selected row is new and has no size yet, so the pill waits for it.
    func watchJumpPillRow() {
        guard let (element, _) = jumpPillRow() else {
            updateJumpPill()
            return
        }
        element.sizeChanged.addHandler { [weak self] _, _ in self?.updateJumpPill() }
        updateJumpPill()
    }

    /// The pill's click: the selected row's middle to the list's middle.
    func jumpToSelectedRow() {
        guard let (element, _) = jumpPillRow(), let span = listSpan(of: element) else { return }
        let y = JumpPillLayout.scrollTarget(rowTop: CGFloat(span.top), rowBottom: CGFloat(span.bottom),
                                            visibleHeight: CGFloat(scroll.viewportHeight), contentHeight: CGFloat(scroll.extentHeight))
        _ = try? scroll.changeView(nil, Double(y), nil, false)
    }
}
