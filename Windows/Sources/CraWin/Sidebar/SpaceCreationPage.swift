import CraCore
import Foundation
import UWP
import WinUI

/// Arc's "Create a Space" page in the sidebar (the Mac's SpaceCreationView, on CraCore's
/// SpaceCreationDraft and SpaceCreationLayout): a picture, a title, the name field with its icon
/// button, the Profile and Choose a Theme rows, and Create Space and Cancel at the bottom. The
/// space it was opened on wears the draft's theme while it is up, and nothing is made until
/// Create Space (SidebarStore.beginSpaceCreation and finishSpaceCreation, shared with the Mac).
/// It is made once and kept while it is up: the sidebar's redraws only recolour it, so the name
/// being typed stays in its field. Every control is kept here (a WinRT control made in Swift is
/// only a wrapper).
@MainActor
final class SpaceCreationPageView {
    let root = Grid()
    let origin: UUID
    private(set) var draft: SpaceCreationDraft
    private let store: SidebarStore
    private let windowID: UUID
    /// The sidebar, which the theme editor stands against.
    private let anchor: FrameworkElement
    /// The draft changed in a way the dock shows (its icon, its theme).
    private let onDraft: @MainActor () -> Void
    /// The page was left, by Create Space or Cancel.
    private let onEnd: @MainActor () -> Void
    private let focusField: @MainActor (TextBox) -> Void
    /// Runs with the space Create Space made.
    var created: (@MainActor (UUID) -> Void)?

    private let column = StackPanel()
    private let picture = Border()
    private let title = TextBlock()
    private let subtitle = TextBlock()
    private let field = Border()
    private let iconButton = Button()
    private let iconEmoji = TextBlock()
    private let iconGlyph = FontIcon()
    private let iconPicture = WinUI.Image()
    private let name = TextBox()
    private let profileRow = Button()
    private let profilePill = Border()
    private let profileName = TextBlock()
    private let themeRow = Button()
    private var rowGlyphs: [FontIcon] = []
    private var rowLabels: [TextBlock] = []
    private let info = FontIcon()
    private let buttons = StackPanel()
    private let create = Button()
    private let createLabel = TextBlock()
    private let cancel = Button()
    private let cancelLabel = TextBlock()
    private var iconPicker: SpaceIconPickerView?
    private var editor: SpaceStyleEditorView?
    private var profileMenu: MenuFlyout?
    private var palette: SidebarPalette
    private var ended = false

