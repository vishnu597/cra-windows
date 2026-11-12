import CraCore
import Foundation
import UWP
import WindowsFoundation
import WinUI

/// The first-run onboarding (the Mac's ImportFlow and OnboardingSteps, after Dia 1.54): a cover
/// page, the default browser, the import, pinned tabs, the space's colour and an outro, on one
/// card over the first browser window. `Onboarding.Flow` (CraCore) decides which steps show and
/// their order; the window it sits over does the work through the closures. It can't be
/// cancelled, only finished: quitting halfway shows it again on the next launch.
///
/// Not on Windows yet: the privacy step (Cra for Windows has no ad blocker or usage stats to
/// switch on), the Mac's Dock option, and the address bar layout (Windows has no toolbar).
@MainActor
final class OnboardingView {
    static let width = 600.0
    static let height = 470.0

    struct Source {
        let source: WindowsImportSource
        let profiles: [ChromiumProfile]
    }

    /// What one import did: its summary, and what its passwords and sign-ins did; or an error.
    enum ImportOutcome {
        case done(summary: String, credentials: String?)
        case failed(String)
    }

    // Wired by the browser window.
    var importData: (WindowsImportSource, Bool) -> ImportOutcome = { _, _ in .failed("") }
    /// Most visited sites from `source` (nil: any browser on this PC), as candidates and the ones
    /// ticked to start with; their icons go into the favicon cache.
    var pinCandidates: (WindowsImportSource?) -> (candidates: [Onboarding.PinCandidate], ticked: Set<String>) = { _ in
        (Onboarding.presetPins, [])
    }
    var pin: ([Onboarding.PinCandidate]) -> Void = { _ in }
    var chooseTheme: (Int) -> Void = { _ in }
    /// The default browser step's choices: make Cra the default (Windows' own page opens), and
    /// open it at sign-in. An error to show, or nil.
    var applySystemOptions: (Bool, Bool) -> String? = { _, _ in nil }
    var finish: () -> Void = {}

    let root = Grid()
    private let body = StackPanel()
    private let footer = Grid()
    private var flow = Onboarding.Flow(offersDefaultBrowser: false, offersPrivacy: false, offersPinnedTabs: false)
    private(set) var step: Onboarding.Step = .cover
    private var sources: [Source] = []
    private var imported: WindowsImportSource?
    private var importResult: [String] = []
    private var candidates: [Onboarding.PinCandidate] = []
    private var ticked: Set<String> = []
    private var chosenTheme: Int?
    private var systemError: String?
    private var wantsDefault = true
    private var wantsLaunchAtLogin = false
    private var wantsCredentials = true
    /// Built per step and held: a WinRT control made from Swift is only a wrapper, its click
    /// handler gone once nothing in Swift holds it.
    private var controls: [Control] = []
    private var primary: Button?
    private var pinTiles: [String: Button] = [:]
    private let favicons: Favicons

    private static let card = UI.brush("#161C2F")
    private static let row = UI.brush("#222A43")
    private static let rowOn = UI.brush("#33406A")
    private static let ring = UI.brush(255, 255, 255)
    private static let bodyText = UI.brush("#B8B9C4")
    private static let white = UI.brush(255, 255, 255)
    private static let muted = UI.brush("#8F929E")

