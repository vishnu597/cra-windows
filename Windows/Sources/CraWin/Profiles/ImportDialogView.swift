import CraCore
import Foundation
import UWP
import WindowsFoundation
import WinUI

/// Import from Another Browser (the Mac's Import from Arc or Dia…, whose sources are
/// WindowsImportSource here): one row per browser with data on this PC; picking one imports its
/// spaces, bookmarks and open tabs (Arc's sidebar, archive and Air Traffic Control), and with the
/// box ticked its passwords and sign-ins (the Mac's Passwords and Sign-ins tiles). When the
/// browser has extensions Cra doesn't, a second page lists them to pick from (the Mac's
/// Extensions step); the picked ones are copied into Cra's Extensions folder. When passwords or
/// extensions come along the card then says what came and what stayed; otherwise it closes. On
/// the profile dialogs' navy card, in a window of its own over the page; Escape is Cancel (or Done).
@MainActor
final class ImportDialogView {
    static let width = 450.0

    /// The browser, whether its passwords and sign-ins come too, and the extensions picked.
    var onImport: (WindowsImportSource, Bool, [ExtensionImport.Candidate]) -> Void = { _, _, _ in }
    var onCancel: () -> Void = {}
    /// The browser's extensions, and the IDs Cra has already (left off the list).
    var extensionsOf: (WindowsImportSource) -> (candidates: [ExtensionImport.Candidate], installed: Set<String>) = { _ in ([], []) }
    /// The card's height changed (the extensions page), to place its window again.
    var onHeightChange: (Double) -> Void = { _ in }

    let root = Grid()
    private let content = StackPanel()
    /// The rows' buttons, held so their click handlers stay alive (a WinRT control built from
    /// Swift is only a wrapper, gone once nothing in Swift holds it).
    private var rows: [Button] = []
    private var cancel: Button?
    private let credentials = CheckBox()
    /// The extensions page's boxes, by extension ID; and its Import button, which takes the keyboard.
    private var extensionBoxes: [(id: String, box: CheckBox)] = []
    private var importButton: Button?
    /// The last list of browsers, for the extensions page's Back.
    private var sources: [(source: WindowsImportSource, profiles: [ChromiumProfile])] = []

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
        self.sources = sources
        content.children.clear()
        rows = []
        extensionBoxes = []
        importButton = nil
        content.children.append(title("Import from Another Browser"))
        if sources.isEmpty {
            content.children.append(paragraph("Cra didn’t find \(WindowsImportSource.names) data on this PC."))
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
        extensionBoxes = []
        importButton = nil
        content.children.append(title(text))
        for line in lines { content.children.append(paragraph(line)) }
        content.children.append(footer("Done"))
        return measuredHeight()
    }

    private func measuredHeight() -> Double {
        try? root.measure(WindowsFoundation.Size(width: Float(Self.width), height: .infinity))
        return Double(root.desiredSize.height).rounded(.up)
    }

    /// The first browser takes the keyboard (Import on the extensions page, Cancel when there is none).
    func focus() {
        _ = try? (importButton ?? rows.first ?? cancel)?.focus(.programmatic)
    }

    /// A browser was picked: its extensions to pick from first, when it has any Cra doesn't.
    private func pick(_ source: WindowsImportSource) {
        let withCredentials = credentials.isChecked == true
        let offered = extensionsOf(source)
        let fresh = offered.candidates.filter { !offered.installed.contains($0.id) }
        guard !fresh.isEmpty else {
            onImport(source, withCredentials, [])
            return
        }
        onHeightChange(showExtensions(source, fresh, alreadyIn: offered.candidates.count - fresh.count,
                                      ticked: ExtensionImport.preselected(fresh, installed: offered.installed), credentials: withCredentials))
        focus()
    }

    /// The Mac's Extensions step: one box per extension, the ones on in the browser ticked.
    private func showExtensions(_ source: WindowsImportSource, _ offered: [ExtensionImport.Candidate], alreadyIn: Int,
                                ticked: Set<String>, credentials withCredentials: Bool) -> Double {
        content.children.clear()
        rows = []
        extensionBoxes = []
        content.children.append(title("Extensions from \(source.name)"))
        var words = "Cra copies the ones you pick into its own Extensions folder. They load in every profile when Cra next starts."
        if alreadyIn > 0 { words += alreadyIn == 1 ? " One is in Cra already." : " \(alreadyIn) are in Cra already." }
        content.children.append(paragraph(words))
        let list = StackPanel()
        list.orientation = .vertical
        list.spacing = 2
        list.margin = Thickness(left: 0, top: 14, right: 0, bottom: 0)
        for e in offered {
            let box = CheckBox()
            let name = e.version.isEmpty ? e.name : "\(e.name) \(e.version)"
            let label = UI.text(e.isEnabled ? name : "\(name) (turned off)", size: 14, color: Self.white, trimmed: true)
            box.content = label
            box.isChecked = ticked.contains(e.id)
            try? AutomationProperties.setName(box, e.name)
            list.children.append(box)
            extensionBoxes.append((e.id, box))
        }
        let scroll = ScrollViewer()
        scroll.maxHeight = 260
        scroll.content = list
        content.children.append(scroll)

        let buttons = Grid()
        buttons.margin = Thickness(left: 0, top: 22, right: 0, bottom: 0)
        buttons.columnDefinitions.append(UI.column(UI.auto))
        buttons.columnDefinitions.append(UI.column(UI.star))
        buttons.columnDefinitions.append(UI.column(UI.auto))
        let back = Button()
        back.content = UI.text("Back", trimmed: false)
        back.minWidth = 80
        back.clickMode = .release
        back.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.onHeightChange(self.show(self.sources))
            self.focus()
        }
        buttons.children.append(back)
        let go = Button()
        go.content = UI.text("Import", trimmed: false)
        go.minWidth = 96
        go.background = Self.white
        go.foreground = Self.card
        go.clickMode = .release
        go.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            let picked = Set(self.extensionBoxes.filter { $0.box.isChecked == true }.map(\.id))
            self.onImport(source, withCredentials, offered.filter { picked.contains($0.id) })
        }
        try? Grid.setColumn(go, 2)
        buttons.children.append(go)
        content.children.append(buttons)
        cancel = back
        importButton = go
        return measuredHeight()
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
            self?.pick(source)
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