    /// Opens the page in `window` (SidebarStore.beginSpaceCreation): the window shows no tab and
    /// its space wears a new space's theme.
    init(store: SidebarStore, window: UUID, anchor: FrameworkElement, focusField: @escaping @MainActor (TextBox) -> Void,
         onDraft: @escaping @MainActor () -> Void, onEnd: @escaping @MainActor () -> Void) {
        self.store = store
        windowID = window
        self.anchor = anchor
        self.focusField = focusField
        self.onDraft = onDraft
        self.onEnd = onEnd
        let begun = store.beginSpaceCreation(window: window)
        draft = begun.draft
        origin = begun.origin
        palette = SidebarPalette(draft.theme)

        for height in [UI.star, UI.auto] { root.rowDefinitions.append(UI.row(height)) }
        root.background = UI.clear
        column.orientation = .vertical
        column.spacing = 0
        column.padding = Thickness(left: L.inset - 10, top: L.pictureTop, right: L.inset - 10, bottom: 0)
        root.children.append(column)

        // The picture, the title and the subtitle, centred.
        picture.width = L.pictureWidth
        picture.height = L.pictureHeight
        picture.cornerRadius = CornerRadius(topLeft: 7, topRight: 7, bottomRight: 7, bottomLeft: 7)
        picture.borderThickness = Thickness(left: 1.5, top: 1.5, right: 1.5, bottom: 1.5)
        picture.horizontalAlignment = .center
        column.children.append(picture)
        title.text = "Create a Space"
        title.fontSize = L.titleFont
        title.fontWeight = UWP.FontWeight(weight: 700)
        title.horizontalAlignment = .center
        title.margin = Thickness(left: 0, top: L.titleTop - L.pictureTop - L.pictureHeight, right: 0, bottom: 0)
        column.children.append(title)
        subtitle.fontSize = L.textFont
        subtitle.textAlignment = .center
        subtitle.textWrapping = .wrap
        subtitle.horizontalAlignment = .center
        subtitle.margin = Thickness(left: 0, top: 10, right: 0, bottom: 28)
        column.children.append(subtitle)

        // The name field: the icon button, then the name.
        let fieldGrid = Grid()
        fieldGrid.columnDefinitions.append(UI.column(UI.auto))
        fieldGrid.columnDefinitions.append(UI.column(UI.star))
        field.height = L.fieldHeight
        field.cornerRadius = CornerRadius(topLeft: L.cornerRadius, topRight: L.cornerRadius, bottomRight: L.cornerRadius, bottomLeft: L.cornerRadius)
        field.child = fieldGrid
        let iconContent = Grid()
        for part: UIElement in [iconEmoji, iconGlyph, iconPicture] { iconContent.children.append(part) }
        iconEmoji.fontSize = 14
        iconEmoji.horizontalAlignment = .center
        iconEmoji.verticalAlignment = .center
        iconGlyph.fontSize = 12
        iconGlyph.horizontalAlignment = .center
        iconGlyph.verticalAlignment = .center
        iconPicture.width = 16
        iconPicture.height = 16
        iconPicture.stretch = .uniform
        iconButton.content = iconContent
        iconButton.width = L.iconSide + 8
        iconButton.height = L.iconSide + 8
        iconButton.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        iconButton.margin = Thickness(left: L.iconInset - 4, top: 0, right: 0, bottom: 0)
        iconButton.verticalAlignment = .center
        iconButton.background = UI.clear
        iconButton.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        iconButton.clickMode = .press
        iconButton.click.addHandler { [weak self] _, _ in self?.showIconPicker() }
        try? AutomationProperties.setName(iconButton, "Space icon")
        fieldGrid.children.append(iconButton)
        name.placeholderText = "Space name..."
        name.fontSize = L.textFont
        name.fontWeight = UWP.FontWeight(weight: 600)
        name.background = UI.clear
        name.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        name.minHeight = 0
        name.padding = Thickness(left: 4, top: 6, right: 6, bottom: 6)
        name.verticalAlignment = .center
        name.isSpellCheckEnabled = false
        name.isTextPredictionEnabled = false
        // Typed text stays the field's own over the TextBox's focus fill.
        for key in ["TextControlBackgroundFocused", "TextControlBackgroundPointerOver", "TextControlBorderBrushFocused"] {
            _ = name.resources.insert(key, UI.clear)
        }
        try? AutomationProperties.setName(name, "Space name")
        try? Grid.setColumn(name, 1)
        fieldGrid.children.append(name)
        name.textChanged.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.draft.title = self.name.text
            self.refreshButtons()
        }
        name.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            switch Int32(truncatingIfNeeded: args.key.rawValue) {
            case 0x0D: args.handled = true; self.createSpace()  // Return
            case 0x1B: args.handled = true; self.cancelCreation()  // Escape
            default: break
            }
        }
        name.loaded.addHandler { [weak self] _, _ in self?.focusName() }
        column.children.append(field)

        // The rows: Profile with its pill and (i), then Choose a Theme.
        let profileGrid = rowContent(symbol: "face.smiling", label: "Profile")
        let pillRow = StackPanel()
        pillRow.orientation = .horizontal
        pillRow.spacing = 8
        pillRow.verticalAlignment = .center
        profilePill.height = L.pillHeight
        profilePill.cornerRadius = CornerRadius(topLeft: 5, topRight: 5, bottomRight: 5, bottomLeft: 5)
        profilePill.padding = Thickness(left: 7, top: 0, right: 7, bottom: 0)
        profileName.fontSize = 12
        profileName.verticalAlignment = .center
        profilePill.child = profileName
        pillRow.children.append(profilePill)
        info.glyph = WinGlyph.code("info.circle")
        info.fontSize = L.infoSide
        info.verticalAlignment = .center
        info.margin = Thickness(left: 0, top: 0, right: L.infoInset - 8, bottom: 0)
        try? ToolTipService.setToolTip(info, SpaceCreationDraft.profileNote)
        pillRow.children.append(info)
        try? Grid.setColumn(pillRow, 2)
        profileGrid.children.append(pillRow)
        setUpRow(profileRow, content: profileGrid, top: L.fieldGap) { [weak self] in self?.showProfileMenu() }
        try? AutomationProperties.setName(profileRow, "Profile")
        column.children.append(profileRow)
        setUpRow(themeRow, content: rowContent(symbol: "paintbrush.fill", label: "Choose a Theme"), top: L.rowGap) { [weak self] in
            self?.showThemeEditor()
        }
        try? AutomationProperties.setName(themeRow, "Choose a Theme")
        column.children.append(themeRow)

        // Create Space, and Cancel under it.
        buttons.orientation = .vertical
        buttons.spacing = 4
        buttons.padding = Thickness(left: L.inset - 10, top: 0, right: L.inset - 10, bottom: L.buttonBottom - L.cancelCentre - 10)
        createLabel.text = "Create Space"
        createLabel.fontSize = L.textFont
        createLabel.fontWeight = UWP.FontWeight(weight: 600)
        create.content = createLabel
        create.height = L.buttonHeight
        create.horizontalAlignment = .stretch
        create.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        create.cornerRadius = CornerRadius(topLeft: L.cornerRadius, topRight: L.cornerRadius, bottomRight: L.cornerRadius, bottomLeft: L.cornerRadius)
        create.click.addHandler { [weak self] _, _ in self?.createSpace() }
        buttons.children.append(create)
        cancelLabel.text = "Cancel"
        cancelLabel.fontSize = L.textFont
        cancelLabel.fontWeight = UWP.FontWeight(weight: 500)
        cancel.content = cancelLabel
        cancel.horizontalAlignment = .center
        cancel.background = UI.clear
        cancel.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        cancel.click.addHandler { [weak self] _, _ in self?.cancelCreation() }
        buttons.children.append(cancel)
        try? Grid.setRow(buttons, 1)
        root.children.append(buttons)

        // Escape anywhere on the page cancels, as on the Mac.
        root.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x1B else { return }
            args.handled = true
            self.cancelCreation()
        }
        showDraft()
    }

    // MARK: Drawing

    /// The sidebar redrew (its theme, its width): the page takes the sidebar's colours and its
    /// width's density (SpaceCreationLayout.Density).
    func apply(palette: SidebarPalette, width: Double) {
        self.palette = palette
        let density = SpaceCreationLayout.Density(sidebarWidth: CGFloat(width))
        subtitle.text = density.subtitle
        for glyph in rowGlyphs { glyph.visibility = density.showsRowGlyphs ? .visible : .collapsed }
        for label in rowLabels {
            label.margin = Thickness(left: Double(density.rowLabelInset) - (density.showsRowGlyphs ? 32 : 0), top: 0, right: 0, bottom: 0)
        }
        let ink = palette.text, faint = palette.secondaryText
        for t in [title, profileName, cancelLabel] { t.foreground = ink }
        subtitle.foreground = faint
        for label in rowLabels { label.foreground = ink }
        for glyph in rowGlyphs { glyph.foreground = ink }
        info.foreground = faint
        iconGlyph.foreground = ink
        name.foreground = ink
        picture.borderBrush = faint
        picture.background = palette.tile
        field.background = palette.tile
        profilePill.background = palette.selected
        for row in [profileRow, themeRow] { row.background = palette.tile }
        refreshButtons()
    }

    /// The draft as drawn: its icon in the name field's button, its profile in the pill.
    private func showDraft() {
        iconEmoji.visibility = .collapsed
        iconGlyph.visibility = .collapsed
        iconPicture.visibility = .collapsed
        iconGlyph.opacity = 1
        switch draft.icon {
        case .emoji(let e):
            iconEmoji.text = e
            iconEmoji.visibility = .visible
        case .symbol(let s):
            iconGlyph.glyph = WinGlyph.known(s) ?? WinGlyph.code("space")
            iconGlyph.visibility = .visible
        case .image(let data):
            iconPicture.source = Pixels.decode(data, side: 32)?.bitmap()
            iconPicture.visibility = .visible
        case .none:
            // Arc's dashed "+" until an icon is picked.
            iconGlyph.glyph = WinGlyph.code("plus")
            iconGlyph.opacity = 0.5
            iconGlyph.visibility = .visible
        }
        profileName.text = draft.profile.flatMap { id in store.profiles.first { $0.id == id }?.name } ?? "Default"
        refreshButtons()
    }

    /// Create Space is lit once the name has a character (SpaceCreationDraft.canCreate).
    private func refreshButtons() {
        let on = draft.canCreate
        create.isEnabled = on
        create.background = palette.isDark ? UI.brush(255, 255, 255, alpha: on ? 235 : 60) : UI.brush(20, 20, 24, alpha: on ? 235 : 50)
        createLabel.foreground = palette.isDark ? UI.brush(20, 20, 24, alpha: on ? 255 : 140) : UI.brush(255, 255, 255, alpha: on ? 255 : 170)
    }

    private func rowContent(symbol: String, label: String) -> Grid {
        let grid = Grid()
        for width in [UI.auto, UI.star, UI.auto] { grid.columnDefinitions.append(UI.column(width)) }
        let glyph = FontIcon()
        glyph.glyph = WinGlyph.code(symbol)
        glyph.fontSize = 13
        glyph.width = 32 - L.rowGlyphInset
        glyph.horizontalAlignment = .left
        glyph.verticalAlignment = .center
        rowGlyphs.append(glyph)
        grid.children.append(glyph)
        let text = UI.text(label, size: L.textFont)
        text.fontWeight = UWP.FontWeight(weight: 600)
        text.verticalAlignment = .center
        rowLabels.append(text)
        try? Grid.setColumn(text, 1)
        grid.children.append(text)
        return grid
    }

    private func setUpRow(_ row: Button, content: Grid, top: Double, _ action: @escaping @MainActor () -> Void) {
        row.content = content
        row.height = L.rowHeight
        row.margin = Thickness(left: 0, top: top, right: 0, bottom: 0)
        row.padding = Thickness(left: L.rowGlyphInset, top: 0, right: 8, bottom: 0)
        row.horizontalAlignment = .stretch
        row.horizontalContentAlignment = .stretch
        row.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        row.cornerRadius = CornerRadius(topLeft: L.cornerRadius, topRight: L.cornerRadius, bottomRight: L.cornerRadius, bottomLeft: L.cornerRadius)
        row.clickMode = .press
        row.click.addHandler { _, _ in action() }
    }

    // MARK: The page's panels

    func focusName() {
        guard !ended else { return }
        focusField(name)
    }

    /// The name field's button: the icon picker (Emoji / Icon) on the draft.
    private func showIconPicker() {
        closePanels()
        let picker = SpaceIconPickerView(current: draft.icon, dark: palette.isDark) { [weak self] icon in
            guard let self, !self.ended else { return }
            self.draft.icon = icon
            self.showDraft()
            self.onDraft()
        }
        iconPicker = picker
        picker.show(at: iconButton)
    }

    /// The Profile row: Default and every profile, the draft's ticked.
    private func showProfileMenu() {
        closePanels()
        let menu = MenuFlyout()
        func entry(_ title: String, _ id: UUID?) -> ToggleMenuFlyoutItem {
            let item = ToggleMenuFlyoutItem()
            item.text = title
            item.isChecked = id == draft.profile
            item.click.addHandler { [weak self] _, _ in
                guard let self, !self.ended else { return }
                self.draft.profile = id
                self.showDraft()
            }
            return item
        }
        menu.items.append(entry("Default", nil))
        for p in store.profiles { menu.items.append(entry(p.name, p.id)) }
        profileMenu = menu
        try? menu.showAt(profilePill)
    }

    /// Choose a Theme: Arc's editor against the sidebar's edge, on the draft. Each change shows
    /// on the space at once (SidebarStore.previewSpaceCreation); closing it keeps the theme.
    private func showThemeEditor() {
        closePanels()
        let editor = SpaceStyleEditorView(theme: draft.theme) { [weak self] theme in
            guard let self, !self.ended else { return }
            self.draft.theme = theme
            self.draft.themeChosen = true
            self.store.previewSpaceCreation(self.draft, origin: self.origin)
            self.onDraft()
        } onClose: {}
        self.editor = editor
        editor.show(beside: anchor)
    }

    private func closePanels() {
        try? iconPicker?.flyout.hide()
        try? editor?.flyout.hide()
        try? profileMenu?.hide()
    }

    // MARK: Leaving

    /// Create Space: the space is made on the draft and shown in this window. A name is needed.
    func createSpace() {
        guard !ended, draft.canCreate else { return }
        closePanels()
        guard let id = store.finishSpaceCreation(draft, origin: origin, window: windowID) else { return }
        let done = created
        end()
        done?(id)
    }

    /// Cancel, Escape, or another space picked: the space it was opened on comes back as it was.
    func cancelCreation() {
        guard !ended else { return }
        closePanels()
        store.cancelSpaceCreation(origin: origin, window: windowID)
        end()
    }

    private func end() {
        ended = true
        onEnd()
    }
}

