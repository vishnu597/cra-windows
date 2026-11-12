import Foundation

/// The actions and their default shortcuts on each platform.
public enum KeyBindingDefaults {
    // Arc's defaults, read from Arc 1.168's menu bar on this Mac (see
    // docs/arc-reverse-engineering.md, "Key bindings"). Items Cra doesn't
    // have (Little Arc, Easels, Split View, Capture) are left out.
    public static let mac: [KeyAction] = {
        let cmd: KeyChord.Modifiers = .command
        let cmdShift: KeyChord.Modifiers = [.command, .shift]
        let cmdOpt: KeyChord.Modifiers = [.command, .option]
        let cmdOptShift: KeyChord.Modifiers = [.command, .option, .shift]
        var list: [KeyAction] = [
            // File
            KeyAction(id: "newTab", name: "New Tab…", section: .file, shortcuts: [KeyChord("t", cmd)], triggers: ["new tab"]),
            KeyAction(id: "newWindow", name: "New Window", section: .file, shortcuts: [KeyChord("n", cmd)], inCommandBar: false),
            // Arc: File ▸ Blank Window ⌃⌘N, a window with a sidebar of its own (#220).
            KeyAction(id: "newBlankWindow", name: "Blank Window", section: .file, shortcuts: [KeyChord("n", [.command, .control] as KeyChord.Modifiers)],
                      triggers: ["blank window", "this window"]),
            KeyAction(id: "newIncognitoWindow", name: "New Incognito Window", section: .file, shortcuts: [KeyChord("n", cmdShift)],
                      triggers: ["incognito", "private"]),
            // Arc: File ▸ New Little Arc Window ⌥⌘N.
            KeyAction(id: "newLittleWindow", name: "New Little Window", section: .file, shortcuts: [KeyChord("n", cmdOpt)], triggers: ["little window", "little arc"]),
            KeyAction(id: "reopenClosedTab", name: "Restore Last Closed Tab", section: .file, shortcuts: [KeyChord("t", cmdShift)], triggers: ["reopen", "undo close", "restore"]),
            KeyAction(id: "editURL", name: "Open Command Bar", section: .file, shortcuts: [KeyChord("l", cmd)], triggers: ["url", "address", "command bar"]),
            KeyAction(id: "newFolder", name: "New Folder", section: .file, shortcuts: [], triggers: ["folder"]),
            KeyAction(id: "newSpace", name: "New Space…", section: .file, shortcuts: [], triggers: ["space"]),
            // Arc: File ▸ New Profile, the dialog Set Profile ▸ New Profile… opens (#279).
            KeyAction(id: "newProfile", name: "New Profile", section: .file, shortcuts: [], triggers: ["profile"]),
            // Arc's command bar: New Boost, the open site's boost.
            KeyAction(id: "newBoost", name: "New Boost", section: .none, shortcuts: [], triggers: ["boost", "restyle", "zap"],
                      symbol: "paintbrush.pointed"),
            // Arc: File ▸ New Easel ⌃⇧E.
            KeyAction(id: "newEasel", name: "New Easel", section: .file, shortcuts: [KeyChord("e", [.control, .shift] as KeyChord.Modifiers)],
                      triggers: ["easel", "whiteboard", "canvas", "draw"]),
            KeyAction(id: "closeWindow", name: "Close Window", section: .file, shortcuts: [KeyChord("w", cmdShift)], inCommandBar: false),
            KeyAction(id: "closeTab", name: "Close Tab", section: .file, shortcuts: [KeyChord("w", cmd)], triggers: ["close", "archive tab"]),
            // Arc: File ▸ Share…, the system's share list for the page (#279).
            KeyAction(id: "share", name: "Share…", section: .file, shortcuts: [], triggers: ["share", "airdrop"]),
            KeyAction(id: "capturePage", name: "Capture…", section: .file, shortcuts: [KeyChord("2", cmdShift)], triggers: ["capture", "screenshot"]),
            // Arc: File ▸ Capture Full Page, Save Page As ⇧⌘S.
            KeyAction(id: "captureFullPage", name: "Capture Full Page", section: .file, shortcuts: [], triggers: ["full page", "screenshot"]),
            KeyAction(id: "capturePortrait", name: "Capture in Portrait Mode", section: .file, shortcuts: [], triggers: ["portrait", "mobile screenshot"]),
            KeyAction(id: "savePageAs", name: "Save Page As", section: .file, shortcuts: [KeyChord("s", cmdShift)], triggers: ["save page", "download page"]),
            KeyAction(id: "print", name: "Print", section: .file, shortcuts: [KeyChord("p", cmd)]),
            // Edit
            KeyAction(id: "copyURL", name: "Copy URL", section: .edit, shortcuts: [KeyChord("c", cmdShift)], triggers: ["copy link"]),
            KeyAction(id: "copyURLMarkdown", name: "Copy URL as Markdown", section: .edit, shortcuts: [KeyChord("c", cmdOptShift)], triggers: ["markdown"]),
            // Arc: Edit ▸ Copy URL as Quote ⌃⇧⌘C, the selection with a link to it.
            KeyAction(id: "copyURLQuote", name: "Copy URL as Quote", section: .edit, shortcuts: [KeyChord("c", [.command, .shift, .control] as KeyChord.Modifiers)], triggers: ["quote", "highlight"]),
            KeyAction(id: "find", name: "Find…", section: .edit, shortcuts: [KeyChord("f", cmd)], triggers: ["find", "search page"]),
            KeyAction(id: "findNext", name: "Find Next", section: .edit, shortcuts: [KeyChord("g", cmd)], inCommandBar: false),
            KeyAction(id: "findPrevious", name: "Find Previous", section: .edit, shortcuts: [KeyChord("g", cmdShift)], inCommandBar: false),
            // Arc: Edit ▸ Find ▸ Use Selection to Find (no key: ⌘E opens extensions) and Jump to Selection ⌘J.
            KeyAction(id: "useSelectionForFind", name: "Use Selection to Find", section: .edit, shortcuts: [], inCommandBar: false),
            KeyAction(id: "jumpToSelection", name: "Jump to Selection", section: .edit, shortcuts: [KeyChord("j", cmd)], inCommandBar: false),
            // View
            KeyAction(id: "toggleSidebar", name: "Hide Sidebar", section: .view, shortcuts: [KeyChord("s", cmd)], triggers: ["sidebar", "hide sidebar", "show sidebar"]),
            KeyAction(id: "toggleToolbar", name: "Hide Toolbar", section: .view, shortcuts: [KeyChord("d", cmdShift)], triggers: ["toolbar"]),
            // Arc: View ▸ Appearance ("Websites, Easels, and Notes will use:"), which turns Arc itself too.
            // Names, aliases and symbols are Arc's command bar entries for those items (#362).
            KeyAction(id: "appearanceAutomatic", name: "Switch to Automatic Appearance", section: .none, shortcuts: [],
                      triggers: ["switch automatic mode", "automatic mode", "system appearance", "website appearance"], symbol: "sparkles"),
            KeyAction(id: "appearanceLight", name: "Switch to Light Mode", section: .none, shortcuts: [],
                      triggers: ["switch light mode", "light mode", "light websites"], symbol: "sun.max"),
            KeyAction(id: "appearanceDark", name: "Switch to Dark Mode", section: .none, shortcuts: [],
                      triggers: ["switch dark mode", "dark mode", "night mode", "dark websites"], symbol: "moon.stars.fill"),
            // Arc: View ▸ Collapse Pinned Tabs / Expand Pinned Tabs.
            KeyAction(id: "collapsePinned", name: "Collapse Pinned Tabs", section: .view, shortcuts: [], triggers: ["collapse pinned", "expand pinned"]),
            KeyAction(id: "stop", name: "Stop Loading", section: .view, shortcuts: [KeyChord(".", cmd)], inCommandBar: false),
            KeyAction(id: "reload", name: "Refresh the Page", section: .view, shortcuts: [KeyChord("r", cmd)], triggers: ["refresh", "reload"]),
            KeyAction(id: "hardReload", name: "Force Refresh the Page", section: .view, shortcuts: [KeyChord("r", cmdShift)]),
            // Arc's command bar (1.171): "clear" lists both, cache first, with a trash glyph.
            KeyAction(id: "clearCache", name: "Clear Cache and Refresh", section: .view, shortcuts: [], symbol: "trash"),
            KeyAction(id: "clearCookies", name: "Clear Cookies and Refresh", section: .view, shortcuts: [], symbol: "trash"),
            // Arc: View ▸ Developer ▸ "Turn on/off Developer Mode for this site" (⌃D).
            KeyAction(id: "toggleDeveloperMode", name: "Toggle Developer Mode for this Site", section: .view, shortcuts: [KeyChord("d", KeyChord.Modifiers.control)], triggers: ["developer mode", "dev mode"]),
            KeyAction(id: "resetZoom", name: "Zoom to Actual Size", section: .view, shortcuts: [KeyChord("0", cmd)], triggers: ["reset zoom"]),
            KeyAction(id: "zoomIn", name: "Zoom In", section: .view, shortcuts: [KeyChord("=", cmd), KeyChord("=", cmdShift)]),
            KeyAction(id: "zoomOut", name: "Zoom Out", section: .view, shortcuts: [KeyChord("-", cmd)]),
            // Arc: View ▸ Developer ▸ Allow JavaScript from Apple Events (AppleScript's `execute`).
            KeyAction(id: "allowAppleEventsJavaScript", name: "Allow JavaScript from Apple Events", section: .none, shortcuts: [],
                      triggers: ["applescript", "apple events"], inCommandBar: false),
            KeyAction(id: "viewSource", name: "View Source", section: .view, shortcuts: [KeyChord("u", cmdOpt)]),
            KeyAction(id: "devTools", name: "Developer Tools", section: .view, shortcuts: [KeyChord("i", cmdOpt), KeyChord(KeyChord.f12, [] as KeyChord.Modifiers)], triggers: ["devtools", "inspect", "console"]),
            KeyAction(id: "inspectElement", name: "Inspect Elements", section: .view, shortcuts: [KeyChord("c", cmdOpt)], inCommandBar: false),
            KeyAction(id: "jsConsole", name: "JavaScript Console", section: .view, shortcuts: [KeyChord("j", cmdOpt)], inCommandBar: false),
            // Arc: Extensions ▸ Picture in Picture (no shortcut); "Open Picture in Picture" in the command bar.
            // Arc: View ▸ Cast; Help ▸ Troubleshooting ▸ Open Task Manager. Chrome's own.
            KeyAction(id: "cast", name: "Cast…", section: .view, shortcuts: [], triggers: ["cast", "chromecast", "airplay"]),
            KeyAction(id: "taskManager", name: "Open Task Manager", section: .help, shortcuts: [], triggers: ["task manager", "memory", "processes"]),
            KeyAction(id: "pictureInPicture", name: "Picture in Picture", section: .view, shortcuts: [], triggers: ["pip", "picture in picture", "pop out", "popout", "video"]),
            // Arc: View ▸ Add Split View ⌃⇧=, Close this Split Pane ⌃⇧-, Separate Page from Split View, Expand Current Split.
            KeyAction(id: "addSplitView", name: "Add Split View", section: .view, shortcuts: [KeyChord("=", [.control, .shift] as KeyChord.Modifiers)], triggers: ["split", "split view", "add split"]),
            KeyAction(id: "closeSplitPane", name: "Close this Split Pane", section: .view, shortcuts: [KeyChord("-", [.control, .shift] as KeyChord.Modifiers)], triggers: ["close split", "close pane"]),
            KeyAction(id: "separateFromSplit", name: "Separate Page from Split View", section: .view, shortcuts: [], triggers: ["separate", "unsplit"]),
            // Arc 1.172: View ▸ Expand Current Split (expandSplitViewPane), no shortcut; the command bar
            // finds it by "Expand; Expand Split View; Maximize" (MainMenu.nib).
            KeyAction(id: "expandSplitPane", name: "Expand Current Split", section: .view, shortcuts: [], triggers: ["expand", "expand split view", "maximize"]),
            KeyAction(id: "flipSplitOrientation", name: "Flip Split View Orientation", section: .view, shortcuts: [], triggers: ["vertical split", "horizontal split", "flip split"]),
            KeyAction(id: "nextSplitPane", name: "Switch to Next Split View", section: .view, shortcuts: [], inCommandBar: false),
            KeyAction(id: "previousSplitPane", name: "Switch to Previous Split View", section: .view, shortcuts: [], inCommandBar: false),
            // Spaces
            KeyAction(id: "nextSpace", name: "Next Space", section: .spaces, shortcuts: [KeyChord(KeyChord.right, cmdOpt)], inCommandBar: false),
            KeyAction(id: "previousSpace", name: "Previous Space", section: .spaces, shortcuts: [KeyChord(KeyChord.left, cmdOpt)], inCommandBar: false),
            KeyAction(id: "editSpace", name: "Edit Space…", section: .spaces, shortcuts: [], triggers: ["theme", "color", "emoji", "edit space"]),
            KeyAction(id: "changeProfile", name: "Change Profile", section: .spaces, shortcuts: [], triggers: ["profile", "change profile", "set profile"]),
            KeyAction(id: "deleteSpace", name: "Delete Space…", section: .spaces, shortcuts: [], triggers: ["delete space", "remove space"]),
            KeyAction(id: "manageSpaces", name: "Manage Spaces…", section: .spaces, shortcuts: [], triggers: ["manage spaces", "reorder spaces"]),
            // Tabs
            KeyAction(id: "pinTab", name: "Pin/Unpin Tab", section: .tabs, shortcuts: [KeyChord("d", cmd)], triggers: ["pin", "unpin"]),
            // Arc: Next Tab ⌥⌘↓ and ⌘}, Previous Tab ⌥⌘↑ and ⌘{ (Settings ▸ Shortcuts).
            KeyAction(id: "nextTab", name: "Next Tab", section: .tabs, shortcuts: [KeyChord(KeyChord.down, cmdOpt), KeyChord("]", cmdShift)], inCommandBar: false),
            KeyAction(id: "previousTab", name: "Previous Tab", section: .tabs, shortcuts: [KeyChord(KeyChord.up, cmdOpt), KeyChord("[", cmdShift)], inCommandBar: false),
            // Arc: Tabs ▸ Reveal Tab in Sidebar; Reveal Current Tab ⌃Space.
            KeyAction(id: "revealTab", name: "Reveal Tab in Sidebar", section: .tabs, shortcuts: [KeyChord(KeyChord.space, KeyChord.Modifiers.control)], triggers: ["reveal", "find tab"]),
            KeyAction(id: "recentTab", name: "Next Recent Tab", section: .tabs, shortcuts: [KeyChord(KeyChord.tab, KeyChord.Modifiers.control)], inCommandBar: false),
            KeyAction(id: "recentTabBackward", name: "Previous Recent Tab", section: .tabs, shortcuts: [KeyChord(KeyChord.tab, [.control, .shift] as KeyChord.Modifiers)], inCommandBar: false),
            KeyAction(id: "clearToday", name: "Clear Today", section: .tabs, shortcuts: [KeyChord("k", cmdShift)], triggers: ["clear", "tidy"]),
            KeyAction(id: "favoriteTab", name: "Add to Favorites", section: .tabs, shortcuts: [], triggers: ["favorite", "top app"]),
            // Arc's Join Meeting ⌃⌘J (Settings ▸ Shortcuts; the command bar's "Join next video conference"):
            // the call from a Calendar favorite's Live Calendar.
            KeyAction(id: "joinNextMeeting", name: "Join Meeting", section: .none, shortcuts: [KeyChord("j", [.control, .command] as KeyChord.Modifiers)],
                      triggers: ["join", "meeting", "video call", "join next video conference"]),
            KeyAction(id: "renameTab", name: "Rename Tab…", section: .tabs, shortcuts: [], triggers: ["rename"]),
            KeyAction(id: "duplicateTab", name: "Duplicate Tab", section: .tabs, shortcuts: [], triggers: ["duplicate"]),
            KeyAction(id: "resetTab", name: "Reset Pinned Tab", section: .tabs, shortcuts: [], triggers: ["reset", "home"]),
            KeyAction(id: "muteTab", name: "Mute / Unmute Tab", section: .tabs, shortcuts: [], triggers: ["mute"]),
            KeyAction(id: "resetSpaceTabs", name: "Reset all tabs in this Space", section: .tabs, shortcuts: [], triggers: ["reset all", "reset pinned"]),
            // Arc lists these in Settings ▸ Shortcuts and the command bar only.
            KeyAction(id: "collapseAllFolders", name: "Collapse All Folders", section: .none, shortcuts: [], triggers: ["collapse folders", "close folders"]),
            KeyAction(id: "expandAllFolders", name: "Expand All Folders", section: .none, shortcuts: [], triggers: ["expand folders", "open folders"]),
            KeyAction(id: "manageExtensions", name: "Manage Extensions…", section: .none, shortcuts: [], triggers: ["manage extensions", "chrome extensions"], symbol: "puzzlepiece.extension"),
            KeyAction(id: "openExtensions", name: "Open Extensions", section: .none, shortcuts: [KeyChord("e", cmd)], triggers: ["extensions", "site controls"]),
            // Archive
            KeyAction(id: "goBack", name: "Go Back", section: .archive, shortcuts: [KeyChord("[", cmd), KeyChord(KeyChord.left, cmd)]),
            KeyAction(id: "goForward", name: "Go Forward", section: .archive, shortcuts: [KeyChord("]", cmd), KeyChord(KeyChord.right, cmd)]),
            KeyAction(id: "viewArchive", name: "View History", section: .archive, shortcuts: [KeyChord("y", cmd)], triggers: ["archive", "history", "closed tabs"]),
            // Arc: Archive ▸ View Archive…, Clear Archive.
            KeyAction(id: "showArchive", name: "View Archive…", section: .archive, shortcuts: [], triggers: ["archive", "archived tabs"]),
            KeyAction(id: "clearArchive", name: "Clear Archive", section: .archive, shortcuts: [], triggers: ["clear archive"], symbol: "trash"),
            // Window
            KeyAction(id: "openLibrary", name: "Open Library…", section: .window, shortcuts: [KeyChord("l", cmdShift)], triggers: ["library"]),
            KeyAction(id: "viewDownloads", name: "View Downloads…", section: .window, shortcuts: [KeyChord("j", cmdShift)], triggers: ["downloads"]),
            // Arc: Window ▸ View Boosts….
            KeyAction(id: "viewBoosts", name: "View Boosts…", section: .window, shortcuts: [], triggers: ["boosts"]),
            // Arc: Window ▸ View Easels….
            KeyAction(id: "viewEasels", name: "View Easels…", section: .window, shortcuts: [], triggers: ["easels"]),
            // Arc: Window ▸ View Media….
            KeyAction(id: "viewMedia", name: "View Media…", section: .window, shortcuts: [], triggers: ["media", "screenshots", "photos"]),
            // Arc: Window ▸ Stay On Top.
            KeyAction(id: "stayOnTop", name: "Stay On Top", section: .window, shortcuts: [], triggers: ["stay on top", "float", "always on top", "pin window"]),
            // Arc's Tabs ▸ "Open Little Arc or Peek in" (openTabIn), the Little Arc's "Open in <space>" button;
            // the menu row reads "Open in <space>" (TabsMenu).
            KeyAction(id: "promoteLittleWindow", name: TabsMenu.openInName, section: .tabs, shortcuts: [KeyChord("o", cmd)], inCommandBar: false),
            // Arc: Show Little Arc "Open In" Menu ⇧⌘O.
            KeyAction(id: "littleWindowOpenInMenu", name: "Show Little Window “Open In” Menu", section: .window,
                      shortcuts: [KeyChord("o", cmdShift)], inCommandBar: false),
            KeyAction(id: "closeLittleWindows", name: "Close Little Windows", section: .window, shortcuts: [], triggers: ["close little"]),
            // App
            KeyAction(id: "settings", name: "Settings…", section: .app, shortcuts: [KeyChord(",", cmd)], triggers: ["preferences", "settings"]),
            // Arc's app menu shows ⌘♡ beside it, a glyph no key types (see buildMenus).
            KeyAction(id: "setDefaultBrowser", name: "Set as Default Browser", section: .app, shortcuts: [], triggers: ["default browser"]),
            KeyAction(id: "importData", name: "Import from Arc or Dia…", section: .app, shortcuts: [], triggers: ["import", "arc", "dia"]),
            KeyAction(id: "rebuildArcProfiles", name: "Rebuild Profiles from Arc…", section: .app, shortcuts: [], triggers: ["profiles", "arc profiles"]),
            // Chrome's app menu item and key; Arc has neither, only Settings ▸ Profiles ▸ Clear Browsing Data.
            KeyAction(id: "clearBrowsingData", name: "Clear Browsing Data…", section: .app, shortcuts: [KeyChord(KeyChord.delete, cmdShift)],
                      triggers: ["clear history", "delete history", "clear browsing data", "delete browsing data"], symbol: "trash"),
            // Arc's Translate bubble item "Language Settings": Chromium's page, in the space's profile (#209).
            KeyAction(id: "languageSettings", name: "Language Settings", section: .app, shortcuts: [],
                      triggers: ["language", "languages", "preferred language", "accept language"], symbol: "globe"),
            KeyAction(id: "checkForUpdates", name: "Check for Updates…", section: .app, shortcuts: [],
                      triggers: ["update", "upgrade", "new version"], symbol: "arrow.down.circle"),
            // Arc: Help ▸ Essential Keyboard Shortcuts.
            KeyAction(id: "essentialShortcuts", name: "Essential Keyboard Shortcuts", section: .help, shortcuts: [],
                      triggers: ["shortcuts", "keyboard shortcuts", "hotkeys"], symbol: "keyboard"),
            // Arc: Help ▸ Troubleshooting ▸ Reveal Arc Data, Copy Arc Info.
            KeyAction(id: "revealData", name: "Reveal Cra Data", section: .help, shortcuts: [], triggers: ["data folder", "reveal data"]),
            KeyAction(id: "copyAppInfo", name: "Copy Cra Info", section: .help, shortcuts: [], triggers: ["version", "copy info"]),
        ]
        // Arc: Switch to Split View 1–4 (⌃⇧1…4), the panes of the open split.
        for n in 1...4 {
            list.append(KeyAction(id: "splitPane\(n)", name: "Switch to Split View \(n)", section: .none,
                                  shortcuts: [KeyChord("\(n)", [.control, .shift] as KeyChord.Modifiers)], inCommandBar: false))
        }
        for n in 1...9 {
            // Arc: ⌘9 is "Go to last Sidebar Item", as in Chrome.
            list.append(KeyAction(id: "item\(n)", name: n == 9 ? "Go to Last Tab" : "Go to Tab \(n)", section: .tabs,
                                  shortcuts: [KeyChord("\(n)", cmd)], triggers: ["\(n). tab", "\(n). item"], inCommandBar: false))
            list.append(KeyAction(id: "space\(n)", name: "Go to Space \(n)", section: .spaces,
                                  shortcuts: [KeyChord("\(n)", KeyChord.Modifiers.control)], inCommandBar: false))
        }
        // Arc has no default for this (its command bar's "Move to Today in <space>" has no key);
        // ⌃⌘N adds ⌘ to Go to Space N (#86). Neither Arc nor macOS binds ⌃⌘1–9.
        for n in 1...9 {
            list.append(KeyAction(id: "moveTabToSpace\(n)", name: "Move Tab to Space \(n)", section: .spaces,
                                  shortcuts: [KeyChord("\(n)", [.command, .control] as KeyChord.Modifiers)], inCommandBar: false))
        }
        return list
    }()

