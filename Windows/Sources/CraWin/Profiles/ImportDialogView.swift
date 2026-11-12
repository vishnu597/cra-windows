import CraCore
import Foundation
import UWP
import WindowsFoundation
import WinUI

/// Import from Another Browser (the Mac's Import from Arc or Dia…, whose sources are
/// WindowsImportSource here): one row per browser with data on this PC; picking one imports its
/// spaces, bookmarks and open tabs (Arc's sidebar, archive and Air Traffic Control), and with the
/// box ticked its passwords and sign-ins (the Mac's Passwords and Sign-ins tiles). When those
/// come along the card then says what came and what stayed; otherwise it closes. On the profile
/// dialogs' navy card, in a window of its own over the page; Escape is Cancel (or Done).
@MainActor
final class ImportDialogView {
    static let width = 450.0

    /// The browser, and whether its passwords and sign-ins come too.
    var onImport: (WindowsImportSource, Bool) -> Void = { _, _ in }
    var onCancel: () -> Void = {}

    let root = Grid()
    private let content = StackPanel()
    /// The rows' buttons, held so their click handlers stay alive (a WinRT control built from
    /// Swift is only a wrapper, gone once nothing in Swift holds it).
    private var rows: [Button] = []
    private var cancel: Button?
    private let credentials = CheckBox()

    private static let card = UI.brush("#161C2F")
    private static let row = UI.brush("#222A43")
    private static let body = UI.brush("#B8B9C4")
    private static let white = UI.brush(255, 255, 255)
    private static let muted = UI.brush("#8F929E")

    init() {
        root.background = Self.card
        root.requestedTheme = .dark
        root.padding = Thickness(left: 37, top: 30, right: 37, bottom: 24)
        content.orientation = .vertical
        root.children.append(content)
        let label = UI.text("Passwords and sign-ins", size: 14, color: Self.white, trimmed: false)
        credentials.content = label
        credentials.isChecked = true
        credentials.margin = Thickness(left: 0, top: 14, right: 0, bottom: 0)
        try? AutomationProperties.setName(credentials, "Bring passwords and sign-ins too")
        root.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x1B else { return }  // Escape
            self.onCancel()
            args.handled = true
        }
    }

    /// The browsers to offer, each with its profiles. Returns the card's height.
    func show(_ sources: [(source: WindowsImportSource, profiles: [ChromiumProfile])]) -> Double {
        content.children.clear()
        rows = []
        content.children.append(title("Import from Another Browser"))
        if sources.isEmpty {
            content.children.append(paragraph("Cra didn’t find Arc, Chrome, Edge, Brave, Opera, Opera GX, Vivaldi or Chromium data on this PC."))
        } else {
            content.children.append(paragraph("Each profile comes over as a Space, with its bookmarks bar pinned and its open tabs in Today. Arc’s Spaces, folders, favorites, archive and Air Traffic Control come over as they are."))
            content.children.append(credentials)
            let list = StackPanel()
            list.orientation = .vertical
            list.spacing = 6
            list.margin = Thickness(left: 0, top: 18, right: 0, bottom: 0)
            for entry in sources {
                let button = rowButton(entry.source, profiles: entry.profiles)
                list.children.append(button)
                rows.append(button)
            }
            let scroll = ScrollViewer()
            scroll.maxHeight = 300
            scroll.content = list
            content.children.append(scroll)
        }
        content.children.append(footer(sources.isEmpty ? "Close" : "Cancel"))
        return measuredHeight()
    }

    /// After an import that brought passwords or sign-ins: what came over and what stayed, with
    /// Done. Returns the card's height.
    func showResult(title text: String, lines: [String]) -> Double {
        content.children.clear()
        rows = []
        content.children.append(title(text))
        for line in lines { content.children.append(paragraph(line)) }
        content.children.append(footer("Done"))
        return measuredHeight()
    }

    private func measuredHeight() -> Double {
        try? root.measure(WindowsFoundation.Size(width: Float(Self.width), height: .infinity))
        return Double(root.desiredSize.height).rounded(.up)
    }

    /// The first browser takes the keyboard (Cancel when there is none).
    func focus() {
        _ = try? (rows.first ?? cancel)?.focus(.programmatic)
    }

    // MARK: Pieces

    private func rowButton(_ source: WindowsImportSource, profiles: [ChromiumProfile]) -> Button {
        let stack = StackPanel()
        stack.orientation = .vertical
        stack.children.append(UI.text(source.name, size: 14, color: Self.white, trimmed: false))
        let detail: String
        switch source.kind {
        case .arc: detail = "Spaces, pinned tabs, favorites and archive"
        case .chromium: detail = profiles.count > 1 ? "\(profiles.count) profiles: " + profiles.map(\.name).joined(separator: ", ") : "Bookmarks and open tabs"
        }
        let line = UI.text(detail, size: 12, color: Self.muted, trimmed: true)
        stack.children.append(line)
        let button = Button()
        button.content = stack
        button.horizontalAlignment = .stretch
        button.horizontalContentAlignment = .left
        button.padding = Thickness(left: 14, top: 9, right: 14, bottom: 9)
        button.background = Self.row
        button.clickMode = .release
        try? AutomationProperties.setName(button, "Import from \(source.name)")
        button.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onImport(source, self.credentials.isChecked == true)
        }
        return button
    }

    private func title(_ text: String) -> TextBlock {
        let t = UI.text(text, size: 17.5, color: Self.white, trimmed: false)
        t.fontWeight = UWP.FontWeight(weight: 600)
        t.textWrapping = .wrap
        return t
    }

    private func paragraph(_ text: String) -> TextBlock {
        let t = UI.text(text, size: 14, color: Self.body, trimmed: false)
        t.textWrapping = .wrap
        t.margin = Thickness(left: 0, top: 12, right: 0, bottom: 0)
        return t
    }

    private func footer(_ title: String) -> UIElement {
        let button = Button()
        button.content = UI.text(title, trimmed: false)
        button.minWidth = 96
        button.horizontalAlignment = .right
        button.margin = Thickness(left: 0, top: 22, right: 0, bottom: 0)
        button.clickMode = .press
        button.click.addHandler { [weak self] _, _ in self?.onCancel() }
        cancel = button
        return button
    }
}
