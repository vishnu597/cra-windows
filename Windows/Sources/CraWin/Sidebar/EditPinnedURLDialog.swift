import CraCore
import Foundation
import UWP
import WindowsFoundation
import WinUI

/// Arc 1.171's "Edit Pinned URL" card (a pinned tab's or favorite's Edit Pinned Page ▸ Edit…, the
/// Mac's EditPinnedURLDialog, #54): the saved URL selected in its field, Cancel (Escape) and Save
/// (Return). Save takes only an address (TypedURL.pinnedDestination), so a search or a script
/// can't become the pinned page. It floats in a window of its own over the browser window, as the
/// profile dialog does.
@MainActor
final class EditPinnedURLDialog {
    static let width = 393.0

    let root = Grid()
    private let field = TextBox()
    private let save = Button()
    private var window: FloatingWindow?
    private var onSave: (String) -> Void = { _ in }
    private var onDone: () -> Void = {}

    private static let card = UI.brush("#161C2F")
    private static let body = UI.brush("#B8B9C4")
    private static let white = UI.brush(255, 255, 255)

    init() {
        root.background = Self.card
        root.requestedTheme = .dark
        root.padding = Thickness(left: 37.5, top: 40, right: 28, bottom: 24)
        let content = StackPanel()
        content.orientation = .vertical
        root.children.append(content)

        let title = UI.text("Edit Pinned URL", size: 17.5, color: Self.white, trimmed: false)
        title.fontWeight = UWP.FontWeight(weight: 600)
        content.children.append(title)
        let body = UI.text("This is what opens first when you click this tab or its favicon.", size: 14, color: Self.body, trimmed: false)
        body.textWrapping = .wrap
        body.maxWidth = 304
        body.horizontalAlignment = .left
        body.margin = Thickness(left: 0, top: 16, right: 0, bottom: 0)
        content.children.append(body)

        field.placeholderText = "Enter a URL…"
        field.width = 318
        field.horizontalAlignment = .left
        field.margin = Thickness(left: 0, top: 15.5, right: 0, bottom: 0)
        field.textChanged.addHandler { [weak self] _, _ in self?.updateSave() }
        try? AutomationProperties.setName(field, "Pinned URL")
        content.children.append(field)

        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 7
        buttons.horizontalAlignment = .right
        buttons.margin = Thickness(left: 0, top: 21, right: 0, bottom: 0)
        let cancel = Button()
        cancel.content = UI.text("Cancel", trimmed: false)
        cancel.minWidth = 96
        cancel.clickMode = .press
        cancel.click.addHandler { [weak self] _, _ in self?.cancel() }
        save.content = UI.text("Save", color: Self.white, trimmed: false)
        save.minWidth = 96
        let accent = WinAppearance.accent
        save.background = UI.brush(accent.r, accent.g, accent.b)
        _ = save.resources.insert("ButtonBackgroundPointerOver", UI.brush(accent.r, accent.g, accent.b, alpha: 230))
        _ = save.resources.insert("ButtonBackgroundPressed", UI.brush(accent.r, accent.g, accent.b, alpha: 205))
        _ = save.resources.insert("ButtonForegroundPointerOver", Self.white)
        _ = save.resources.insert("ButtonForegroundPressed", Self.white)
        save.clickMode = .press
        save.click.addHandler { [weak self] _, _ in self?.confirm() }
        buttons.children.append(cancel)
        buttons.children.append(save)
        content.children.append(buttons)

        root.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            switch Int32(truncatingIfNeeded: args.key.rawValue) {
            case 0x1B: self.cancel()  // Escape
            case 0x0D: self.confirm()  // Return
            default: return
            }
            args.handled = true
        }
    }

    /// Shows the card centred over `owner` with `url` selected; `onSave` gets the address to pin,
    /// `onDone` runs once the card goes (saved or not), for the window to take the keyboard back.
    func present(over owner: HostWindow, url: String, onSave: @escaping (String) -> Void, onDone: @escaping () -> Void) {
        self.onSave = onSave
        self.onDone = onDone
        if window == nil {
            do {
                window = try FloatingWindow(owner: owner, content: root)
                // Alt+F4 on the card cancels it.
                window?.onClose = { [weak self] in self?.cancel() }
            } catch {
                print("Cra: the Edit Pinned URL window could not be made: \(error)")
                return
            }
        }
        field.text = url
        updateSave()
        try? root.measure(WindowsFoundation.Size(width: Float(Self.width), height: .infinity))
        let height = max(220, Double(root.desiredSize.height).rounded(.up))
        let scale = owner.scale
        let position = owner.appWindow.position, size = owner.appWindow.size
        let width = (Self.width * scale).rounded(), h = (height * scale).rounded()
        let left = Double(position.x) + (Double(size.width) - width) / 2
        let top = Double(position.y) + max(0, (Double(size.height) - h) / 2)
        window?.place(origin: PointInt32(x: Int32(left.rounded()), y: Int32(top.rounded())),
                      size: SizeInt32(width: Int32(width), height: Int32(h)))
        window?.show { [weak self] in
            guard let self else { return }
            _ = try? self.field.focus(.programmatic)
            try? self.field.selectAll()
        }
    }

    private var destination: String? { TypedURL.pinnedDestination(field.text) }

    private func updateSave() { save.isEnabled = destination != nil }

    private func confirm() {
        guard let destination, window?.isVisible == true else { return }
        let save = onSave
        close()
        save(destination)
    }

    private func cancel() { close() }

    private func close() {
        guard window?.isVisible == true else { return }
        window?.hide()
        let done = onDone
        onSave = { _ in }
        onDone = {}
        done()
    }
}
