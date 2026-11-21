import CraCore
import Foundation
import UWP
import WinAppSDK
import WindowsFoundation
import WinSDK
import WinUI

/// Arc's dialog sheet for a confirmation (the Mac's AppDialog, upstream bc47470, #224): one navy
/// card, 450 DIPs wide, over the middle of its window: the title, the message under it, and the
/// buttons along the bottom, the default one Arc's blue (red to delete) with ↩ on it and Cancel
/// with ESC. Which button Return and Escape press, and the buttons' order, are CraCore's
/// `DialogActions`; their colours `DialogButtonColors`. The card sits in a window of its own over
/// the page (FloatingWindow), as the import card does; the window under it stays usable.
@MainActor
final class AppDialog {
    static let width = 450.0

    let title: String
    let message: String
    let actions: DialogActions
    private let root = Grid()
    private var window: FloatingWindow?
    private weak var owner: HostWindow?
    private var completion: ((Int?) -> Void)?
    /// The buttons' parts, kept: a WinRT control built from Swift is only a wrapper, gone once
    /// nothing in Swift holds it, and its handlers would find nothing.
    private var kept: [AnyObject] = []
    /// The dialog on screen over each window, so a second one doesn't stack on it.
    private static var showing: [ObjectIdentifier: AppDialog] = [:]

    init(title: String, message: String = "", actions: [DialogAction] = [DialogAction("OK")]) {
        self.title = title
        self.message = message
        self.actions = DialogActions(actions)
    }

    /// Shows the card over `owner`; `completion` gets the picked button's index in `actions`, or
    /// nil when it went without one (Alt+F4, or another dialog was already up there).
    func present(over owner: HostWindow, completion: @escaping (Int?) -> Void) {
        let key = ObjectIdentifier(owner)
        guard Self.showing[key] == nil else { return completion(nil) }
        self.owner = owner
        self.completion = completion
        build()
        do {
            let window = try FloatingWindow(owner: owner, content: root)
            window.onClose = { [weak self] in self?.finish(nil) }
            self.window = window
        } catch {
            print("Cra: the dialog's window could not be made: \(error)")
            return completion(nil)
        }
        Self.showing[key] = self
        place()
        window?.show { [weak self] in _ = try? self?.root.focus(.programmatic) }
    }

    /// Picks button `index` as a click on it does.
    func select(_ index: Int) {
        guard actions.buttons.indices.contains(index) else { return }
        finish(index)
    }

    private func finish(_ index: Int?) {
        guard let done = completion else { return }
        completion = nil
        if let owner { Self.showing[ObjectIdentifier(owner)] = nil }
        // After the click's event: the XAML that delivered it goes with the window.
        let window = self.window
        self.window = nil
        _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { window?.destroy() }
        window?.hide()
        kept = []
        done(index)
    }

    private func place() {
        guard let window, let owner else { return }
        try? root.measure(WindowsFoundation.Size(width: Float(Self.width), height: .infinity))
        let scale = owner.scale
        let width = (Self.width * scale).rounded(), height = (Double(root.desiredSize.height) * scale).rounded(.up)
        let position = owner.appWindow.position, size = owner.appWindow.size
        let left = Double(position.x) + (Double(size.width) - width) / 2
        let top = Double(position.y) + max(0, (Double(size.height) - height) / 2)
        window.place(origin: PointInt32(x: Int32(left.rounded()), y: Int32(top.rounded())),
                     size: SizeInt32(width: Int32(width), height: Int32(height)))
    }

    // MARK: The card