    /// Windows' table: the Mac's actions the Windows app has so far, in the Mac's order, with
    /// Windows' keys. On Windows a chord's `.control` bit is Ctrl and `.option` is Alt (the keys
    /// the bits are named after); `.command` would be the Windows key, which no default uses.
    /// ⌘ becomes Ctrl, and where that collides or Windows has its own convention the key is
    /// Chrome's on Windows: Alt+Left and Right go back and forward, Ctrl+Tab cycles tabs in
    /// sidebar order (Windows has no tab switcher yet), F3 and F5 keep their meaning. Spaces take
    /// Arc for Windows' keys: Ctrl+Alt+Left and Right page them, Alt+1–9 go to one (Ctrl+1–9 is
    /// already Go to Tab, as in Chrome).
    public static let windows: [KeyAction] = mac.compactMap { action in
        windowsShortcuts[action.id].map { keys in
            var a = action
            a.shortcuts = keys
            return a
        }
    }

    /// Action id to Windows' default shortcuts. An action joins when the Windows app performs it.
    public static let windowsShortcuts: [String: [KeyChord]] = {
        let ctrl: KeyChord.Modifiers = .control
        let ctrlShift: KeyChord.Modifiers = [.control, .shift]
        let ctrlAlt: KeyChord.Modifiers = [.control, .option]
        let alt: KeyChord.Modifiers = .option
        var table: [String: [KeyChord]] = [
            "newTab": [KeyChord("t", ctrl)],
            "newWindow": [KeyChord("n", ctrl)],
            "newIncognitoWindow": [KeyChord("n", ctrlShift)],
            "closeWindow": [KeyChord("w", ctrlShift)],
            "reopenClosedTab": [KeyChord("t", ctrlShift)],
            "editURL": [KeyChord("l", ctrl)],
            "closeTab": [KeyChord("w", ctrl)],
            "capturePage": [KeyChord("2", ctrlShift)],
            "copyURL": [KeyChord("c", ctrlShift)],
            "copyURLMarkdown": [KeyChord("c", [.control, .option, .shift] as KeyChord.Modifiers)],
            "find": [KeyChord("f", ctrl)],
            "findNext": [KeyChord("g", ctrl), KeyChord(KeyChord.function(3), [] as KeyChord.Modifiers)],
            "findPrevious": [KeyChord("g", ctrlShift), KeyChord(KeyChord.function(3), KeyChord.Modifiers.shift)],
            "reload": [KeyChord("r", ctrl), KeyChord(KeyChord.function(5), [] as KeyChord.Modifiers)],
            "hardReload": [KeyChord("r", ctrlShift), KeyChord(KeyChord.function(5), ctrl)],
            "addSplitView": [KeyChord("=", ctrlShift)],
            "closeSplitPane": [KeyChord("-", ctrlShift)],
            "separateFromSplit": [],
            "flipSplitOrientation": [],
            "nextSplitPane": [],
            "previousSplitPane": [],
            "nextSpace": [KeyChord(KeyChord.right, ctrlAlt)],
            "previousSpace": [KeyChord(KeyChord.left, ctrlAlt)],
            "changeProfile": [],
            "newProfile": [],
            "share": [],
            "pinTab": [KeyChord("d", ctrl)],
            "nextTab": [KeyChord(KeyChord.tab, ctrl)],
            "previousTab": [KeyChord(KeyChord.tab, ctrlShift)],
            "goBack": [KeyChord(KeyChord.left, alt)],
            "goForward": [KeyChord(KeyChord.right, alt)],
            "settings": [KeyChord(",", ctrl)],
            // Chrome's DevTools keys on Windows. Its Inspect key, Ctrl+Shift+C, is Copy URL here as
            // in Arc, and Ctrl+Alt+C would take AltGr+C from layouts that type with it: none.
            "devTools": [KeyChord("i", ctrlShift), KeyChord(KeyChord.function(12), [] as KeyChord.Modifiers)],
            "jsConsole": [KeyChord("j", ctrlShift)],
            "inspectElement": [],
            // The Mac's ⌃D is Pin Tab's Ctrl+D here, so Shift joins it (Chrome's Bookmark All Tabs,
            // which Cra doesn't have).
            "toggleDeveloperMode": [KeyChord("d", ctrlShift)],
            "clearCache": [],
            "clearCookies": [],
            // Arc for Windows' Little Arc key. Where AltGr+N types a letter (Polish ń), Cra lets it
            // type (WinKeyboard.typesCharacter) and doesn't take it from other apps.
            "newLittleWindow": [KeyChord("n", ctrlAlt)],
            "promoteLittleWindow": [KeyChord("o", ctrl)],
            "closeLittleWindows": [],
            // The Library: Ctrl+Shift+L as on the Mac; history and downloads take Chrome's keys.
            "openLibrary": [KeyChord("l", ctrlShift)],
            "viewArchive": [KeyChord("h", ctrl)],
            "viewDownloads": [KeyChord("j", ctrl)],
            // Registers Cra and opens Windows' Default apps page for it (PR 9).
            "setDefaultBrowser": [],
        ]
        for n in 1...9 {
            table["item\(n)"] = [KeyChord("\(n)", ctrl)]
            table["space\(n)"] = [KeyChord("\(n)", alt)]
        }
        return table
    }()
}