/// SpaceCreationLayout's measures as XAML's Doubles (CGFloat is a type of its own off Apple's
/// platforms).
private enum L {
    static let inset = Double(SpaceCreationLayout.inset)
    static let pictureTop = Double(SpaceCreationLayout.pictureTop)
    static let titleTop = Double(SpaceCreationLayout.titleTop)
    static let titleFont = Double(SpaceCreationLayout.titleFont)
    static let textFont = Double(SpaceCreationLayout.textFont)
    static let fieldHeight = Double(SpaceCreationLayout.fieldHeight)
    static let cornerRadius = Double(SpaceCreationLayout.cornerRadius)
    static let iconSide = Double(SpaceCreationLayout.iconSide)
    static let iconInset = Double(SpaceCreationLayout.iconInset)
    static let pillHeight = Double(SpaceCreationLayout.pillHeight)
    static let infoSide = Double(SpaceCreationLayout.infoSide)
    static let infoInset = Double(SpaceCreationLayout.infoInset)
    static let fieldGap = Double(SpaceCreationLayout.fieldGap)
    static let rowGap = Double(SpaceCreationLayout.rowGap)
    static let buttonBottom = Double(SpaceCreationLayout.buttonBottom)
    static let cancelCentre = Double(SpaceCreationLayout.cancelCentre)
    static let buttonHeight = Double(SpaceCreationLayout.buttonHeight)
    static let rowHeight = Double(SpaceCreationLayout.rowHeight)
    static let rowGlyphInset = Double(SpaceCreationLayout.rowGlyphInset)
    static let pictureWidth = Double(SpaceCreationLayout.pictureSize.width)
    static let pictureHeight = Double(SpaceCreationLayout.pictureSize.height)
}