    private func build() {
        root.children.clear()
        root.background = UI.brush(DialogButtonColors.card)
        root.requestedTheme = .dark
        root.isTabStop = true
        root.padding = Thickness(left: 38.5, top: 38.5, right: 38.5, bottom: 28)
        try? AutomationProperties.setName(root, title)
        let stack = StackPanel()
        stack.orientation = .vertical
        let heading = UI.text(title, size: 17.5, color: UI.brush(255, 255, 255), trimmed: false)
        heading.fontWeight = UWP.FontWeight(weight: 600)
        heading.textWrapping = .wrap
        stack.children.append(heading)
        if !message.isEmpty {
            let body = UI.text(message, size: 14, color: UI.brush(DialogButtonColors.body), trimmed: false)
            body.textWrapping = .wrap
            body.margin = Thickness(left: 0, top: 16, right: 0, bottom: 0)
            stack.children.append(body)
        }
        // Arc's extra choice ("Quit, and don’t ask again") at the card's left edge, the rest at its right.
        let row = Grid()
        row.margin = Thickness(left: -10.5, top: 38, right: -10.5, bottom: 0)
        row.columnDefinitions.append(UI.column(UI.auto))
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.auto))
        let leading = buttons(actions.leadingOrder), trailing = buttons(actions.trailingOrder)
        row.children.append(leading)
        row.children.append(trailing)
        try? Grid.setColumn(trailing, 2)
        stack.children.append(row)
        root.children.append(stack)
        root.keyDown.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            switch Int32(truncatingIfNeeded: args.key.rawValue) {
            case 0x1B:  // Escape
                if let i = self.actions.cancelIndex { args.handled = true; self.select(i) }
            case 0x0D:  // Return
                if let i = self.actions.defaultIndex { args.handled = true; self.select(i) }
            default: break
            }
        }
    }

    private func buttons(_ order: [Int]) -> StackPanel {
        let panel = StackPanel()
        panel.orientation = .horizontal
        panel.spacing = 7
        for index in order { panel.children.append(button(index)) }
        return panel
    }

    /// One of Arc's sheet buttons: 37 DIPs tall, 8 DIP corners, the key it answers to in a badge
    /// after the title, a darker lip under the default one and a 10 % tint under the pointer.
    private func button(_ index: Int) -> UIElement {
        let action = actions.buttons[index]
        let colors = DialogButtonColors(DialogButtonColors.style(for: action.role))
        let key = actions.key(at: index)

        let face = Border()
        face.height = 37
        face.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        face.background = UI.brush(colors.fill)
        if let rim = colors.rim {
            face.borderBrush = UI.brush(rim)
            face.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        }
        face.padding = Thickness(left: 12.5, top: 0, right: 12, bottom: 0)
        let content = StackPanel()
        content.orientation = .horizontal
        content.spacing = 9
        content.verticalAlignment = .center
        let label = UI.text(action.title, size: 13, color: UI.brush(colors.title), trimmed: false)
        label.fontWeight = UWP.FontWeight(weight: 500)
        label.verticalAlignment = .center
        content.children.append(label)
        if !key.isEmpty {
            let badge = Border()
            badge.minWidth = 27
            badge.height = 19
            badge.cornerRadius = CornerRadius(topLeft: 5, topRight: 5, bottomRight: 5, bottomLeft: 5)
            badge.background = UI.brush(colors.badgeFill)
            if let rim = colors.badgeRim {
                badge.borderBrush = UI.brush(rim)
                badge.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
            }
            badge.padding = Thickness(left: 2, top: 0, right: 2, bottom: 0)
            badge.verticalAlignment = .center
            let text = UI.text(key, size: key == "↩" ? 13 : 11, color: UI.brush(colors.badgeText), trimmed: false)
            text.fontWeight = UWP.FontWeight(weight: 700)
            text.horizontalAlignment = .center
            text.verticalAlignment = .center
            badge.child = text
            content.children.append(badge)
        }
        let hover = Border()
        hover.cornerRadius = face.cornerRadius
        hover.background = colors.hoverIsWhite ? UI.brush(255, 255, 255, alpha: 26) : UI.brush(0, 0, 0, alpha: 26)
        hover.opacity = 0
        hover.isHitTestVisible = false
        let inner = Grid()
        inner.children.append(content)
        face.child = inner

        let shell = Grid()
        shell.background = UI.clear
        if let lip = colors.lip {
            let under = Border()
            under.cornerRadius = face.cornerRadius
            under.background = UI.brush(lip)
            under.margin = Thickness(left: 0, top: 1.5, right: 0, bottom: -1.5)
            shell.children.append(under)
        }
        shell.children.append(face)
        shell.children.append(hover)
        try? AutomationProperties.setName(shell, action.title)
        shell.pointerEntered.addHandler { _, _ in hover.opacity = 1 }
        shell.pointerExited.addHandler { _, _ in hover.opacity = 0 }
        shell.tapped.addHandler { [weak self] _, args in
            args?.handled = true
            self?.select(index)
        }
        kept += [shell, hover, face]
        return shell
    }
}