    init(favicons: Favicons = .shared) {
        self.favicons = favicons
        root.background = Self.card
        root.requestedTheme = .dark
        root.padding = Thickness(left: 44, top: 38, right: 44, bottom: 28)
        for height in [UI.star, UI.auto] { root.rowDefinitions.append(UI.row(height)) }
        body.orientation = .vertical
        root.children.append(body)
        try? Grid.setRow(footer, 1)
        for width in [UI.auto, UI.star, UI.auto] { footer.columnDefinitions.append(UI.column(width)) }
        root.children.append(footer)
        root.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x0D, let primary = self.primary else { return }  // Return
            if primary.isEnabled { self.pressPrimary() }
            args.handled = true
        }
    }

    /// Starts at the cover. `isDefaultBrowser` and `launchesAtLogin` set the default browser
    /// step's boxes (it shows only while Cra isn't the default).
    func start(flow: Onboarding.Flow, sources: [Source], launchesAtLogin: Bool) {
        self.flow = flow
        self.sources = sources
        wantsDefault = true
        wantsLaunchAtLogin = launchesAtLogin
        show(.cover)
    }

    /// The step's main button takes the keyboard.
    func focus() {
        _ = try? primary?.focus(.programmatic)
    }

    // MARK: Steps

    private var primaryAction: () -> Void = {}

    private func pressPrimary() { primaryAction() }

    private func show(_ next: Onboarding.Step) {
        step = next
        // No ad blocker or usage stats on Windows yet: the flow never offers it.
        if next == .privacy { return advance() }
        body.children.clear()
        footer.children.clear()
        controls = []
        pinTiles = [:]
        primary = nil
        switch next {
        case .cover: showCover()
        case .defaultBrowser: showDefaultBrowser()
        case .privacy, .importData: showImport()
        case .pinnedTabs: showPinnedTabs()
        case .personalization: showPersonalization()
        case .outro: showOutro()
        }
        focus()
    }

    private func advance() {
        guard let next = flow.next(after: step) else { return finish() }
        show(next)
    }

    private func showCover() {
        body.children.append(title("A calmer way\nto browse", size: 34, top: 40))
        body.children.append(paragraph("Cra is a browser with a sidebar instead of a tab strip. Spaces, pinned tabs, a command bar that learns, and an archive that tidies up after you."))
        setButtons(primary: "Get Started", back: false) { [weak self] in self?.advance() }
    }

    private func showDefaultBrowser() {
        body.children.append(title("Make Cra your default browser"))
        body.children.append(paragraph("Links from other apps then open in Cra. Windows asks you to pick Cra yourself, in Settings ▸ Default apps."))
        let list = StackPanel()
        list.orientation = .vertical
        list.spacing = 10
        list.margin = Thickness(left: 0, top: 26, right: 0, bottom: 0)
        list.children.append(checkbox("Make Cra your default browser", on: wantsDefault) { [weak self] in self?.wantsDefault = $0 })
        list.children.append(checkbox("Open Cra when you sign in to Windows", on: wantsLaunchAtLogin) { [weak self] in self?.wantsLaunchAtLogin = $0 })
        body.children.append(list)
        if let systemError { body.children.append(paragraph(systemError)) }
        setButtons(primary: "Continue", back: true) { [weak self] in
            guard let self else { return }
            // After a refusal has been shown, Continue moves on instead of asking again.
            if self.systemError == nil,
               let error = self.applySystemOptions(self.wantsDefault, self.wantsLaunchAtLogin) {
                self.systemError = error
                return self.show(.defaultBrowser)
            }
            self.advance()
        }
    }

    private func showImport() {
        body.children.append(title("Bring your stuff over"))
        if !importResult.isEmpty {
            for line in importResult { body.children.append(paragraph(line)) }
            setButtons(primary: "Continue", back: false) { [weak self] in self?.advance() }
            return
        }
        guard !sources.isEmpty else {
            body.children.append(paragraph("Cra didn’t find Arc, Chrome, Edge, Brave, Opera, Opera GX, Vivaldi or Chromium data on this PC. You can import later from Settings ▸ General."))
            setButtons(primary: "Continue", back: true) { [weak self] in self?.advance() }
            return
        }
        body.children.append(paragraph("Pick a browser: each profile comes over as a Space, with its bookmarks bar pinned and its open tabs in Today. Arc’s Spaces, favorites and archive come over as they are."))
        let credentials = checkbox("Passwords and sign-ins", on: wantsCredentials) { [weak self] in self?.wantsCredentials = $0 }
        credentials.margin = Thickness(left: 0, top: 14, right: 0, bottom: 0)
        body.children.append(credentials)
        let list = StackPanel()
        list.orientation = .vertical
        list.spacing = 6
        for entry in sources {
            let button = sourceButton(entry)
            list.children.append(button)
            controls.append(button)
        }
        let scroll = ScrollViewer()
        scroll.maxHeight = 170
        scroll.margin = Thickness(left: 0, top: 16, right: 0, bottom: 0)
        scroll.content = list
        body.children.append(scroll)
        setButtons(primary: "Skip", back: true) { [weak self] in self?.advance() }
    }

    private func sourceButton(_ entry: Source) -> Button {
        let stack = StackPanel()
        stack.orientation = .vertical
        stack.children.append(UI.text(entry.source.name, size: 14, color: Self.white, trimmed: false))
        let detail: String
        switch entry.source.kind {
        case .arc: detail = "Spaces, pinned tabs, favorites and archive"
        case .chromium:
            detail = entry.profiles.count > 1 ? "\(entry.profiles.count) profiles: " + entry.profiles.map(\.name).joined(separator: ", ")
                : "Bookmarks and open tabs"
        }
        stack.children.append(UI.text(detail, size: 12, color: Self.muted, trimmed: true))
        let button = Button()
        button.content = stack
        button.horizontalAlignment = .stretch
        button.horizontalContentAlignment = .left
        button.padding = Thickness(left: 14, top: 9, right: 14, bottom: 9)
        button.background = Self.row
        button.clickMode = .release
        try? AutomationProperties.setName(button, "Import from \(entry.source.name)")
        button.click.addHandler { [weak self] _, _ in self?.runImport(entry.source) }
        return button
    }

    private func runImport(_ source: WindowsImportSource) {
        switch importData(source, wantsCredentials) {
        case .done(let summary, let words):
            imported = source
            importResult = [summary] + (words.map { [$0] } ?? [])
        case .failed(let error):
            importResult = [error.isEmpty ? "Cra couldn’t import from \(source.name)." : error]
        }
        show(.importData)
    }

    private func showPinnedTabs() {
        if candidates.isEmpty {
            let offered = pinCandidates(imported)
            candidates = offered.candidates
            ticked = offered.ticked
        }
        body.children.append(title("Pin the sites you use most"))
        body.children.append(paragraph("They go in your favorites at the top of the sidebar, one click away."))
        let grid = Grid()
        grid.margin = Thickness(left: 0, top: 20, right: 0, bottom: 0)
        grid.columnSpacing = 8
        grid.rowSpacing = 8
        let columns = 4
        for _ in 0..<columns { grid.columnDefinitions.append(UI.column(UI.star)) }
        for _ in 0..<((candidates.count + columns - 1) / columns) { grid.rowDefinitions.append(UI.row(UI.pixels(52))) }
        for (i, candidate) in candidates.enumerated() {
            let tile = pinTile(candidate)
            try? Grid.setColumn(tile, Int32(i % columns))
            try? Grid.setRow(tile, Int32(i / columns))
            grid.children.append(tile)
            controls.append(tile)
            pinTiles[candidate.host] = tile
        }
        body.children.append(grid)
        setButtons(primary: "Continue", back: true) { [weak self] in
            guard let self else { return }
            self.pin(self.candidates.filter { self.ticked.contains($0.host) })
            self.advance()
        }
    }

    private func pinTile(_ candidate: Onboarding.PinCandidate) -> Button {
        let on = ticked.contains(candidate.host)
        let stack = StackPanel()
        stack.orientation = .horizontal
        stack.spacing = 8
        if let key = FaviconKey.key(for: candidate.url), let bitmap = favicons.bitmap(forKey: key, onDark: true) {
            let image = UI.image(bitmap, size: 16)
            image.verticalAlignment = .center
            stack.children.append(image)
        }
        let name = UI.text(candidate.name, size: 13, color: Self.white, trimmed: true)
        name.verticalAlignment = .center
        stack.children.append(name)
        let button = Button()
        button.content = stack
        button.horizontalAlignment = .stretch
        button.verticalAlignment = .stretch
        button.horizontalContentAlignment = .left
        button.padding = Thickness(left: 12, top: 0, right: 8, bottom: 0)
        button.background = on ? Self.rowOn : Self.row
        button.borderBrush = on ? Self.ring : UI.clear
        button.borderThickness = Thickness(left: 1.5, top: 1.5, right: 1.5, bottom: 1.5)
        button.clickMode = .release
        try? AutomationProperties.setName(button, "\(on ? "Unpin" : "Pin") \(candidate.name)")
        button.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.ticked.contains(candidate.host) { self.ticked.remove(candidate.host) } else { self.ticked.insert(candidate.host) }
            self.show(.pinnedTabs)
            if let again = self.pinTiles[candidate.host] { _ = try? again.focus(.programmatic) }
        }
        return button
    }

    private func showPersonalization() {
        body.children.append(title("Make it yours"))
        body.children.append(paragraph("Pick the colour that feels right for your space. You can change it later from the space’s menu."))
        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 10
        row.margin = Thickness(left: 0, top: 28, right: 0, bottom: 0)
        for (i, theme) in SpaceTheme.presets.enumerated() {
            let swatch = swatch(theme, index: i)
            row.children.append(swatch)
            controls.append(swatch)
        }
        body.children.append(row)
        setButtons(primary: "Continue", back: true) { [weak self] in self?.advance() }
    }

    private func swatch(_ theme: SpaceTheme, index: Int) -> Button {
        let on = chosenTheme == index
        let dot = Border()
        dot.width = 34
        dot.height = 34
        dot.cornerRadius = CornerRadius(topLeft: 17, topRight: 17, bottomRight: 17, bottomLeft: 17)
        dot.background = UI.brush(theme.colors.last ?? theme.colors.first ?? "#808080")
        dot.borderBrush = UI.brush(theme.colors.first ?? "#808080")
        dot.borderThickness = Thickness(left: 5, top: 5, right: 5, bottom: 5)
        let button = Button()
        button.content = dot
        button.padding = Thickness(left: 3, top: 3, right: 3, bottom: 3)
        button.background = UI.clear
        button.borderBrush = on ? Self.ring : UI.clear
        button.borderThickness = Thickness(left: 2, top: 2, right: 2, bottom: 2)
        button.cornerRadius = CornerRadius(topLeft: 22, topRight: 22, bottomRight: 22, bottomLeft: 22)
        button.clickMode = .release
        try? AutomationProperties.setName(button, "Theme colour \(index + 1)\(on ? ", chosen" : "")")
        button.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.chosenTheme = index
            self.chooseTheme(index)
            self.show(.personalization)
            if index < self.controls.count { _ = try? self.controls[index].focus(.programmatic) }
        }
        return button
    }

    private func showOutro() {
        let t = title("Welcome to your new\nhome on the internet", size: 32, top: 70)
        t.horizontalAlignment = .center
        body.children.append(t)
        let tip = paragraph("Ctrl+T opens the command bar: type to search, open a tab or run any command.")
        tip.horizontalAlignment = .center
        body.children.append(tip)
        setButtons(primary: "Start browsing", back: false, centred: true) { [weak self] in self?.finish() }
    }

    // MARK: Pieces

    private func checkbox(_ title: String, on: Bool, _ changed: @escaping (Bool) -> Void) -> CheckBox {
        let box = CheckBox()
        let label = UI.text(title, size: 14, color: Self.white, trimmed: false)
        label.textWrapping = .wrap
        box.content = label
        box.isChecked = on
        try? AutomationProperties.setName(box, title)
        box.click.addHandler { [weak box] _, _ in
            guard let box else { return }
            changed(box.isChecked == true)
        }
        controls.append(box)
        return box
    }

    private func setButtons(primary title: String, back: Bool, centred: Bool = false, _ action: @escaping () -> Void) {
        primaryAction = action
        if back, let previous = flow.previous(before: step) {
            let button = Button()
            button.content = UI.text("Back", trimmed: false)
            button.minWidth = 80
            button.clickMode = .release
            button.click.addHandler { [weak self] _, _ in self?.show(previous) }
            footer.children.append(button)
            controls.append(button)
        }
        let button = Button()
        button.content = UI.text(title, trimmed: false)
        button.minWidth = centred ? 220 : 120
        button.background = Self.white
        button.foreground = Self.card
        button.clickMode = .release
        button.click.addHandler { [weak self] _, _ in self?.pressPrimary() }
        if centred {
            button.horizontalAlignment = .center
            try? Grid.setColumn(button, 1)
        } else {
            try? Grid.setColumn(button, 2)
        }
        footer.children.append(button)
        controls.append(button)
        primary = button
    }

    private func title(_ text: String, size: Double = 26, top: Double = 0) -> TextBlock {
        let t = UI.text(text, size: size, color: Self.white, trimmed: false)
        t.fontFamily = FontFamily("Georgia")
        t.textWrapping = .wrap
        t.margin = Thickness(left: 0, top: top, right: 0, bottom: 0)
        return t
    }

    private func paragraph(_ text: String) -> TextBlock {
        let t = UI.text(text, size: 14, color: Self.bodyText, trimmed: false)
        t.textWrapping = .wrap
        t.margin = Thickness(left: 0, top: 14, right: 0, bottom: 0)
        return t
    }
}
