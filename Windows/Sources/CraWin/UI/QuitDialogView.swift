import CraCore
import Foundation
import UWP
import WindowsFoundation
import WinUI

/// "Quit Cra?" and "Downloads in progress" (CraCore's QuitDialog, the Mac's AppDialog alerts) on
/// the profile dialogs' navy card, floating over the browser window. Return is the default
/// button and Escape stays.
@MainActor
final class QuitDialogView {
    static let width = 380.0

    var onAnswer: (QuitDialog.Answer) -> Void = { _ in }

    let root = Grid()
    private let content = StackPanel()
    private var dialog: QuitDialog?
    /// Held so their click handlers' weak captures stay alive (a WinRT control built from Swift
    /// is only a wrapper).
    private var buttons: [Button] = []

    private static let card = UI.brush("#161C2F")
    private static let body = UI.brush("#B8B9C4")
    private static let white = UI.brush(255, 255, 255)

    init() {
        root.background = Self.card
        root.requestedTheme = .dark
        root.padding = Thickness(left: 28, top: 24, right: 28, bottom: 20)
        content.orientation = .vertical
        root.children.append(content)
        root.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            switch Int32(truncatingIfNeeded: args.key.rawValue) {
            case 0x1B: self.onAnswer(QuitDialog.dismissed)  // Escape
            case 0x0D:  // Return
                guard let answer = self.dialog?.buttons.first(where: \.isDefault)?.answer else { return }
                self.onAnswer(answer)
            default: return
            }
            args.handled = true
        }
    }

    /// Builds the card for `dialog`. Returns its height in DIPs.
    func show(_ dialog: QuitDialog) -> Double {
        self.dialog = dialog
        content.children.clear()
        buttons = []
        let title = UI.text(dialog.title, size: 18, color: Self.white, trimmed: false)
        title.fontWeight = UWP.FontWeight(weight: 600)
        title.textWrapping = .wrap
        content.children.append(title)
        if let message = dialog.message {
            let text = UI.text(message, size: 13, color: Self.body, trimmed: false)
            text.textWrapping = .wrap
            text.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
            content.children.append(text)
        }
        let row = StackPanel()
        row.orientation = .vertical
        row.spacing = 8
        row.margin = Thickness(left: 0, top: 20, right: 0, bottom: 0)
        for b in dialog.buttons {
            let button = Button()
            button.content = UI.text(b.title, color: b.isDefault ? Self.white : nil, trimmed: false)
            button.horizontalAlignment = .stretch
            button.clickMode = .press
            if b.isDefault {
                // Windows' accent colour, as the profile dialog's default button.
                let accent = WinAppearance.accent
                button.background = UI.brush(accent.r, accent.g, accent.b)
                _ = button.resources.insert("ButtonBackgroundPointerOver", UI.brush(accent.r, accent.g, accent.b, alpha: 230))
                _ = button.resources.insert("ButtonBackgroundPressed", UI.brush(accent.r, accent.g, accent.b, alpha: 205))
                _ = button.resources.insert("ButtonForegroundPointerOver", Self.white)
                _ = button.resources.insert("ButtonForegroundPressed", Self.white)
            }
            let answer = b.answer
            button.click.addHandler { [weak self] _, _ in self?.onAnswer(answer) }
            try? AutomationProperties.setName(button, b.title)
            buttons.append(button)
            row.children.append(button)
        }
        content.children.append(row)
        try? root.measure(WindowsFoundation.Size(width: Float(Self.width), height: .infinity))
        return Double(root.desiredSize.height).rounded(.up)
    }

    /// The default button takes the keyboard (Return and Escape then reach the card).
    func focus() {
        guard let i = dialog?.buttons.firstIndex(where: \.isDefault), i < buttons.count else { return }
        _ = try? buttons[i].focus(.programmatic)
    }
}
