# Mac feature parity

Every feature of the Mac app, what the Windows app has of it, and where the code that both
can share lives. The goal is the Mac app's features on Windows, built on the Mac's own logic:
what decides something goes in CraCore once and both shells call it (CLAUDE.md, rule 1).

<!-- upstream-reviewed: f547bd8 -->
Upstream reviewed through **3e2757b** (VictorKildahl/cra main, 7 Nov 2026). Fork main has
merged upstream through 3e2757b (#28).

**Status:** ✅ on Windows · 🟡 partly · 🔜 in review · ❌ not yet · ➖ Mac only, or replaced by a
Windows counterpart

**Sources:** the Mac code (the files named in each row), the upstream history, and the site's
[release notes](https://crabrowser.app/release-notes) and [changelog](https://crabrowser.app/changelog),
which say in users' words how each feature behaves. For look and feel: [brand](https://crabrowser.app/brand),
[design notes](https://crabrowser.app/design-notes), `brand/` and `docs/arc-reverse-engineering.md`.

## Summary

<!-- summary: parity.py summary --write -->
| Area | ✅ | 🟡 | 🔜 | ❌ | ➖ |
|---|--:|--:|--:|--:|--:|
| Window, pages and toolbar | 6 | 3 | 0 | 13 | 1 |
| Sidebar | 5 | 5 | 0 | 15 | 0 |
| Command bar and shortcuts | 3 | 1 | 0 | 2 | 0 |
| Split view | 1 | 1 | 0 | 1 | 0 |
| Little Windows, Peek and the Library | 2 | 4 | 0 | 4 | 0 |
| Tabs and memory | 1 | 1 | 0 | 3 | 0 |
| Media and capture | 0 | 2 | 0 | 2 | 1 |
| Profiles, privacy and site data | 3 | 1 | 0 | 8 | 0 |
| DevTools and Developer Mode | 2 | 0 | 0 | 1 | 0 |
| Extensions | 0 | 0 | 0 | 5 | 0 |
| Settings | 4 | 1 | 0 | 4 | 0 |
| Import and onboarding | 0 | 0 | 0 | 5 | 1 |
| Arc Max (on-device AI) | 0 | 0 | 0 | 0 | 3 |
| System integration and release | 3 | 0 | 1 | 8 | 3 |
| **All** | 30 | 19 | 1 | 71 | 9 |
<!-- /summary -->

## Window, pages and toolbar

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Browser window with pages inside it (CEF child windows), crash-safe start | ✅ [#2] [#3] | `main.swift`, `AppDelegate.swift`, `AppComposition.swift`, `MainWindowController.swift`, `ShellView.swift`, `BrowserManager.swift`, `EmbeddedPages.swift`, `ChromiumWindowCorners.swift`, `ChromiumChildHover.swift`, `ChromiumChildFullscreen.swift`, `WindowDragGesture.swift`, `CraCEF.mm`, `CraCEF.h`, `main.cc` | `ChromiumCrashState`, `JSONStore`, `Scheduling`, `ObserveChanges` | Windows: `HostWindow`, `CraCEFWin.cpp`. Missing: Settings' edge-to-edge pages, Escape leaves video fullscreen (check). |
| More than one window, window frames saved in `windows.json` | ✅ [#18] | `MainWindowController.swift` | `WindowFrame`, `SpaceWindow` | `SpaceWindow` picks the window a Little Window's page goes to (#23); `moveTabToSpaceN` still waits for a key. |
| Private (incognito) windows | ✅ [#18] | `BrowserManager.swift` | `SidebarStore` | |
| Blank Window (`newBlankWindow`, "This Window" with a sidebar of its own); a tab dragged out of the window opens in one | ❌ | `AppDelegate.swift`, `MainWindowController.swift`, `SidebarRowViews.swift` | `BlankWindow`, `TabTearOff`, `SidebarStore` (`addBlankWindow`, `moveToBlankWindow`, `isStandalone`) | Upstream #220, #219 (f1d9c56, 9de5a59). The store already saves Blank Windows' spaces outside `spaceOrder`, so Windows needs the window, its header and the drag out of the sidebar (which waits for drag and drop). |
| Toolbar: optional (`toggleToolbar`), host-only address, Show Full URL, reload that turns into stop (`stop`), tab colour, link-copy glyph | ❌ | `PaneToolbarView.swift`, `AppKitControls.swift` | `ToolbarComposition`, `ToolbarColor`, `ToolbarExtensionFit` | Off by default as on the Mac, so it comes after the sidebar's address pill. Composition and colour decisions are already shared. Upstream 87ab765 and 15c5913 set Arc's 36 pt button pitch and right-end spacing (`ToolbarComposition`). |
| Loading bar at the top middle of the window | ❌ | `LoadingIndicatorView.swift` | `LoadingIndicator` | Small: drive a XAML bar from `LoadingIndicator`. |
| Hide the sidebar (`toggleSidebar`) and the floating sidebar that slides in from the left edge | ❌ | `FloatingSidebar.swift`, `FloatingSidebarGeometry.swift` | (move `FloatingSidebarGeometry` here) | `FloatingSidebarGeometry` is a CLAUDE.md known exception: move it to CraCore with this PR. Since upstream ba0bd0f the Mac slides it with Arc's measured ⌘S motion (`SidebarMotion`). |
| Drag the window from the top of a page (on by default, as in Arc) | ❌ | `MainWindowController.swift` | `PageTopDrag` | Upstream 3b6b27d. Windows: a press in the page's top strip starts the move (WM_NCLBUTTONDOWN with HTCAPTION). |
| Clicks land under the pointer while Chrome's debugger bar shows (#241) | ❌ | `CraCEF.mm` | `PageViewInsets` | Upstream 7675257: the Mac page view moved down by the bar. Check on Windows when extensions that debug pages (#228) run. |
| Find in page with match count | ✅ [#10] | `Overlays.swift` | `FindInPage` | |
| Toasts (copied URL with Share, captures, downloads) | ✅ [#17] | `ShinyToast.swift`, `Overlays.swift` | `ToastStyle` | Share button on Windows needs the Windows share sheet (DataTransferManager). |
| Site Control Center, lock badge and certificate viewer | ✅ [#17] | `SiteControlCenter.swift`, `CertificateWindow.swift` | `SiteControlCenter`, `ConnectionSecurity`, `PageCapture` | Missing: the protected-media card (Mac only, see Media). Since upstream 8dbd6d1 (#226) the sliders show without extensions too; Windows already shows them in the sidebar's address pill. |
| Zoom (`zoomIn`, `zoomOut`, `resetZoom`), `print`, `viewSource` | 🟡 | `AppDelegate.swift` | `KeyBindingDefaults` | Left to Chromium's own keys on Windows: not in Cra's key table, the command bar or Settings ▸ Shortcuts. Add them to `KeyBindingDefaults.windowsShortcuts`. |
| Page context menu: Open Link in New Tab / Background Tab | 🟡 | `BrowserManager.swift` | `LinkMenu` | Chromium's menu shows; Cra's two items and the background setting are missing. |
| Arc-style tooltips in the space's tones | ❌ | `ArcTooltip.swift` | `ThemeTones` (`TooltipTones`) | Windows uses plain WinUI tooltips. |
| Theme, metrics and the brand mark | 🟡 | `Theme.swift`, `Tuning.swift`, `BrandMark.swift` | `SpaceTheme`, `ThemeTones` | Sidebar palette from `SpaceTheme` is shared; Windows has its own metrics. Brand mark from `brand/`. |
| Sidebar blur, Reduce transparency, active/inactive look | ❌ | `ActiveAppearanceProbe.swift` | `SidebarBackdrop` | Windows counterpart: Mica or Acrylic, and Windows' transparency setting. Since f6b9fb6 a full-screen window keeps its active look while its Space slides away (AppKit's own answer, `windowActive(activeAppearance:)`). |
| Only one Cra running (an older copy quits) | ➖ | `NewestCopy.swift` | | Windows: a single-instance mutex when the installer lands. |
| Arc's dialog sheet for every confirmation: one card, its buttons, keys and hover | ❌ | `AppDialog.swift`, `DialogComponents.swift`, `Colors.swift` | `DialogActions` | Upstream bc47470 (#224). Windows asks with WinUI flyouts and dialogs; `DialogActions` (which button Return and Escape press) is shared for the Windows card. `Colors.swift` is SwiftUI's hex colours. |
| Stay On Top (`stayOnTop`), Save Page As (`savePageAs`), Copy URL as Quote (`copyURLQuote`), Copy URL without trackers | ❌ | `MainWindowController.swift`, `AppDelegate.swift` | `CleanURL` | Upstream d110dc6. Windows' Copy URL copies the address as it is: call `CleanURL` there first. Stay On Top: `HWND_TOPMOST`. |
| Find ▸ Use Selection to Find (`useSelectionForFind`), Jump to Selection (`jumpToSelection`) | ❌ | `MainWindowController.swift` | `FindInPage` | Upstream 894f1f6. Windows' find bar would take the page's selection. |
| What websites see: View ▸ Appearance (`appearanceAutomatic`, `appearanceLight`, `appearanceDark`), sound effects, "Allow websites to get your theme data" | ❌ | `AppDelegate.swift`, `BrowserManager.swift`, `AdvancedPane.swift`, `CraCEF.mm` | `SidebarModel` (`WebsiteAppearance`), `ArcThemeData`, `ThemeTones`, `SidebarStore` (`themeDataCSS`) | Upstream 35bc84a, bfd9962. The settings are in the shared `settings.json`; Windows needs the CEF colour-scheme call and the `:root` style injection. |
| "When opening Cra, restore windows from previous session" | ❌ | `AppDelegate.swift`, `AdvancedPane.swift` | `SidebarModel` (`restoreWindows`), `SidebarStore` | Upstream 337d5f8. Windows always restores its windows; read the setting with the Advanced pane. |

## Sidebar

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Spaces: switch, create, delete, the space dock | ✅ [#5] | `SidebarView.swift`, `SidebarRootView.swift`, `SpaceDock.swift`, `SpaceListView.swift`, `SpaceColumnView.swift`, `SidebarUIState.swift` | `SidebarStore`, `SidebarModel`, `ItemTable`, `SidebarIntegrity` | Same `sidebar.json` as the Mac. |
| Go to Space N (`spaceN`) on Alt+1–9, next and previous space on Ctrl+Alt+Right and Left | ✅ [#5] [#21] | `MainWindowController.swift`, `AppDelegate.swift` | `KeyBindingDefaults`, `SidebarStore` (`focusSpace(number:)`) | Arc for Windows' keys: Ctrl+1–9 stays Go to Tab, as in Chrome. |
| Move Tab to Space N (`moveTabToSpaceN`) | ❌ | `MainWindowController.swift`, `AppDelegate.swift` | `SpaceWindow`, `SidebarStore` | No Windows key yet (the Mac's is ⌃⌘N); comes with Little Windows, whose page it can also send. |
| Swipe, Shift + wheel or sideways wheel between spaces | ❌ | `SpacePagerView.swift` | `WheelSpaceSwitch` | Decision shared; Windows needs the wheel hook and the slide. |
| Pinned tabs and folders, Today, Clear Today, archive on close | ✅ [#5] | `SidebarRowViews.swift`, `SidebarItemView.swift` | `SidebarStore`, `CloseSuccessor`, `SidebarClose`, `PinnedPeek` | `clearToday` and `newFolder` are in the sidebar menus, not yet commands; `SidebarClose` (Arc's close buttons per row kind) isn't used on Windows yet. |
| Pinned tab extras: back to its page by the favicon, the slash, Reset (`resetTab`), edit URL | ❌ | `EditPinnedURLDialog.swift`, `SidebarRowViews.swift` | `PinnedNavigation` | Since 6e371cc "Back to Pinned URL" slides in under the title on hovering the icon (0.16 s). |
| Folders: hinge animation, hover previews with search, tabs shown under a closed folder | 🟡 | `FolderPreview.swift`, `FolderGlyphView.swift` | `FolderPeek` | Windows has folders without previews or the animation. Since upstream 11ff4c9 (#234) the folder's emblem follows its front panel's perspective. |
| Favorites | 🟡 [#5] | `SidebarRowViews.swift`, `TileColor.swift` | `FavoritesLayout`, `FavoritesSharing` | Missing: 4/2/1 columns by width (`FavoritesLayout`), tile colours and icons, "Drag to add Favorites" card, Settings' share-across-spaces switch. |
| Drag and drop: reorder, into folders and favorites, onto a space's icon, several picked tabs at once, reorder spaces | ❌ | `SidebarListDrop.swift`, `SpaceListView.swift` | `SidebarStore` | The store's moves are shared; the XAML drag layer is the work. Big item. Since 1f3c3d3 a tab dropped on any tab, pinned too, offers a split (no folder drop); since dfa3358 rows keep their hover through AppKit's stray exits (Mac only). |
| Space menu: rename, icon, theme, profile, folder, export, delete | 🟡 [#5] [#19] | `MainWindowController+SpaceMenu.swift`, `SidebarMenus.swift`, `SpaceIconPicker.swift`, `EmojiCatalog.swift`, `EmojiCatalog+Data.swift` | `SpaceProfiles`, `SpaceIcon` | Since upstream 8f511ac (#205) a space's icon can be a symbol (`Space.symbol`, `SpaceIcon`); Windows draws the emoji only. Windows has New Folder, New Space, Clear Today, Hide Space Header, Set Profile, Delete. Missing `editSpace`, `deleteSpace` and `newSpace` as commands, rename, the emoji picker. `EmojiCatalog+Data.swift` has no imports: move it to CraCore for the Windows picker. |
| Space theme editor: Arc's presets, light and dark halves, grain | ❌ | `SpaceStyleEditor.swift`, `SpaceEditorView.swift` | `SpaceTheme`, `SpaceThemeVariants`, `SpaceColorPresets`, `ArcThemeImport` | Windows draws themes it reads; editing is missing. The colour logic is all shared. Since 6e371cc swatches and knobs grow under the pointer and shrink when pressed. |
| Manage Spaces page (`manageSpaces`) | ❌ | `SpacesManagerView.swift` | `SidebarStore` | |
| Space tooltip with its profile and keys | ❌ | `SpaceDock.swift`, `ArcTooltip.swift` | `ThemeTones` | |
| Jump pill back to the open tab | ❌ | `SidebarJumpPill.swift` | | |
| Rename (`renameTab`), duplicate (`duplicateTab`), Add to Favorites (`favoriteTab`) as commands | 🟡 | `SidebarMenus.swift` | `SidebarStore` | Duplicate and favorites are in the row menu; rename is missing; none are commands yet. |
| Arc's other sidebar actions: Collapse Pinned Tabs (`collapsePinned`), Collapse and Expand All Folders (`collapseAllFolders`, `expandAllFolders`), Reveal Tab in Sidebar (`revealTab`), Reset all tabs in this Space (`resetSpaceTabs`), Archive Tabs Below, Change Icon…, Share ▸ | ❌ | `SidebarMenus.swift`, `MainWindowController.swift`, `SiteControlCenter.swift` | `SidebarStore` (`setAllFoldersExpanded`, `revealInSidebar`, `archiveTabsBelow`) | Upstream d110dc6, 6f3f298. The store side is shared; Windows needs the menu items and commands. |
| Unread dots and theme colours | ✅ [#5] | `SidebarRowViews.swift` | `SidebarModel` | |
| Tab row on hover: the name runs to 13 pt before the close button (#243) | ❌ | `SidebarRowViews.swift` | `TabRowTrailing` | Upstream 12ab4cf. Windows' row keeps a fixed gap; use `TabRowTrailing`'s insets. |
| Mouse back and forward buttons over the sidebar switch spaces (#233) | ❌ | `SidebarView.swift` | `MouseButtonSpaceSwitch` | Upstream 2b95100. Windows: XBUTTON1/XBUTTON2 over the sidebar. |
| Favorite previews on hover: a Gmail favorite's unread mail, a Google Calendar favorite's Live Calendar, Join Meeting (`joinNextMeeting`, ⌃⌘J) | ❌ | `FavoritePreviewCard.swift`, `LiveCalendarClient.swift` | `GmailPreview`, `CalendarPreview`, `FavoritePreviewMetrics` | Upstream 06366ad, 874e1ca, 32caaf8. Windows needs the hover card over the favorites row and the same signed-in page reads. |
| Download location per profile: a folder, or ask where to save each file (Settings ▸ Profiles) | ❌ | `DownloadDestinations.swift`, `ProfilesPane.swift` | `DownloadLocation` | Upstream ef42649. `DownloadLocation`'s decoder keeps only folders starting with "/": Windows needs drive paths (`C:\…`) to count as absolute first. |
| Downloads list in the footer, thumbnails, no Chrome download arrow | ✅ [#10] [#12] | `DownloadsTray.swift`, `DownloadThumbnails.swift`, `ChromeDownloadAnimation.swift` | `DownloadHistory`, `DownloadRow`, `RelativeTime` | `viewDownloads` is Ctrl+J (Chrome's Downloads key): the Library's Downloads page (#27), with Open, Show in Folder and Open Downloads Folder. Missing: the flight into the bin (`DownloadFlight.swift`). |
| Download flight into the Library button | ❌ | `DownloadFlight.swift` | | |
| Favicons in rows, tiles and the command bar | 🟡 [#12] | `FaviconCache.swift` | `FaviconKey` | Since upstream 061a0ef (#211) tabs on one host keep their own icons (`FaviconKey.key(for:iconURL:)`, `SidebarStore.setFaviconKey`); Windows still keeps one icon a site. |
| GitHub and GitLab live folders (`newGitHubLiveFolder`, Live Folders ▸ GitLab…) | ❌ | `LiveFolderManager.swift`, `GitHubLiveClient.swift`, `LiveFolderViews.swift` | `LiveFolderModel`, `GitLabLiveClient` | GitLab came upstream in bb38e5a (#223), its client already in CraCore. `GitHubLiveClient.swift` is Foundation only: move it to CraCore so Windows doesn't rewrite it. Sign-in token storage needs Credential Manager. |

## Command bar and shortcuts

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Command bar: tabs, archive, history, domains, actions, inline completion, ⌘Return background tab, Tab on the empty field lists actions (#195) | ✅ [#8] [#9] [#24] | `CommandBarController.swift`, `CommandBarView.swift`, `CommandTextField.swift`, `SearchSuggestLoader.swift` | `SuggestionEngine`, `CommandBarDedupe`, `CommandBarGlyph`, `TypedURL`, `RelativeTime`, `ActionSearchScope` | The actions scope (upstream 390cc0b) came with #24's sync. Windows: `WinSuggestLoader` repeats the Mac's loader on FoundationNetworking; move the loader to CraCore. Missing: the theme-following glow and scope bounce, ⌥Return as a split, `checkForUpdates`. |
| Search suggestions, Site Search with Tab, % tab search, Chromium's engines | ✅ [#9] [#13] | `SearchEngines.swift` | `SearchSuggestions`, `SiteSearch`, `TabSearchScope` | Windows reads Cra's engine setting; the Mac also reads Chromium's engine list (SQLite). |
| Shortcuts in `keybindings.json`, Settings ▸ Shortcuts | ✅ [#15] | `KeyBindings.swift`, `ShortcutsPane.swift`, `KeyboardLayoutCharacters.swift` | `KeyBindingDefaults`, `KeyBindings`, `KeyChord`, `KeyChord+Windows` | Since upstream 370ca1a (#212) the Mac matches by the character the layout types and falls back to the key's ANSI place (`KeyChord.match`); Windows matches virtual keys, which already follow the layout. Windows' table is `KeyBindingDefaults.windowsShortcuts`; a command joins it when Windows performs it (`parity.py report` lists the rest, each named in its feature's row). |
| Help menu: Essential Keyboard Shortcuts card (`essentialShortcuts`), Reveal Cra Data (`revealData`), Copy Cra Info (`copyAppInfo`), Open Task Manager (`taskManager`), Cast… (`cast`) | ❌ | `EssentialShortcutsWindow.swift`, `AppDelegate.swift` | `KeyBindingDefaults` | Upstream a6b5d41, d729895, d110dc6. Task Manager and Cast are Chrome's own pages. |
| Recent-tab switcher on ⌃Tab (`recentTab`, `recentTabBackward`) | ❌ | `TabSwitcher.swift`, `TabSwitcherView.swift` | `SidebarStore` | Ctrl+Tab cycles sidebar order on Windows until this lands. |
| Context menus show shortcut glyphs | 🟡 | `SidebarMenus.swift` | `KeyBindings` | WinUI menu items take KeyboardAcceleratorTextOverride. |

## Split view

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Up to four panes, dragger, add, close, separate, flip, cycle, split menu | ✅ [#11] | `PaneCardView.swift`, `SplitDraggerHandleView.swift`, `SplitPaneLayout.swift` | `SplitPaneLayout` | |
| Pane controls on focus and hover, focus ring, rename a split, pinned and favorite splits | 🟡 | `PaneCardView.swift`, `SidebarRowViews.swift` | `SidebarStore` | Windows has the layout and the menu; the per-pane bar, ring and rename are missing. |
| Switch to Split View 1–4 (`splitPaneN`), Open in Split View and Add Split View on the tab menu, a tab dropped on a pinned tab makes a pinned split (#180) | ❌ | `MainWindowController.swift`, `SidebarMenus.swift` | `SidebarStore` (`createSplit(inPlace:)`, `combineIntoSplit`) | Upstream 56a5232, b2955ba. The drop waits for drag and drop. |

## Little Windows, Peek and the Library

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Little Windows (`newLittleWindow`, `promoteLittleWindow`, `closeLittleWindows`), profile chip, ⌥⌘N from any app | ✅ [#23] | `LittleWindowController.swift`, `GlobalHotkey.swift` | `LittleWindowLayout`, `SpaceWindow`, `GlobalShortcut` | Windows: Ctrl+Alt+N (also from any app, RegisterHotKey, skipped where AltGr+N types a letter), Ctrl+O; the strip, Open in Space and its menu, the profile chip, the command bar, size and cascade, archive on close. The live page moves into the browser window (`cra_browser_set_parent`). Windows keeps its own title bar in the strip's navy. Left: Arc's searchable spaces popup (a menu here), the grow-from-the-pointer animation, "Don't ask again" on the profile change, Show Little Window "Open In" Menu (`littleWindowOpenInMenu`, upstream e8675b2), archiving Little Windows after 1, 6 or 12 hours (`LittleWindowArchive`, upstream d4e9705). |
| Peek: card over the page with its own bar, Close, Expand, Add To Split | ✅ [#24] | `PeekChrome.swift`, `PeekDimPanel.swift`, `ChromiumChildFocus.swift`, `LittleWindowController.swift` | `PeekLayout`, `PeekBarColors`, `PeekTrigger`, `PeekVeil`, `PinnedNavigation`, `PeekTabs` (`openLinkTab`, `peekSplitTabs`, `joinSplit`) | Windows: the card is an owned HostWindow with the page-coloured bar (`Peek/PeekBarView.swift`); the veil, click catcher and round buttons are owned layered windows (`CraOverlay.cpp`, `Peek/PeekOverlays.swift`). Settings ▸ Tabs ▸ Links, Shift-click, Escape (from the page or the bar), Ctrl+O, Ctrl+Shift+T reopening it, the card keeping the keyboard while it is up (#26), links leaving it for a tab, the badge on the tab it came from. Left: the card growing out of the link and back (#204, `PeekTransition`); the veil only fades. Since #24 the Mac shrinks the page behind a Peek a little unless pages fill the window edge to edge (#221, `PeekVeil`, `PeekLayout.backdrop`) and keeps the browser window's shadow (#222, `ChromiumChildFocus.swift`); Windows' browser window already stays active under the card, and its page doesn't shrink yet. Since upstream 5e777bf and 3a85ee6 (#242) a Peek waits on its tab and comes back with it, and a click on another tab's row opens that tab while the Peek waits (`PeekPresence`); Windows closes the Peek instead. |
| Air Traffic Control: route links from other apps to a space or Little Window | 🟡 [#29] | `AirTrafficControlView.swift`, `AppDelegate.swift` | `LinkRouting`, `ExternalLink` | Windows sends each link from another app where the routes and Settings ▸ Tabs ▸ "Links from other apps open in a Little Window" say (`WindowList.openExternal`, the same `ExternalLink.target` the Mac's `openExternalURL` asks). Left: the routes editor, so routes come only from a `settings.json` the Mac wrote. |
| Library in the sidebar (`openLibrary`), swipe or button slides it in | 🟡 [#27] | `LibraryView.swift` | `LibraryPage`, `LibraryLayout`, `LibraryList`, `LibrarySwipe` | Windows (`Sidebar/LibraryView.swift`): the sidebar widens 70 DIPs for the rail (Downloads, Archived Tabs), the page's search and ⋯ menu, rows by day; Ctrl+Shift+L, the downloads button (Arc's Library button: hover lists downloads, a click opens the Library), Escape and the back arrow leave it, and it opens again on the page last shown. Left: the slide in and out, the two-finger swipe (`LibrarySwipe`), the Spaces page (Manage Spaces row), the Media and Easels pages (their rows), dragging a download out. Upstream since #27: Arc's Filter by profile (`LibraryFilter`, `LibraryFilterPanel.swift`), Library ▸ Downloads listing running downloads with their progress (#245, `DownloadList`; Windows' page lists finished files), archived-row buttons and theme accents (bf6648e). |
| History and archive view (`viewArchive`), Archive ▸ View Archive… (`showArchive`) and Clear Archive (`clearArchive`) | 🟡 [#27] | `LibraryView.swift` | `SidebarStore`, `LibraryList` | Ctrl+H (Chrome's History key) opens the Library's Archived Tabs: search by title or address, a click restores the tab where it was closed from; Restore, Copy Link, Remove from Archive, and Clear Archive in the ⋯ menu. Upstream d110dc6 made View Archive… and Clear Archive commands of their own: not in Windows' command bar yet. |
| Library ▸ Media (`viewMedia`): screenshots, pictures and videos from the folders shown, after Arc's opt-in card | ❌ | `LibraryMedia.swift`, `LibraryView.swift`, `MediaPreviewWindow.swift` | `MediaLibrary`, `LibraryPage` | Upstream 2294e13. Windows needs the folder scan (Pictures, Screenshots, Videos) and the grid. Since a8fde87, bf6648e and f547bd8: Arc's media preview (`MediaPreview`), grid and menu. |
| Easels (`newEasel`, `viewEasels`): Arc's canvas with text, shapes, freehand and captures, Library ▸ Easels | ❌ | `EaselBrowser.swift`, `EaselCanvasView.swift`, `LibraryView.swift`, `LibraryEaselGrid.swift` | `Easel`, `LibraryList` (`easels`) | Upstream f7e3b8f to 3e2757b. The model, tools, hit-testing and saving are shared; Windows needs the canvas (Win2D or a XAML Canvas). Since fea3d7c and f547bd8: Arc's grid of easel cards, pictures resized by their corners (`EaselResize`). |
| Boosts (`newBoost`, `viewBoosts`): restyle a site (colours, fonts, Zap, CSS and JS code with the eyedropper and hammer), Library ▸ Boosts with each site's icon | ❌ | `BoostStore.swift`, `BoostEditor.swift`, `LibraryBoostRow.swift`, `SiteIconLoader.swift` | `Boost`, `BoostPicker`, `SiteIcon` | Upstream 415ff0e, 5da196f, 8878058, a8fde87, 6523975. The model, picker and icon choice are shared; Windows needs the editor panel and injecting the boost into pages through CEF. `LibraryPage.boosts` is in CraCore; Windows' rail doesn't show it yet. |
| Now-playing player in the sidebar | ❌ | `NowPlayingTray.swift`, `NowPlaying.swift` | `AudibleHold` (Mac's WebKit tabs) | Windows counterpart for media keys: System Media Transport Controls. |
| Downloads rename card | 🟡 | `DownloadRenameCard.swift` | `TidyDownloads` | The Windows list has open and Show in Folder; the rename card comes with Tidy Downloads. |

## Tabs and memory

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Auto-archive Today tabs after a set time | ✅ [#14] | `TabsPane.swift` | `SidebarModel` (`AutoArchiveThreshold`) | |
| Tab freezing and sleeping, Tab Cleanup timers, calls stay awake | ❌ | `BrowserManager.swift` | `TabSleepPolicy` | The policy is shared; Windows needs the CEF discard calls and the two Settings ▸ Tabs switches. Since upstream 135f794 (#214) the policy reads a `PageState` per page and says why it passed one over. Since upstream c09f3c3 (#237) critical memory pressure closes 9 pages a pass and each pass logs one line per way of closing (`TabSleepPolicy.PassLog`). |
| Mute a tab (`muteTab`), speaker icon, camera and microphone dot | 🟡 | `SidebarRowViews.swift` | `SidebarModel` | The bridge can mute; the sidebar shows no speaker yet. |
| Open links in new tabs in the background | ❌ | `TabsPane.swift` | `LinkMenu` | |
| Background tabs laid out at the pane's size, first seconds of a tab, hidden tabs give their GPU tiles back (#195) | ❌ | `BrowserManager.swift`, `PageProbe.swift`, `PageScript.swift` | `HiddenFrameRelease` | `PageScript.swift` is Foundation only: move it to CraCore. |

## Media and capture

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Capture (`capturePage`): copy the page | 🟡 [#17] | `CaptureOverlay.swift`, `ViewSnapshot.swift` | `PageCapture`, `ContentCapture` | Windows copies the visible page or the full page. Missing: Arc's element pick and region drag with copy, save and send (`ContentCapture`); Capture Full Page (`captureFullPage`) and Capture in Portrait Mode (`capturePortrait`) as commands (upstream 2294e13); the menu's New Easel and Send To… an easel (c85c878, b09185a). |
| Picture in Picture (`pictureInPicture`), automatic on leaving a video tab or a Meet call (Document Picture in Picture, upstream #198), throw into corners | ❌ | `PictureInPictureChrome.swift`, `PictureInPictureControls.swift` | `PictureInPictureGesture`, `PictureInPictureThrow` | Gestures and throws are shared. Since upstream 529bff6 (#246) Arc's top bar, scrim and size limits (`PictureInPictureLayout`), and Chrome's own strip never shows. |
| Protected media (DRM services in Safari's engine) | ➖ | `PageEngines.swift`, `WebKitBrowser.swift`, `WebKitStores.swift` | `ProtectedMedia` | Mac only (FairPlay in WebKit). On Windows the counterpart is a Widevine-capable CEF build; the per-site choices in `ProtectedMedia` can be reused. |
| Screen sharing with tab audio, web notifications shown and clicked | 🟡 [#17] | `CraCEF.mm` | `PermissionPrompt` | The prompts work on Windows; Chrome's screen picker and notifications opening their page haven't been checked on the PC. |
| Speech recognition on device | ❌ | `CraCEF.mm` | `ChromiumLocale` | The `speech-on-device` CEF patch is Mac only. |

## Profiles, privacy and site data

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Permission prompts | ✅ [#17] | `CraCEF.mm` | `PermissionPrompt` | |
| Profiles: per-space cookie folders, Set Profile, Change Profile, New Profile, Settings ▸ Profiles | ✅ [#19] | `ProfilesPane.swift`, `ProfileDialogs.swift`, `NewProfileDialog.swift` | `SpaceProfiles`, `DeletedProfiles` | |
| Website languages per profile in Settings ▸ Profiles, Language Settings (`languageSettings`) opens Chromium's page (#209) | ❌ | `ProfilesPane.swift` | `BrowserLanguages` | Upstream b528590. Windows: a row in its Profiles pane and the command, reading each profile's Preferences. |
| Rebuild profiles from Arc (`rebuildArcProfiles`) | ❌ | `ArcProfileRebuilder.swift` | `ArcProfileRebuild` | Waits for Arc import. |
| Clear Cache, Clear Cookies | ✅ [#17] | `SiteData.swift` | `SiteDataClearing` | |
| Clear Browsing Data (`clearBrowsingData`) | 🟡 | `AppDelegate.swift` | `BrowsingDataClear` | The store side is shared; the command and Chrome's dialog are missing. |
| Ad and tracker blocker | ❌ | `CraContentBlocker.h`, `CraCEF.mm` | | `CraContentBlocker.h` is plain C++ with no Cocoa or CEF: `CraCEFWin.cpp` can include it as is, with the same domain list. |
| Block Cookie Banners (Arc's, off by default) | ❌ | `BrowserManager.swift`, `PrivacyPane.swift` | `CookieBanners`, `SidebarStore` (`cookieBannerCSS`) | Upstream 93b20a6. The stylesheet is shared; Windows injects it with the Privacy pane. |
| Always use secure connections (HTTPS-only), Secure DNS | ❌ | `PrivacyPane.swift`, `SecureDNSSetting.swift` | `SecureDNS` | Both are Chromium prefs; the decisions are shared. |
| Passwords and cookies encrypted with a key of Cra's own | ❌ | `SafeStorage.swift`, `keychain-service-name.patch` | | Windows counterpart: DPAPI, which Chromium uses by default. Confirm the stock CEF build does. |
| Safe Browsing, Web Push | ❌ | `CraCEF.mm`, `safe-browsing-update-interval.patch`, `gcm-enabled.patch` | | Needs Cra's CEF patches on the Windows build (today it uses Spotify's stock build). |
| Passkeys with the platform authenticator | ❌ | `webauthn-keychain-access-group.patch` | | Windows counterpart: Windows Hello, which Chromium uses on Windows. Check it works in CEF. |

## DevTools and Developer Mode

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| DevTools docked in the page's place (`devTools`, `inspectElement`, `jsConsole`), Chrome's dock sides and undocking | ✅ [#20] | `MainWindowController.swift` | `DevToolsToggle` | Moved to CraCore in #20; both apps decide each press with it. |
| Developer Mode for a site (`toggleDeveloperMode`): the striped bar with the full URL edited in place, Copy, Console, Network, Inspect; host and port under the tab's title; the ring round the open tab | ✅ [#22] | `PaneToolbarView.swift`, `SidebarRowViews.swift` | `ToolbarComposition`, `DeveloperBar` (`SpaceTheme.developerBar`, `DeveloperStripes`, `DeveloperTabRing`, `OKLab`) | Windows: Ctrl+Shift+D (the Mac's ⌃D is Pin Tab there). The bar's colours, stripes and ring moved to CraCore in #22 for both apps. Not in a split, as on the Mac; Windows has no normal toolbar yet, so a split pane shows no bar. localhost, 127.0.0.1 and *.localhost start in Developer Mode on any port (upstream 0efe33a, 6d65cf8): Windows gets it from the shared `isDeveloperMode`. |
| Performance recorder, Settings ▸ Performance, Export Diagnostics | ❌ | `PerformancePane.swift`, `Perf.swift`, `PerfCEF.swift`, `PerfFiles.swift`, `PerfRecorder.swift`, `PerfSamplers.swift`, `MainLoopObserver.swift`, `HitchMonitor.swift`, `Diagnostics.swift`, `CraLog.swift` | `PerfHistory`, `PerfInsights`, `PerfMetric`, `PerfProcessTable`, `PerfReport`, `PerfSampleStack`, `PerfSession`, `PerfStall`, `PerfState`, `LogHistogram`, `SiteNames`, `DiagnosticsRedaction`, `DisplayDiagnostics` | The recorder's model is shared; samplers are per platform. `CraLog.swift` is Foundation only: move it to CraCore so both apps log the same way. |

## Extensions

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Install from the Chrome Web Store or a folder, Extensions menu (`openExtensions`, `manageExtensions`) | ❌ | `ExtensionStore.swift`, `ExtensionsMenu.swift`, `ExtensionLaunch.swift` | `ExtensionProfiles`, `ExtensionPagePlacement`, `ExtensionPageRetry`, `WebStoreInstalls` | Phase 2 items 12 and 13. `ExtensionLaunch.swift` is a known exception: move it. Upstream 3fe0c5b (#227): quitting while a Web Store install runs no longer crashes. |
| Toolbar and pinned buttons, popups, badges, live icons | ❌ | `ExtensionActions.swift`, `ExtensionPopupWindow.swift`, `ExtensionPopupCandidate.swift` | `ExtensionActionState`, `ExtensionBadge`, `PinnedExtensions`, `PinnedExtensionGrid`, `ToolbarExtensionFit`, `DismissingClick`, `FirstClick` | The extension CEF patches (`extension-popup-browser-info.patch` and the others) need the Windows CEF build too. |
| Extension side panels (MetaMask) | ❌ | `ExtensionSidePanel.swift` | `ExtensionSidePanel` | |
| Native messaging hosts (1Password and others) | ❌ | `NativeMessagingHosts.swift`, `ExtensionProtocolReply.swift` | `ExtensionProxyControl` | Windows reads hosts from the registry, not folders. Both files are Foundation only: move the shared part to CraCore. |
| Settings ▸ Extensions | ❌ | `ExtensionsPane.swift` | | |

## Settings

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Settings window, back and forward, panes listed by `SettingsPane.windowsPanes` | ✅ [#14] | `SettingsWindowController.swift`, `SettingsKit.swift` | `SettingsNavigation`, `SettingsMetrics` | Panes not on Windows yet: `max`, `privacy`, `extensions`, `performance`, `advanced`. |
| General | 🟡 [#14] [#29] | `GeneralPane.swift`, `AppIconPicker.swift` | | Windows has the default browser and Open at login. Cra.exe and its windows carry the Mac app icon (#29). Missing: the app icon picker (a taskbar icon on Windows). |
| Tabs | ✅ [#14] | `TabsPane.swift` | `SidebarModel` | New Tab placement, single-space header, tab cleanup, Peek, links from other apps (#29). Missing rows arrive with their features (Air Traffic Control…, sleeping, shared favorites, background tabs, Little Window archive time). |
| Shortcuts | ✅ [#15] | `ShortcutsPane.swift` | `KeyBindings` | |
| Profiles | ✅ [#19] | `ProfilesPane.swift` | `SpaceProfiles` | |
| Privacy | ❌ | `PrivacyPane.swift` | `SecureDNS` | With the blocker and HTTPS-only. |
| Extensions | ❌ | `ExtensionsPane.swift` | | |
| Advanced: engine, export bookmarks, versions | ❌ | `AdvancedPane.swift`, `SidebarExport.swift` | | The bookmarks-file writer in `SidebarExport.swift` can move to CraCore; the save dialog stays per platform. |
| Max, Performance | ❌ | `MaxPane.swift`, `PerformancePane.swift` | | See Arc Max and DevTools. |

## Import and onboarding

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Import from Arc and Dia: spaces, pinned, folders, favorites, archive, profiles (`importData`) | ❌ | `Importers.swift`, `DiaSidebar.swift`, `BrowserSources.swift` | `ArcThemeImport`, `ExtensionProfiles` | Phase 2 item 10. CLAUDE.md lists `Services/Import/` as a known exception: the parsers move to CraCore with this PR; only paths (`%LOCALAPPDATA%`) and icons stay per platform. |
| Import from Chrome, Edge, Brave, Opera, Vivaldi, Helium: tabs, bookmarks, history, extensions | ❌ | `ChromiumImporter.swift`, `ExtensionImporter.swift` | | Same move. |
| Passwords and sign-ins | ❌ | `CredentialImport.swift` | | Windows decrypts with DPAPI and AES-GCM (BCrypt) instead of the Keychain. |
| Firefox and Zen | ❌ | `FirefoxImporter.swift`, `ZenImporter.swift` | | Same move. |
| Safari | ➖ | `SafariImporter.swift` | | No Safari on Windows. |
| Onboarding: import, theme colour, address bar placement | ❌ | `ImportFlow.swift`, `ImportFlowArt.swift`, `ImportFlowViews.swift`, `OnboardingSteps.swift` | | Phase 2 item 11, after import. |

## Arc Max (on-device AI)

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Tidy Tabs | ➖ | `TidyTabsService.swift` | `TidyTabs` | Runs on Apple Intelligence; Cra sends nothing to a server. A Windows counterpart would need an on-device model (Windows AI APIs on Copilot+ PCs); the prompts and parsing in CraCore can be reused. |
| Tidy Tab Titles (and Arc's rules for 52 sites) | ➖ | `TidyTitlesService.swift` | `TidyTitles`, `TidyTitleRules`, `TidyTitleRules+Data` | The rule-based titles need no model and could ship on Windows on their own. |
| Tidy Downloads | ➖ | `TidyDownloadsService.swift` | `TidyDownloads` | As Tidy Tabs. |

## System integration and release

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Open at login | ✅ [#14] | `SystemIntegration.swift` | | Windows: the Run key. |
| Default browser (`setDefaultBrowser`), opening links from other apps | 🔜 [#29] | `SystemIntegration.swift`, `AppDelegate.swift` | `ExternalLink` | Windows (`App/DefaultBrowser.swift`): "Set Cra as Default" in Settings ▸ General and the command register Cra under HKEY_CURRENT_USER (`CraHTML` for http, https and HTML files, `StartMenuInternet\Cra`, RegisteredApplications) and open its page in Windows' Default apps, where the user picks it; Windows doesn't let an app make itself the default. A link runs `Cra.exe --single-argument <url>`; a second launch reaches the running Cra through Chromium's process singleton (`OnAlreadyRunningAppRelaunch`), and `ExternalLink.links` picks the links (an .html path becomes a file:// URL). Started again with no link, Cra brings its window forward. `cra://` links from other apps aren't handled on Windows yet. Left: Windows 11 (25H2) doesn't list Cra in Default apps yet, so the button lands on the general list (tried on the PC: run from a normal folder, Start menu shortcut, AUMID, Uninstall entry, icon and version info; next: sign-out, signing, the installer's own registration); Dock's counterpart (pin to taskbar). |
| Another app's link (zoommtg:, slack:) in a new tab or window opens the app after asking, not a blank tab (#207) | ❌ | `AppLinkPrompt.swift`, `CraCEF.mm` | `AppLinks` | Upstream d1ad2af. Windows: CEF's external-protocol callback and a prompt in the page's place. |
| Links Cra opens to crabrowser.app (release notes, help) name the button they came from | ❌ | `AppDelegate.swift`, `SoftwareUpdater.swift` | `SiteLinks` | Upstream 94c1fc3. Comes with Windows' help links and the updater. |
| `cra://` scheme for scripting (`cra://open?space=`) | ❌ | `AppDelegate.swift`, `TestGesture.swift` | | |
| Auto-update (`checkForUpdates`), update banner | ❌ | `SoftwareUpdater.swift`, `UpdateBanner.swift`, `UpdaterWindow.swift` | | WinSparkle reads the same appcast. Phase 3. |
| Signed installer | ❌ | | | Authenticode and MSIX or Inno Setup. Phase 3. |
| Custom app icon | ❌ | `AppIconManager.swift` | | |
| Bluetooth device cache for Chromium | ➖ | `ChromiumBluetoothCache.swift` | | Mac only (CoreBluetooth). |
| Chromium follows the system language | ❌ | `AppDelegate.swift` | `ChromiumLocale` | Shared decision; Windows passes the user's UI language. |
| Shortcuts set in the system's keyboard settings work in pages | ➖ | `AppDelegate.swift` | | macOS only. |
| AppleScript with Arc's dictionary, JavaScript from Apple Events off by default (`allowAppleEventsJavaScript`) | ➖ | `AppleScripting.swift` | | macOS only (upstream de695e2). Windows' scripting goes through `cra://` (its own row). |
| Keep Cra in the menu bar after quitting (#231) | ❌ | `MenuBarItem.swift` | `MenuBarMode` | Upstream 96c0255. Windows' counterpart is a notification-area icon that keeps Cra running. |
| Feature flags | ❌ | `FeatureFlags.swift` | | |
| Persistence of the data folder | ✅ [#5] | `Persistence.swift`, `SidebarStore+App.swift`, `Scheduler.swift` | `JSONStore`, `Scheduling`, `SidebarStore` | `%LOCALAPPDATA%\Cra` holds the same files. Keep both versions of `Persistence.swift` in step: Mac tests compile it with CraCore. |
| Portability helpers, CraCore seen by every Mac file | ✅ [#1] [#16] | `CraCoreExports.swift` | `CGVector+Portable`, `CGAffineTransform+Portable`, `ChromiumLocale` | |

## Moving Mac code into CraCore

Code that decides something without a window, written once for both apps. In order of what
the next Windows PRs need:

1. `FloatingSidebarGeometry.swift` (hidden sidebar): a CLAUDE.md known exception, already
   Foundation only. (`DevToolsToggle` moved in #20.)
2. `Services/Import/` parsers (Import PR): replace `NSImage` with PNG `Data` and the
   `~/Library` paths with a passed-in root, keep the Mac's fixture tests.
3. `GitHubLiveClient.swift`, `PageScript.swift`, `CraLog.swift`, `NativeMessagingHosts.swift`,
   `ExtensionProtocolReply.swift`, `SearchSuggestLoader.swift`: Foundation only today.
4. `EmojiCatalog+Data.swift`: data with no imports, for the space icon picker.
5. The bookmarks writer in `SidebarExport.swift` and the domain list behind `CraContentBlocker.h`
   (a header both C++ bridges can include).

Windows code that repeats Mac logic instead of calling CraCore is a bug to fix the same way.

## Waiting in upstream

Upstream commits after the fork's last sync (9da50e7, in #25), triaged. The 16 commits #25
merged (565e477 to 9da50e7), with what each means for Windows:

| Commit | What | Windows |
|---|---|---|
| f1d9c56, 9de5a59 | Blank Window (⌃⌘N) and a tab dragged out of the window opens in one (#220, #219) | New Blank Window row (`BlankWindow`, `TabTearOff`, `newBlankWindow`). The store side came with the sync. |
| 09cbcb6, 3b57e7f | The page behind a Peek gently shrinks (#221); a Peek keeps the browser window's shadow (#222) | Peek row (`PeekVeil`, `PeekDimPanel.swift`, `ChromiumChildFocus.swift`). |
| 154d357, 5cc90c3 | A collapsed pinned section keeps the last pinned tab in sight (`PinnedPeek`); a click opens a closed folder that keeps the open tab in sight (#213) | Pinned tabs and folders rows; Windows has no collapsed pinned section or folder previews yet. |
| 370ca1a | Shortcuts follow the keyboard layout (#212) | Shortcuts row: Windows matches virtual keys. |
| 657a1f9, 3008649, 7f3ba00 | Extension popups: close buttons, imported files kept until verified, downloads from popups (#216, #217, #218) | With the Extensions rows (`WebStoreInstalls`). |
| 4aa54e6 | Arc's GitHub live folder imports as a live folder (#215) | With the live folders and import rows. |
| 9da50e7 | A WebKit video played again within 2 s shows as playing (`AudibleHold`) | Mac only (Safari's engine); now-playing row. |
| 9e2d728, 60d6e13, 800cc36, 5e79e3a | Perf harness, nightly, snapshots, mutation testing | Nothing for Windows. 9e2d728 was also cherry-picked into #24. |

Then 3d3ff80 (synced with PR 8): the blank-window scenario's window fits GitHub's 1024×768 runner screen. Test tooling, nothing for Windows.

The 34 commits #28 merged (3d3ff80 to 3e2757b), mostly upstream's Arc parity sweep:

| Commit | What | Windows |
|---|---|---|
| d2dcd18, 135f794, 3fe0c5b | Tear-off drop spot, tab sleeping's reasons (#214), quitting during a Web Store install (#227) | Tabs and memory, Extensions rows. |
| b2955ba, 56a5232 | A tab dropped on a pinned tab makes a pinned split (#180); split items on the tab menu | New split row. |
| bc47470 | Arc's dialog sheet for every confirmation (#224) | New dialog row (`AppDialog.swift`, `DialogActions`). |
| bb38e5a | GitLab live folders (#223) | Live folders row (`GitLabLiveClient`). |
| 8dbd6d1 | Site Control Center sliders without extensions (#226) | Site Control Center row. |
| d110dc6, 6f3f298, d4e9705, 337d5f8, e8675b2, 894f1f6, d729895, a6b5d41, 35bc84a, bfd9962, 93b20a6 | Arc's menu items: Stay On Top, Save Page As, Copy URL as Quote, clean Copy URL, sidebar actions, Little Window archive and Open In menu, restore windows, find selection, Cast and Task Manager, Essential Keyboard Shortcuts, website appearance and sound effects, theme data, cookie banners | New rows in Window, Sidebar, Command bar, Little Windows and Privacy. |
| 2294e13, 35d3c8a | Library ▸ Media, Capture in Portrait Mode | New Media row; Capture row. `LibraryPage` gained `media` and `easels` in CraCore; Windows' rail keeps Downloads and Archived Tabs. |
| f7e3b8f, 719a4bf, a4463ed, bb1ac55, a4c2286, 5ea57ec, c85c878, b09185a, 3e2757b | Easels: model, canvas, Library page, backdrop, text size, toolbar, capture menu, duplicate | New Easels row (`Easel`, `LibraryList.easels`). |
| 2985c38, 1759699, b68d430, 7f31945 | docs/arc-parity.md and live checks | Nothing for Windows. |

The 40 commits the eighth sync merged (de695e2 to f547bd8):

| Commit | What | Windows |
|---|---|---|
| 415ff0e, 5da196f, 8878058, a8fde87, 6523975 | Boosts: New Boost, the editor, Zap, code, Library ▸ Boosts with site icons | New Boosts row (`Boost`, `BoostPicker`, `SiteIcon`, `newBoost`, `viewBoosts`). `LibraryPage.boosts` added to CraCore. |
| 06366ad, 874e1ca, 32caaf8 | Gmail and Live Calendar previews on favorites, Join Meeting | New favorite previews row (`GmailPreview`, `CalendarPreview`, `joinNextMeeting`). |
| 1b29a73, bf6648e, a8fde87, fea3d7c, f547bd8 | Library: running downloads (#245), Filter, archived-row buttons, media preview and menu, easel grid, picture resize | Library, Media and Easels rows. Upstream's `DownloadList` now holds the download rows; the fork's CraCore `DownloadHistory` reads it (types, tray, `library(query:)`, profiles). The Mac's `LibraryView.swift` is upstream's again (it no longer reads `LibraryList`); Windows still does, with Arc's empty-page words for Downloads and Boosts. |
| 5e777bf, 3a85ee6 | A Peek waits on its tab and comes back with it (#242) | Peek row (`PeekPresence`). |
| 529bff6 | Picture in Picture: Arc's bar, scrim and size limits (#246) | Picture in Picture row (`PictureInPictureLayout`). |
| 3b6b27d, 7675257 | Dragging the window from the top of a page; clicks under Chrome's debugger bar (#241) | New rows (`PageTopDrag`, `PageViewInsets`). |
| 2b95100, 12ab4cf, 11ff4c9, ba0bd0f | Mouse buttons switch spaces (#233), tab row hover spacing (#243), folder emblems (#234), the ⌘S motion | New Sidebar rows (`MouseButtonSpaceSwitch`, `TabRowTrailing`); Folders and Hide the sidebar rows (`FolderGlyphView.swift`, `SidebarMotion`). |
| 87ab765, 15c5913, c42afc3 | Toolbar pitch and right-end spacing | Toolbar row. |
| 0efe33a, 6d65cf8 | localhost, 127.0.0.1 and *.localhost start in Developer Mode (#228) | Shared through `SidebarModel`: Windows has it. |
| c09f3c3 | Tab sleep under critical memory pressure (#237) | Tabs and memory row (`TabSleepPolicy`). |
| 4b18433 | Live folder repository filters (#229) | Live folders row; `SidebarStore.liveRepositories` is public in CraCore. |
| de695e2, 96c0255 | AppleScript (`allowAppleEventsJavaScript`), Cra kept in the menu bar after ⌘Q (#231) | New rows: AppleScript is Mac only; the menu bar item's counterpart is a notification-area icon (`MenuBarMode`). |
| 905a582 | Manifest V2 extensions run again (#228) | Extensions rows: Windows has no extensions yet. |
| 30b93c6, 435b87f, 357dc38, 6d8b2f6 | CEF 156.0.26, Intel Macs | Windows fetches the same CEF version (`fetch-deps.ps1` reads `fetch-cef.sh`). |
| 0039635 | A Chromium page played again within 2 s shows as playing | Now-playing row. |
| b9ec9b9, 55d0dd0, cf21e03, 3201357 | Docs: reviewing, localization and ideas policy, arc-parity | Nothing for Windows. |

## Keeping this current

- **Each upstream sync** (CONTRIBUTING's merge before each new PR): run
  `python3 -I Windows/scripts/parity.py report --upstream upstream/main`, add or update a row for
  each new feature, file and command, triage the commits under Waiting in upstream, and move the
  `upstream-reviewed` marker to the newest upstream commit you read. The weekly
  `upstream-drift.yml` puts the same report in its summary.
- **Each Windows PR**: change its rows (status and PR link) in the same PR.
- **CI** (`upstream-drift.yml` on pull requests) runs `parity.py check`: it fails when a Mac
  file, CraCore file, Mac command or Settings pane has no row, or when main has merged upstream
  commits newer than the marker. It warns when `Windows/Sources` changed and this file didn't.

[#1]: https://github.com/vishnu597/cra-windows/pull/1
[#2]: https://github.com/vishnu597/cra-windows/pull/2
[#3]: https://github.com/vishnu597/cra-windows/pull/3
[#5]: https://github.com/vishnu597/cra-windows/pull/5
[#8]: https://github.com/vishnu597/cra-windows/pull/8
[#9]: https://github.com/vishnu597/cra-windows/pull/9
[#10]: https://github.com/vishnu597/cra-windows/pull/10
[#11]: https://github.com/vishnu597/cra-windows/pull/11
[#12]: https://github.com/vishnu597/cra-windows/pull/12
[#13]: https://github.com/vishnu597/cra-windows/pull/13
[#14]: https://github.com/vishnu597/cra-windows/pull/14
[#15]: https://github.com/vishnu597/cra-windows/pull/15
[#16]: https://github.com/vishnu597/cra-windows/pull/16
[#17]: https://github.com/vishnu597/cra-windows/pull/17
[#18]: https://github.com/vishnu597/cra-windows/pull/18
[#19]: https://github.com/vishnu597/cra-windows/pull/19
[#20]: https://github.com/vishnu597/cra-windows/pull/20
[#21]: https://github.com/vishnu597/cra-windows/pull/21
[#22]: https://github.com/vishnu597/cra-windows/pull/22
[#23]: https://github.com/vishnu597/cra-windows/pull/23
[#24]: https://github.com/vishnu597/cra-windows/pull/24
[#27]: https://github.com/vishnu597/cra-windows/pull/27
[#29]: https://github.com/vishnu597/cra-windows/pull/29