/// One-line descriptions for the Shortcuts pane's detail column (Dia: "Create a new tab.").
public enum ShortcutDescriptions {
    public static func text(for a: KeyAction, custom: String? = nil) -> String {
        if let custom { return custom }
        if let t = table[a.id] { return t }
        if a.id.hasPrefix("item"), let n = a.id.dropFirst(4).first { return "Switch to the \(n). tab in the sidebar." }
        if a.id.hasPrefix("space"), let n = a.id.dropFirst(5).first { return "Switch to the \(n). space." }
        if a.id.hasPrefix("splitPane"), let n = a.id.dropFirst(9).first { return "Switch to the \(n). pane of the open split." }
        if a.id.hasPrefix("moveTabToSpace"), let n = a.id.dropFirst(14).first { return "Move the current tab, or a Little Window's page, to the \(n). space and switch to it." }
        return a.name + "."
    }

    private static let table: [String: String] = [
        // Upstream's Arc parity sweep (#28).
        "newEasel": "Create an Easel, a canvas for text, shapes, drawings and captures.",
        "captureFullPage": "Capture the whole page, top to bottom.",
        "capturePortrait": "Capture the page as a phone would show it.",
        "savePageAs": "Save the page to a file.",
        "copyURLQuote": "Copy the selected text with a link to it.",
        "useSelectionForFind": "Search the page for the selected text.",
        "jumpToSelection": "Scroll the selected text into view.",
        "appearanceAutomatic": "Websites follow your system's light or dark appearance.",
        "appearanceLight": "Websites always show their light appearance.",
        "appearanceDark": "Websites always show their dark appearance.",
        "collapsePinned": "Collapse or expand the pinned tabs.",
        "cast": "Cast the page to a device on your network.",
        "taskManager": "Open Chromium's task manager to see what each page uses.",
        "revealTab": "Scroll the sidebar to the open tab.",
        "resetSpaceTabs": "Take every pinned tab in this space back to its pinned page.",
        "collapseAllFolders": "Close every folder in the space.",
        "expandAllFolders": "Open every folder in the space.",
        "manageExtensions": "Open the page that lists your extensions.",
        "openExtensions": "Open the Extensions menu for this page.",
        "showArchive": "Open the Library's Archived Tabs.",
        "clearArchive": "Remove every archived tab.",
        "viewEasels": "Open the Library's Easels.",
        "viewBoosts": "Open the Library's Boosts.",
        "newBoost": "Create a Boost that restyles the site you're on.",
        "allowAppleEventsJavaScript": "Let AppleScript run JavaScript in your tabs.",
        "joinNextMeeting": "Join the next video call on your Calendar favorite's Live Calendar.",
        "viewMedia": "Open the Library's Media: screenshots, pictures and videos.",
        "stayOnTop": "Keep this window above other apps' windows.",
        "littleWindowOpenInMenu": "Show where a Little Window's page can open.",
        "essentialShortcuts": "Show a card with five shortcuts worth knowing.",
        "revealData": "Show Cra's data folder.",
        "copyAppInfo": "Copy Cra's version and system details, for a bug report.",
        "newTab": "Create a new tab.",
        "newWindow": "Open a new window.",
        "newBlankWindow": "Open a window with a sidebar of its own, apart from your spaces.",
        "newIncognitoWindow": "Open a window that keeps no history, cookies or tabs once closed.",
        "newLittleWindow": "Open a small, disposable window for a quick look.",
        "reopenClosedTab": "Bring back the tab you closed last.",
        "editURL": "Open the command bar to search or enter a URL.",
        "newFolder": "Create a folder in the sidebar.",
        "newProfile": "Create a browser profile with separate logins and site data.",
        "share": "Open the system share list for the current page.",
        "newSpace": "Create a new space.",
        "closeWindow": "Close the current window.",
        "closeTab": "Close the current tab.",
        "capturePage": "Take a screenshot of the page.",
        "print": "Print the page.",
        "copyURL": "Copy the page’s URL.",
        "copyURLMarkdown": "Copy the page’s title and URL as a Markdown link.",
        "find": "Search for text on the page.",
        "findNext": "Jump to the next match.",
        "findPrevious": "Jump to the previous match.",
        "toggleSidebar": "Show or hide the sidebar.",
        "toggleToolbar": "Show or hide the toolbar above the page.",
        "stop": "Stop loading the page.",
        "reload": "Reload the page.",
        "hardReload": "Reload the page, ignoring cached content.",
        "clearCache": "Clear the browser cache and reload the page.",
        "clearCookies": "Clear this site’s cookies and reload the page.",
        "toggleDeveloperMode": "Show the full URL and developer tools for this site.",
        "resetZoom": "Return the page to its actual size.",
        "zoomIn": "Make the page larger.",
        "zoomOut": "Make the page smaller.",
        "viewSource": "Show the page’s source.",
        "devTools": "Open the developer tools.",
        "inspectElement": "Open the developer tools on the Elements panel.",
        "jsConsole": "Open the developer tools on the Console panel.",
        "pictureInPicture": "Pop the playing video out into a floating window.",
        "addSplitView": "Open another page beside this one.",
        "closeSplitPane": "Close the focused split pane.",
        "separateFromSplit": "Move the page out of the split view into its own tab.",
        "expandSplitPane": "Give the focused split pane the window, leaving the other panes narrow.",
        "flipSplitOrientation": "Switch the split view between side by side and stacked.",
        "nextSplitPane": "Focus the next split pane.",
        "previousSplitPane": "Focus the previous split pane.",
        "nextSpace": "Switch to the next space.",
        "previousSpace": "Switch to the previous space.",
        "editSpace": "Change the space’s name, emoji and theme.",
        "changeProfile": "Pick the profile the space’s sign-ins, cookies and extensions come from.",
        "deleteSpace": "Delete the current space.",
        "manageSpaces": "Open the Library’s Spaces page: every space side by side, to reorder or edit them.",
        "pinTab": "Pin the tab or unpin it.",
        "nextTab": "Switch to the next tab.",
        "previousTab": "Switch to the previous tab.",
        "recentTab": "Open the tab switcher and cycle through recent tabs, like ⌘Tab for apps.",
        "recentTabBackward": "Cycle backwards through recent tabs in the tab switcher.",
        "clearToday": "Archive all of today’s tabs.",
        "favoriteTab": "Add the tab to the favorites grid.",
        "renameTab": "Give the tab a name of your own.",
        "duplicateTab": "Open a copy of the tab.",
        "resetTab": "Return a pinned tab to its original URL.",
        "muteTab": "Mute or unmute the tab.",
        "goBack": "Go back a page.",
        "goForward": "Go forward a page.",
        "viewArchive": "Open the archive of closed tabs.",
        "openLibrary": "Open the Library.",
        "viewDownloads": "Show your downloads.",
        "promoteLittleWindow": "Move the Little Window’s or Peek’s page into the space its Open in button names.",
        "closeLittleWindows": "Close all Little Windows.",
        "settings": "Open Settings.",
        "setDefaultBrowser": "Make Cra the default browser.",
        "importData": "Bring tabs, spaces and extensions over from Arc or Dia.",
        "rebuildArcProfiles": "Put spaces imported from Arc back on their Arc profiles, with their sign-ins and extensions.",
        "clearBrowsingData": "Delete history, cookies and cached files with Chrome’s dialog.",
        "languageSettings": "Choose the languages websites show their pages in, for this space’s profile.",
        "checkForUpdates": "Look for a newer version of Cra.",
    ]
}
