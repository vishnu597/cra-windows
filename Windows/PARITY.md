# Mac feature parity

Every feature of the Mac app, what the Windows app has of it, and where the code that both
can share lives. The goal is the Mac app's features on Windows, built on the Mac's own logic:
what decides something goes in CraCore once and both shells call it (CLAUDE.md, rule 1).

<!-- upstream-reviewed: b517a00 -->
Upstream reviewed through **b517a00** (VictorKildahl/cra main, 12 Nov 2026), the 80 commits
after 2bf4f8f triaged under Waiting in upstream. Upstream sync #9 carries them into the fork;
the Windows gaps below remain explicit rather than inheriting the Mac's status.

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
| Window, pages and toolbar | 5 | 4 | 0 | 15 | 1 |
| Sidebar | 3 | 7 | 0 | 18 | 0 |
| Command bar and shortcuts | 1 | 4 | 0 | 4 | 0 |
| Split view | 1 | 1 | 0 | 2 | 0 |
| Little Windows, Peek and the Library | 2 | 4 | 0 | 4 | 0 |
| Tabs and memory | 1 | 1 | 0 | 4 | 0 |
| Media and capture | 0 | 2 | 0 | 2 | 1 |
| Profiles, privacy and site data | 2 | 2 | 0 | 9 | 0 |
| DevTools and Developer Mode | 2 | 0 | 0 | 1 | 0 |
| Extensions | 0 | 0 | 0 | 5 | 0 |
| Settings | 2 | 4 | 0 | 5 | 0 |
| Import and onboarding | 0 | 0 | 0 | 5 | 1 |
| Arc Max (on-device AI) | 0 | 0 | 0 | 0 | 3 |
| System integration and release | 3 | 2 | 0 | 9 | 4 |
| **All** | 22 | 31 | 0 | 83 | 10 |
<!-- /summary -->

## Window, pages and toolbar

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Browser window with pages inside it (CEF child windows), crash-safe start | ✅ [#2] [#3] | `main.swift`, `AppDelegate.swift`, `AppComposition.swift`, `MainWindowController.swift`, `ShellView.swift`, `BrowserManager.swift`, `EmbeddedPages.swift`, `ChromiumWindowCorners.swift`, `ChromiumChildHover.swift`, `ChromiumChildFullscreen.swift`, `WindowDragGesture.swift`, `CraCEF.mm`, `CraCEF.h`, `main.cc` | `ChromiumCrashState`, `JSONStore`, `Scheduling`, `ObserveChanges`, `TabActivationRaise` | Windows: `HostWindow`, `CraCEFWin.cpp`. Missing: Settings' edge-to-edge pages, Escape leaves video fullscreen (check). Upstream c795319 and 0051bb3 keep a background browser behind the app in use while pages are created or extensions select a tab; Windows needs its own focus regression checks. |
| More than one window, window frames saved in `windows.json` | ✅ [#18] | `MainWindowController.swift` | `WindowFrame`, `SpaceWindow` | `SpaceWindow` picks the window a Little Window's page goes to (#23); `moveTabToSpaceN` still waits for a key. |
| Private (incognito) windows | ✅ [#18] | `BrowserManager.swift` | `SidebarStore` | |
| Blank Window (`newBlankWindow`, "This Window" with a sidebar of its own); a tab dragged out of the window opens in one | ❌ | `AppDelegate.swift`, `MainWindowController.swift`, `SidebarRowViews.swift` | `BlankWindow`, `TabTearOff`, `SidebarStore` (`addBlankWindow`, `moveToBlankWindow`, `isStandalone`) | Upstream #220, #219 (f1d9c56, 9de5a59). The store already saves Blank Windows' spaces outside `spaceOrder`, so Windows needs the window, its header and the drag out of the sidebar (which waits for drag and drop). |
| Toolbar: optional (`toggleToolbar`), host-only address, Show Full URL, reload that turns into stop (`stop`), tab colour, link-copy glyph | ❌ | `PaneToolbarView.swift`, `AppKitControls.swift` | `ToolbarComposition`, `ToolbarColor`, `ToolbarExtensionFit` | Off by default as on the Mac, so it comes after the sidebar's address pill. Composition and colour decisions are already shared. Upstream 87ab765 and 15c5913 set Arc's 36 pt button pitch and right-end spacing (`ToolbarComposition`). |
| Loading bar at the top middle of the window | ❌ | `LoadingIndicatorView.swift` | `LoadingIndicator` | Small: drive a XAML bar from `LoadingIndicator`. |
| Hide the sidebar (`toggleSidebar`) and the floating sidebar that slides in from the left edge | ❌ | `FloatingSidebar.swift`, `FloatingSidebarGeometry.swift` | `SidebarMotion`, `SidebarSlidePage` (move `FloatingSidebarGeometry` here) | `FloatingSidebarGeometry` is a CLAUDE.md known exception: move it to CraCore with this PR. Upstream 86dbb44, fb2c304 and 43e8adc refine the reveal, fullscreen edge and page/toolbar staying put while the sidebar slides. Windows needs the whole hidden/floating-sidebar path. |
| Drag the window from the top of a page (on by default, as in Arc) | ❌ | `MainWindowController.swift` | `PageTopDrag` | Upstream 3b6b27d. Windows: a press in the page's top strip starts the move (WM_NCLBUTTONDOWN with HTCAPTION). |
| Clicks land under the pointer while Chrome's debugger bar shows (#241) | ❌ | `CraCEF.mm` | `PageViewInsets` | Upstream 7675257: the Mac page view moved down by the bar. Check on Windows when extensions that debug pages (#228) run. |
| Find in page with match count | ✅ [#10] | `Overlays.swift` | `FindInPage` | |
| Toasts (copied URL with Share, captures, downloads) | ✅ [#17] | `ShinyToast.swift`, `Overlays.swift` | `ToastStyle`, `ShareRetry` | Windows uses DataTransferManager for Share. `ShareRetry` bounds temporary-busy retries and ends with one failure toast; commands, Site Controls and copied-URL toasts use the same path. Successful Share-panel handling still needs a working Windows Share service in the PC test. |
| Site Control Center, lock badge and certificate viewer | 🟡 [#17] | `SiteControlCenter.swift`, `CertificateWindow.swift` | `SiteControlCenter`, `ConnectionSecurity`, `PageCapture` | Windows shows the sliders in the sidebar's address pill. Missing: the protected-media card (Mac only, see Media) and upstream cbb5753's per-site Automatic Picture-In-Picture switch. |
| Zoom (`zoomIn`, `zoomOut`, `resetZoom`), `print`, `viewSource` | 🟡 | `AppDelegate.swift` | `KeyBindingDefaults` | Left to Chromium's own keys on Windows: not in Cra's key table, the command bar or Settings ▸ Shortcuts. Add them to `KeyBindingDefaults.windowsShortcuts`. |
| Page context menu: Open Link in New Tab and Open Link in Split View; Alt-click split | 🟡 | `BrowserManager.swift` | `LinkMenu`, `PageMenuLabels`, `LinkSplitClick` | Chromium's menu shows on Windows. Upstream 9630b47, 249adb7 and 8a6c6bf add a split action, one localized Open Link in New Tab item following the foreground setting, and Option-click split (Alt on Windows). Windows needs those policies wired to the page callbacks. |
| Arc-style tooltips in the space's tones | ❌ | `ArcTooltip.swift` | `ThemeTones` (`TooltipTones`) | Windows uses plain WinUI tooltips. |
| Theme, metrics and the brand mark | 🟡 | `Theme.swift`, `Tuning.swift`, `BrandMark.swift` | `SpaceTheme`, `ThemeTones`, `ArcMenuTones`, `SidebarTones`, `CardFill` | Sidebar palette from `SpaceTheme` is shared; Windows has its own metrics. Upstream's Arc menu, sidebar hover and card-fill policies are available but not all used by the Windows controls. Brand mark from `brand/`. |
| Sidebar blur, Reduce transparency, active/inactive look | ❌ | `ActiveAppearanceProbe.swift` | `SidebarBackdrop` | Windows counterpart: Mica or Acrylic, and Windows' transparency setting. Since f6b9fb6 a full-screen window keeps its active look while its Space slides away (AppKit's own answer, `windowActive(activeAppearance:)`). |
| Only one Cra running (an older copy quits) | ➖ | `NewestCopy.swift` | | Windows: a single-instance mutex when the installer lands. |
| Arc's dialog sheet for every confirmation: one card, its buttons, keys and hover | ❌ | `AppDialog.swift`, `DialogComponents.swift`, `Colors.swift` | `DialogActions` | Upstream bc47470 (#224). Windows asks with WinUI flyouts and dialogs; `DialogActions` (which button Return and Escape press) is shared for the Windows card. `Colors.swift` is SwiftUI's hex colours. |
| Stay On Top (`stayOnTop`), Save Page As (`savePageAs`), Copy URL as Quote (`copyURLQuote`), Copy URL without trackers | ❌ | `MainWindowController.swift`, `AppDelegate.swift` | `CleanURL` | Upstream d110dc6. Windows' Copy URL copies the address as it is: call `CleanURL` there first. Stay On Top: `HWND_TOPMOST`. Upstream cd8f3f5 copies every selected sidebar tab's URL on separate lines; Windows also needs multi-selection for that behavior. |
| Find ▸ Use Selection to Find (`useSelectionForFind`), Jump to Selection (`jumpToSelection`) | ❌ | `MainWindowController.swift` | `FindInPage` | Upstream 894f1f6. Windows' find bar would take the page's selection. |
| What websites see: View ▸ Appearance (`appearanceAutomatic`, `appearanceLight`, `appearanceDark`), sound effects, "Allow websites to get your theme data" | ❌ | `AppDelegate.swift`, `BrowserManager.swift`, `AdvancedPane.swift`, `CraCEF.mm` | `SidebarModel` (`WebsiteAppearance`), `ArcThemeData`, `ThemeTones`, `SidebarStore` (`themeDataCSS`) | Upstream 35bc84a, bfd9962. The settings are in the shared `settings.json`; Windows needs the CEF colour-scheme call and the `:root` style injection. |
| "When opening Cra, restore windows from previous session" and "start on a new tab" | ❌ | `AppDelegate.swift`, `AdvancedPane.swift` | `SidebarModel` (`restoreWindows`), `SidebarStore`, `LaunchStart` | Upstream 337d5f8 and 7c98d46. Windows always restores its windows; read both launch settings with the Advanced pane. A link launch must still show its link rather than a new-tab bar. |
| Slow first response: after 10 seconds, a waiting-page toast with Stop Loading | ❌ | `BrowserManager.swift`, `ShinyToast.swift` | `SlowResponseNotice` | Upstream 001afb2. The waiting/wording policy is shared; Windows needs scheduled notices and the Stop Loading action. |
| Translate a page, Translation Available affordance and Arc's translate popover | ❌ | `BrowserManager+Translation.swift`, `TranslatePopover.swift`, `PaneToolbarView.swift` | `PageTranslation` | Upstream 386fbf8. Requires the translate CEF bridge/patch (`translate-ui.patch`) and native Windows popover; stock CEF alone does not provide Cra's state callback. |

## Sidebar

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Spaces: switch, create, delete, the space dock | 🟡 [#5] | `SidebarView.swift`, `SidebarRootView.swift`, `SpaceDock.swift`, `SpaceListView.swift`, `SpaceColumnView.swift`, `SidebarUIState.swift` | `SidebarStore`, `SidebarModel`, `ItemTable`, `SidebarIntegrity`, `SpaceDock` | Same `sidebar.json` as the Mac. The Windows dock has emoji buttons; upstream a7ea20f and dc404ff add Arc's iconless/squeezed dots and expanding hovered dot, which are not drawn on Windows yet. |
| Go to Space N (`spaceN`) on Alt+1–9, next and previous space on Ctrl+Alt+Right and Left | ✅ [#5] [#21] | `MainWindowController.swift`, `AppDelegate.swift` | `KeyBindingDefaults`, `SidebarStore` (`focusSpace(number:)`) | Arc for Windows' keys: Ctrl+1–9 stays Go to Tab, as in Chrome. |
| Move Tab to Space N (`moveTabToSpaceN`) | ❌ | `MainWindowController.swift`, `AppDelegate.swift` | `SpaceWindow`, `SidebarStore` | No Windows key yet (the Mac's is ⌃⌘N); comes with Little Windows, whose page it can also send. |
| Swipe, Shift + wheel or sideways wheel between spaces | ❌ | `SpacePagerView.swift` | `WheelSpaceSwitch`, `PageDetentHaptics` | Decisions shared; Windows needs the wheel hook and the slide. Upstream c4ee4dc adds one trackpad haptic per changed page, including a flick; hardware feedback needs a Windows counterpart if supported. |
| Pinned tabs and folders, Today, Clear Today, archive on close | ✅ [#5] | `SidebarRowViews.swift`, `SidebarItemView.swift` | `SidebarStore`, `CloseSuccessor`, `SidebarClose`, `PinnedPeek` | `clearToday` and `newFolder` are in the sidebar menus, not yet commands; `SidebarClose` (Arc's close buttons per row kind) isn't used on Windows yet. |
| Pinned tab extras: back to its page by the favicon, the slash, Reset (`resetTab`), edit URL | ❌ | `EditPinnedURLDialog.swift`, `SidebarRowViews.swift` | `PinnedNavigation` | Since 6e371cc "Back to Pinned URL" slides in under the title on hovering the icon (0.16 s). |
| Folders: hinge animation, hover previews with search, tabs shown under a closed folder, icon picker | 🟡 | `FolderPreview.swift`, `FolderGlyphView.swift`, `FolderIconPicker.swift`, `FolderSymbolImages.swift` | `FolderPeek`, `FolderSymbol` | Windows has folders without previews or the animation. Since upstream 11ff4c9 (#234) the folder's emblem follows its front panel's perspective; 4fc05d2 adds Arc's picker and native symbol-mask rendering, still missing on Windows. |
| Favorites | 🟡 [#5] | `SidebarRowViews.swift`, `TileColor.swift` | `FavoritesLayout`, `FavoritesSharing`, `FavoriteClick`, `FavoriteSelectionTint`, `FavoriteOutlineColors` | Missing: 4/2/1 columns by width (`FavoritesLayout`), tile colours and icons, "Drag to add Favorites" card, Settings' share-across-spaces switch, double-click returning to the pinned page (a17a8fe), and the opt-in logo-coloured outline/Arc hover fills (86dbb44, 9927600). |
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
| Downloads list in the footer, thumbnails, no Chrome download arrow | 🟡 [#10] [#12] | `DownloadsTray.swift`, `DownloadThumbnails.swift`, `ChromeDownloadAnimation.swift`, `DownloadProgressBadge.swift`, `DownloadRowMenu.swift` | `DownloadHistory`, `DownloadRow`, `DownloadMenu`, `RelativeTime` | `viewDownloads` is Ctrl+J (Chrome's Downloads key): the Library's Downloads page (#27), with Open, Show in Folder and Open Downloads Folder. Missing: the flight into the bin (`DownloadFlight.swift`), upstream e44ba8f's pause/resume/cancel callbacks and row menu, the progress ring on the bin and confirmation before quitting with downloads running. |
| Download flight into the Library button | ❌ | `DownloadFlight.swift` | | |
| Favicons in rows, tiles and the command bar | 🟡 [#12] | `FaviconCache.swift` | `FaviconKey` | Since upstream 061a0ef (#211) and f6c91a3 (#291), each tab's icon, including a data: icon, persists across relaunch (`FaviconKey`, `SidebarStore.setFaviconKey`). Windows still keeps one icon a site. |
| Live folder plugins: built-in GitHub, GitLab and Jira, installed JavaScript providers | ❌ | `LiveFolderManager.swift`, `LiveFolderPluginStore.swift`, `LiveFolderViews.swift`, `PluginsPane.swift` | `LiveFolderModel`, `GitLabLiveClient` (legacy model), `LiveFolderPlugin`, `LiveFolderPluginArchive`, `LiveFolderPluginConfiguration`, `LiveFolderPluginOutput`, `LiveFolderPluginPackage`, `LiveFolderPluginProcess` | Upstream 664cc6a replaces the native GitHub/GitLab clients with bundled JavaScript providers and a package/permission flow (Settings ▸ `plugins`); b08beb3 fixes bundled paths under /private. `GitHubLiveClient.swift` was deleted upstream. Windows needs the runtime, exact-origin session reads, package settings and native live rows. Pure manifest/ZIP/output validation is portable; operational ZIP extraction and plugin process invocation explicitly report unsupported on Windows until its installer/runtime is implemented. Preserve old folder data. |
| Sidebar width, drag-to-hide, snap and narrow header | ❌ | `SidebarView.swift`, `SidebarMorePanel.swift` | `SidebarWidth`, `SidebarResize`, `SidebarHeaderLayout` | Upstream 46cfb2a and 06d5380: 164–500 pt, snap to 228, drag shut below 82, compact navigation below 212. Windows' fixed sidebar needs the resize input, saved width and narrow header; use these policies rather than duplicate thresholds. |
| Sidebar + creation menu and More options in the space's palette | ❌ | `SidebarCreationMenu.swift`, `SidebarMorePanel.swift` | `ArcMenuTones`, `SidebarTones` | Upstream 895b0c5 and 86dbb44. Windows' footer + creates a space directly; it does not yet show Arc's creation menu or the +/× transition. |
| Floating music notes on a playing favorite | ❌ | `MusicNotesView.swift`, `SidebarRowViews.swift` | `MusicNotes` | Upstream e1c8765. Shared note paths/timing are available; Windows needs audio state and the favorite overlay. |

## Command bar and shortcuts

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Command bar: tabs, archive, history, domains, actions, inline completion, ⌘Return background tab, Tab on the empty field lists actions (#195) | 🟡 [#8] [#9] [#24] | `CommandBarController.swift`, `CommandBarView.swift`, `CommandTextField.swift`, `SearchSuggestLoader.swift` | `SuggestionEngine`, `CommandBarDedupe`, `CommandBarGlyph`, `TypedURL`, `RelativeTime`, `ActionSearchScope`, `CommandBarTones` | Windows has the shared ranking and actions scope. `WinSuggestLoader` repeats the Mac's loader on FoundationNetworking; move it to CraCore. Missing: upstream 3bd548d's Arc sizing/row and badge tones, the theme glow and scope bounce, Alt+Return split, `checkForUpdates`, and cab6d40's current-space-only setting. |
| Search suggestions, Site Search with Tab, % tab search, Chromium's engines | 🟡 [#9] [#13] | `SearchEngines.swift` | `SearchSuggestions`, `SiteSearch`, `TabSearchScope` | Windows reads Cra's engine setting; the Mac also reads Chromium's engine list (SQLite). Upstream d55e7a0 adds a search engine per space and cab6d40 can restrict tab results to that space; the Windows caller must use the shared engine/scope decisions. |
| Shortcuts in `keybindings.json`, Settings ▸ Shortcuts | ✅ [#15] | `KeyBindings.swift`, `ShortcutsPane.swift`, `KeyboardLayoutCharacters.swift` | `KeyBindingDefaults`, `KeyBindingRegistry`, `KeyChord`, `KeyChord+Windows` | Since upstream 370ca1a (#212) the Mac matches by the character the layout types and falls back to the key's ANSI place (`KeyChord.match`); Windows matches virtual keys, which already follow the layout. Windows' table is `KeyBindingDefaults.windowsShortcuts`; a command joins it when Windows performs it (`parity.py report` lists the rest, each named in its feature's row). |
| Who gets a shortcut's keys while a page wants them: Prefer Cra, Use Both, Prefer Websites (#374); search by keys | ❌ | `ShortcutsPane.swift`, `AppDelegate.swift`, `CraCEF.mm` | `ShortcutPriority`, `ShortcutSearch`, `KeyBindingRegistry` | Upstream 115e806. keybindings.json carries each action's priority on its chords (`KeyBindingOverrides`), and Windows' registry reads and keeps it already; Windows still takes its keys at one point (before the page) and has no pop-up for it. |
| Help menu: Essential Keyboard Shortcuts card (`essentialShortcuts`), Reveal Cra Data (`revealData`), Copy Cra Info (`copyAppInfo`), Open Task Manager (`taskManager`), Cast… (`cast`) | ❌ | `EssentialShortcutsWindow.swift`, `AppDelegate.swift` | `KeyBindingDefaults` | Upstream a6b5d41, d729895, d110dc6. Task Manager and Cast are Chrome's own pages. |
| Recent-tab switcher on ⌃Tab (`recentTab`, `recentTabBackward`) | ❌ | `TabSwitcher.swift`, `TabSwitcherView.swift` | `SidebarStore` | Ctrl+Tab cycles sidebar order on Windows until this lands. |
| Context menus show shortcut glyphs | 🟡 | `SidebarMenus.swift` | `KeyBindings` | WinUI menu items take KeyboardAcceleratorTextOverride. |
| Command bar's search-suggestions notice | ❌ | `CommandBarController.swift`, `CommandBarView.swift` | `SearchSuggestionsNotice`, `CommandBarTones` | Upstream 50d2fa9 then 0c81531: Arc's (i) opens the search-engine privacy notice, not Site Control Center; Dismiss persists. Windows needs the badge, banner and Search Settings action. |
| File menu's Arc sections, Share… (`share`) and New Profile (`newProfile`) | 🟡 | `AppDelegate.swift` | `FileMenu` | Upstream 7f5759f. Sync #8 exposes the existing Windows profile/share capabilities as commands. The Windows shell still has no native File menu built from `FileMenu.sections`. |

## Split view

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Up to four panes, dragger, add, close, separate, flip, cycle, split menu | ✅ [#11] | `PaneCardView.swift`, `SplitDraggerHandleView.swift`, `SplitPaneLayout.swift` | `SplitPaneLayout` | |
| Pane controls on focus and hover, focus ring, rename a split, pinned and favorite splits | 🟡 | `PaneCardView.swift`, `SidebarRowViews.swift` | `SidebarStore` | Windows has the layout and the menu; the per-pane bar, ring and rename are missing. |
| Switch to Split View 1–4 (`splitPaneN`), Open in Split View and Add Split View on the tab menu, a tab dropped on a pinned tab makes a pinned split (#180) | ❌ | `MainWindowController.swift`, `SidebarMenus.swift` | `SidebarStore` (`createSplit(inPlace:)`, `combineIntoSplit`) | Upstream 56a5232, b2955ba. The drop waits for drag and drop. |
| Expand Current Split (`expandSplitPane`): the focused pane takes the window, the others keep Arc's 220 pt minimum | ❌ | `MainWindowController.swift`, `SplitPaneTransition.swift` | `SplitPaneLayout` | Upstream 9629fd1. `SplitPaneLayout.expanding` and the 220 pt minimum are shared and already lay Windows' panes out; Windows needs the command and the menu item. |

## Little Windows, Peek and the Library

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Little Windows (`newLittleWindow`, `promoteLittleWindow`, `closeLittleWindows`), profile chip, ⌥⌘N from any app | 🟡 [#23] | `LittleWindowController.swift`, `GlobalHotkey.swift` | `LittleWindowLayout`, `SpaceWindow`, `GlobalShortcut`, `LittleWindowTarget`, `LittleMoveMenu` | Windows: Ctrl+Alt+N (also from any app, RegisterHotKey, skipped where AltGr+N types a letter), Ctrl+O; strip, Open in Space menu, profile chip, command bar, size/cascade and archive on close. The live page moves into the browser window (`cra_browser_set_parent`). Left: upstream 2bf4f8f's searchable 46 pt rows, scrolling and hidden chevron with one space; the grow animation; "Don't ask again"; `littleWindowOpenInMenu`; archive after 1/6/12 hours (`LittleWindowArchive`). Upstream c247e40 and 4e5ce86 make a picked space stay in that Little Window only, while the next follows the browser used last; use `LittleWindowTarget` for that policy. |
| Peek: card over the page with its own bar, Close, Expand, Add To Split | ✅ [#24] | `PeekChrome.swift`, `PeekDimPanel.swift`, `ChromiumChildFocus.swift`, `LittleWindowController.swift` | `PeekLayout`, `PeekBarColors`, `PeekTrigger`, `PeekVeil`, `PinnedNavigation`, `PeekTabs` (`openLinkTab`, `peekSplitTabs`, `joinSplit`) | Windows: the card is an owned HostWindow with the page-coloured bar (`Peek/PeekBarView.swift`); the veil, click catcher and round buttons are owned layered windows (`CraOverlay.cpp`, `Peek/PeekOverlays.swift`). Settings ▸ Tabs ▸ Links, Shift-click, Escape (from the page or the bar), Ctrl+O, Ctrl+Shift+T reopening it, the card keeping the keyboard while it is up (#26), links leaving it for a tab, the badge on the tab it came from. Left: the card growing out of the link and back (#204, `PeekTransition`); the veil only fades. Since #24 the Mac shrinks the page behind a Peek a little unless pages fill the window edge to edge (#221, `PeekVeil`, `PeekLayout.backdrop`) and keeps the browser window's shadow (#222, `ChromiumChildFocus.swift`); Windows' browser window already stays active under the card, and its page doesn't shrink yet. Since upstream 5e777bf and 3a85ee6 (#242) a Peek waits on its tab and comes back with it, and a click on another tab's row opens that tab while the Peek waits (`PeekPresence`); Windows closes the Peek instead. |
| Air Traffic Control: route links from other apps to a space or Little Window | ✅ [#29] [#31] | `AirTrafficControlView.swift`, `LinksPane.swift`, `AppDelegate.swift` | `LinkRouting`, `AirTrafficControl`, `ExternalLink` | #31's PC test (10 Nov): add/edit/remove, persistence, routes, deleted-space fallback, Default, focus cycling and Escape/✕/backdrop dismissal passed. Windows keeps the sheet under Settings ▸ Tabs; the Mac moved it to Links. Sync #8 carries upstream 692e524's named Little Window space through the shared choices, a secondary space menu in the Windows sheet and `WindowList.openExternal`; this new selection still needs its sync PC test. |
| Library in the sidebar (`openLibrary`), swipe or button slides it in | 🟡 [#27] | `LibraryView.swift` | `LibraryPage`, `LibraryLayout`, `LibraryList`, `LibrarySwipe`, `LibraryWidth` | Windows (`Sidebar/LibraryView.swift`): widens 70 DIPs for the rail (Downloads, Archived Tabs), search and ⋯ menu, rows by day; Ctrl+Shift+L, footer button, Escape and Back, and reopening the last page. Left: slide/swipe, Spaces/Media/Easels/Boosts pages, drag-out, Filter by profile (`LibraryFilter`, `LibraryFilterPanel.swift`), running downloads (`DownloadList`) and archived-row accents. Upstream 0473e3d and 22a8552 give the Mac a fixed 417 pt Library sidebar that yields to the page in a narrow window; b45f55e fixes a swipe immediately after leaving it. |
| History and archive view (`viewArchive`), Archive ▸ View Archive… (`showArchive`) and Clear Archive (`clearArchive`) | 🟡 [#27] | `LibraryView.swift` | `SidebarStore`, `LibraryList` | Ctrl+H (Chrome's History key) opens the Library's Archived Tabs: search by title or address, a click restores the tab where it was closed from; Restore, Copy Link, Remove from Archive, and Clear Archive in the ⋯ menu. Upstream d110dc6 made View Archive… and Clear Archive commands of their own: not in Windows' command bar yet. |
| Library ▸ Media (`viewMedia`): screenshots, pictures and videos from the folders shown, after Arc's opt-in card | ❌ | `LibraryMedia.swift`, `LibraryView.swift`, `MediaPreviewWindow.swift` | `MediaLibrary`, `LibraryPage` | Upstream 2294e13. Windows needs the folder scan (Pictures, Screenshots, Videos) and the grid. Since a8fde87, bf6648e and f547bd8: Arc's media preview (`MediaPreview`), grid and menu. |
| Easels (`newEasel`, `viewEasels`): Arc's canvas with text, shapes, freehand and captures, Library ▸ Easels | ❌ | `EaselBrowser.swift`, `EaselCanvasView.swift`, `LibraryView.swift`, `LibraryEaselGrid.swift` | `Easel`, `LibraryList` (`easels`) | Upstream f7e3b8f to 3e2757b. The model, tools, hit-testing and saving are shared; Windows needs the canvas (Win2D or a XAML Canvas). Since fea3d7c and f547bd8: Arc's grid of easel cards, pictures resized by their corners (`EaselResize`). |
| Boosts (`newBoost`, `viewBoosts`): restyle a site (colours, fonts, Zap, CSS and JS code with the eyedropper and hammer), Library ▸ Boosts with each site's icon | ❌ | `BoostStore.swift`, `BoostEditor.swift`, `LibraryBoostRow.swift`, `SiteIconLoader.swift` | `Boost`, `BoostPicker`, `SiteIcon` | Upstream 415ff0e, 5da196f, 8878058, a8fde87, 6523975. The model, picker and icon choice are shared; Windows needs the editor panel and injecting the boost into pages through CEF. `LibraryPage.boosts` is in CraCore; Windows' rail doesn't show it yet. |
| Now-playing player in the sidebar | ❌ | `NowPlayingTray.swift`, `NowPlaying.swift` | `AudibleHold` (Mac's WebKit tabs) | Windows counterpart for media keys: System Media Transport Controls. |
| Downloads rename card | 🟡 | `DownloadRenameCard.swift` | `TidyDownloads` | The Windows list has open and Show in Folder; the rename card comes with Tidy Downloads. |

## Tabs and memory

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Auto-archive Today tabs after a set time | ✅ [#14] | `TabsPane.swift` | `SidebarModel` (`AutoArchiveThreshold`) | Upstream 2e8a659 adds 90/180 days and tolerant decoding of newer values. Windows' picker lists the shared cases, so the new thresholds arrive with the model; recheck the menu in the sync PC test. |
| Tab freezing and sleeping, Tab Cleanup timers, calls stay awake | ❌ | `BrowserManager.swift` | `TabSleepPolicy` | The policy is shared; Windows needs the CEF discard calls and the two Settings ▸ Tabs switches. Since upstream 135f794 (#214) the policy reads a `PageState` per page and says why it passed one over. Since upstream c09f3c3 (#237) critical memory pressure closes 9 pages a pass and each pass logs one line per way of closing (`TabSleepPolicy.PassLog`). |
| Mute a tab (`muteTab`), speaker icon, camera and microphone dot | 🟡 | `SidebarRowViews.swift` | `SidebarModel` | The bridge can mute; the sidebar shows no speaker yet. |
| Open links in new tabs in the background | ❌ | `TabsPane.swift` | `LinkMenu` | |
| Background tabs laid out at the pane's size, first seconds of a tab, hidden tabs give their GPU tiles back (#195) | ❌ | `BrowserManager.swift`, `PageProbe.swift`, `PageScript.swift` | `HiddenFrameRelease` | `PageScript.swift` is Foundation only: move it to CraCore. |
| Tabs keep back/forward history across relaunch; Back closes a link-opened tab and returns to its source | ❌ | `PageHistoryStore.swift`, `BrowserManager.swift` | `PageHistory`, `BackToReferrer` | Upstream 5fe9cd2 and fe7810f. Windows needs Chromium serialized-history save/restore callbacks and referrer-aware Back behavior; the shared model alone does not preserve a CEF page's history. |

## Media and capture

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Capture (`capturePage`): copy the page | 🟡 [#17] | `CaptureOverlay.swift`, `ViewSnapshot.swift`, `CaptureAccess.swift`, `MainWindowController+Capture.swift`, `LittleWindowController+Capture.swift` | `PageCapture`, `ContentCapture` | Windows copies the visible page or the full page. Missing: element/region pick with copy/save/send, `captureFullPage` and `capturePortrait` as commands, New Easel and Send To… an easel. Upstream 6d6ede8 makes capture target a Peek's page and show its result inside the Peek; that path also needs Windows support. |
| Picture in Picture (`pictureInPicture`), automatic on leaving a video tab or a Meet call (Document Picture in Picture, upstream #198), throw into corners | ❌ | `PictureInPictureChrome.swift`, `PictureInPictureControls.swift` | `PictureInPictureGesture`, `PictureInPictureThrow`, `PictureInPictureLayout` | Shared gestures, throws, bar/scrim and limits. Upstream a4c4b9b, c247e40 and 9ae7224 refine Chrome window focus, reopen on the previous display and spring-back from beyond the screen edge. Windows needs the native window and bridge; cbb5753's automatic PiP setting is per site. |
| Protected media (DRM services in Safari's engine) | ➖ | `PageEngines.swift`, `WebKitBrowser.swift`, `WebKitStores.swift` | `ProtectedMedia` | Mac only (FairPlay in WebKit). On Windows the counterpart is a Widevine-capable CEF build; the per-site choices in `ProtectedMedia` can be reused. |
| Screen sharing with tab audio, web notifications shown and clicked | 🟡 [#17] | `CraCEF.mm` | `PermissionPrompt` | The prompts work on Windows; Chrome's screen picker and notifications opening their page haven't been checked on the PC. |
| Speech recognition on device | ❌ | `CraCEF.mm` | `ChromiumLocale` | The `speech-on-device` CEF patch is Mac only. |

## Profiles, privacy and site data

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Permission prompts | 🟡 [#17] | `CraCEF.mm`, `BrowserManager.swift` | `PermissionPrompt`, `PermissionAsk` | Windows prompts work. Upstream f8a9d1f queues a hidden tab's camera/microphone request until the tab is shown and logs outcomes; Windows does not yet use `PermissionAsk` for that waiting policy. |
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
| Opt-in anonymous usage stats and crash reports | ❌ | `SharingService.swift`, `PrivacyPane.swift`, `OnboardingSteps.swift`, `SidebarView.swift` | `Sharing` | Upstream ff99afd, 2eb5877 and 0495029; `docs/sharing.md` describes the fields, release-only guard, daily timing and separate consent. Upstream CONTRIBUTING now expressly documents this opt-in exception. The models and Mac service arrive in the sync; Windows has no sending service, consent UI or sidebar prompt, so the Windows app sends none of these reports. |

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
| Settings window, back and forward, panes listed by `DiaSettingsPane.windowsPanes` | 🟡 [#14] | `SettingsWindowController.swift`, `SettingsKit.swift`, `MemberCardView.swift`, `SettingsArt.swift`, `SettingsPictures.swift` | `DiaSettingsNavigation`, `DiaSettingsMetrics`, `SettingsTab`, `MemberCard`, `MaxMasterSwitch`, `TranslateReset` | Windows has General, Tabs, Profiles and Shortcuts. Panes not on Windows yet: `links`, `max`, `privacy`, `extensions`, `plugins`, `performance`, `advanced`. Upstream d34987a/b4c20de add inset selection, pane clipping, descriptive rows and layout pictures; Windows needs those visual refinements. The #31 PC test still showed clipped Back/Forward focus outlines; keyboard reactivation needs a separate focused reproduction. Upstream 80cdfe7/caaa884 (#372) moved the Mac to Arc 1.172.2's window: 684 × 650 pt with ten tabs in a toolbar (`SettingsTab`), a member card first. Windows still draws Dia's sidebar window (its CraCore types are now `Dia*`); next: follow the tab toolbar. |
| General | 🟡 [#14] [#29] | `GeneralPane.swift`, `AppIconPicker.swift` | | Windows has default-browser registration and Open at login. #31's PC test verified title-bar icons on browser, Settings and Little Windows; taskbar-button appearance remains unverified. Missing: the app icon picker, including upstream's Violet choice and 72 pt tiles (b454fdb, 5e5a220, 41deeb9). |
| Tabs | 🟡 [#14] | `TabsPane.swift` | `SidebarModel`, `AddressBarPlacement` | New Tab placement, single-space header, cleanup, Peek, external links and the #31 Air Traffic Control sheet are present. Missing: address-bar position (3d560c2), current-space-only search (cab6d40), sleeping, shared favorites, background-tab preference, Little Window archive time and upstream's descriptive/pictured layout. |
| Links | 🟡 [#31] | `LinksPane.swift`, `AirTrafficControlView.swift` | `LinkRouting`, `AirTrafficControl` | Upstream b4c20de moves Little Windows, Peek, foreground-link preference and Air Traffic Control out of Tabs into Settings ▸ Links. Windows keeps its implemented rows under Tabs; it does not list a Links pane yet. |
| Shortcuts | ✅ [#15] | `ShortcutsPane.swift` | `KeyBindingRegistry` | |
| Profiles | ✅ [#19] | `ProfilesPane.swift` | `SpaceProfiles` | |
| Privacy | ❌ | `PrivacyPane.swift` | `SecureDNS` | With the blocker and HTTPS-only. |
| Extensions | ❌ | `ExtensionsPane.swift` | | |
| Plugins | ❌ | `PluginsPane.swift` | `LiveFolderPlugin`, `LiveFolderPluginPackage` | With the live-folder plugin runtime: install, permission summary, enable/disable, reload and remove packages. |
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
| Default browser (`setDefaultBrowser`), opening links from other apps | 🟡 [#29] | `SystemIntegration.swift`, `AppDelegate.swift` | `ExternalLink` | Windows registers under HKEY_CURRENT_USER (`CraHTML`, `StartMenuInternet\Cra`, RegisteredApplications) and opens Windows' Default apps; the user chooses the default. External links and second launches work through Chromium's process singleton (`OnAlreadyRunningAppRelaunch`). #31's PC test confirmed the remaining Windows 11 25H2 gap: searching Default apps still does not list Cra, despite registration. No default association was changed by the test. Signing, installer registration and refresh at sign-in remain avenues to investigate; pinning to taskbar remains a release task. |
| Another app's link (zoommtg:, slack:) in a new tab or window opens the app after asking, not a blank tab (#207) | ❌ | `AppLinkPrompt.swift`, `CraCEF.mm` | `AppLinks` | Upstream d1ad2af. Windows: CEF's external-protocol callback and a prompt in the page's place. |
| Links Cra opens to crabrowser.app (release notes, help) name the button they came from | ❌ | `AppDelegate.swift`, `SoftwareUpdater.swift` | `SiteLinks` | Upstream 94c1fc3. Comes with Windows' help links and the updater. |
| `cra://` scheme for scripting (`cra://open?space=`) | 🟡 [#31] | `AppDelegate.swift`, `TestGesture.swift` | `CraLink`, `ExternalLink`, `InternalURLRaise` | #31's PC test passed registration, commandbar query/edit, dismiss, foreground/named-space/background/Little Window opens, normal-mode refusals, opt-in action/navigate and cold starts. The background tab remained unread and selection did not change. Sync #8 carries upstream 6a4e05a's no-activation policy for background opens. Left: key, import, debug and `CRA_COMMAND_FILE`; Mac link parsing still has not switched to `CraLink`. |
| Auto-update (`checkForUpdates`), update banner | ❌ | `SoftwareUpdater.swift`, `UpdateBanner.swift`, `UpdaterWindow.swift` | `UpdateNotice` | WinSparkle reads the same appcast. Upstream 110b3c6/ad2ed55 keep the news/sponsor card and show an update-news toast with the sidebar hidden. Windows needs its updater and this notice flow. Phase 3. |
| Signed installer | ❌ | | | Authenticode and MSIX or Inno Setup. Phase 3. |
| Custom app icon | ❌ | `AppIconManager.swift` | | |
| Bluetooth device cache for Chromium | ➖ | `ChromiumBluetoothCache.swift` | | Mac only (CoreBluetooth). |
| Chromium follows the system language | ❌ | `AppDelegate.swift` | `ChromiumLocale` | Shared decision; Windows passes the user's UI language. |
| Shortcuts set in the system's keyboard settings work in pages | ➖ | `AppDelegate.swift` | | macOS only. |
| AppleScript with Arc's dictionary, JavaScript from Apple Events off by default (`allowAppleEventsJavaScript`) | ➖ | `AppleScripting.swift` | | macOS only (upstream de695e2). Windows' scripting goes through `cra://` (its own row). |
| Keep Cra in the menu bar after quitting (#231) | ❌ | `MenuBarItem.swift` | `MenuBarMode` | Upstream 96c0255. Windows' counterpart is a notification-area icon that keeps Cra running. |
| Open a Safari page handed off from an iPhone | ➖ | `AppDelegate+Handoff.swift` | | Upstream 4fd9b3e uses macOS Handoff/NSUserActivity. There is no direct Windows Handoff counterpart in this port. |
| Sync sidebar, settings and shortcuts through iCloud or a folder | ❌ | `SettingsSyncService.swift`, `SyncSection.swift` | `SettingsSync` | Upstream cae2918. Folder manifests, merge and conflict decisions are portable; Windows needs the folder chooser, file coordination/watching and settings UI. iCloud integration is Mac-specific. Sharing consent and MCP permissions do not sync. |
| Agents in Cra: permissioned local MCP server and bridge | ❌ | `MCPServer.swift`, `MCPListener.swift`, `MCPConnection.swift`, `MCPPeer.swift`, `MCPInput.swift`, `MCPPage.swift`, `MCPTransfers.swift` | `MCPAgents`, `MCPAgentAids`, `MCPInputPlan`, `MCPProtocol`, `JSONNumber`, `MCPReferences`, `MCPSession` | Upstream 31187f8. Protocol/session/reference/input policies are shared. Windows needs transport/client identity, approval UI and native page/input/capture integration; this sync does not start an MCP listener on Windows. JavaScript and history access remain separate opt-ins in the model. |
| Feature flags | ❌ | `FeatureFlags.swift` | | |
| Persistence of the data folder | ✅ [#5] | `Persistence.swift`, `SidebarStore+App.swift`, `Scheduler.swift` | `JSONStore`, `Scheduling`, `SidebarStore` | `%LOCALAPPDATA%\Cra` holds the same files. Keep both versions of `Persistence.swift` in step: Mac tests compile it with CraCore. |
| Portability helpers, CraCore seen by every Mac file | ✅ [#1] [#16] | `CraCoreExports.swift`, `TestScreen+AppKit.swift` | `CGVector+Portable`, `CGAffineTransform+Portable`, `ChromiumLocale`, `TestScreen` | `TestScreen` is the portable test-display decision; `TestScreen+AppKit.swift` applies it only on the Mac. New shared geometry helpers stay guarded for Linux and Windows. |

The #31 PC test also reproduced black text on a dark background on an unstyled page, over
both file:// and localhost HTTP. The cause is still open. Escape worked during ordinary sheet
editing; one Escape after external navigation and automated Settings reactivation was ignored,
as were some Alt+F4 attempts. Close buttons worked and no crash dump was produced; this remains
an unconfirmed reactivation/focus follow-up, not a demonstrated #31 regression.

## Moving Mac code into CraCore

Code that decides something without a window, written once for both apps. In order of what
the next Windows PRs need:

1. `FloatingSidebarGeometry.swift` (hidden sidebar): a CLAUDE.md known exception, already
   Foundation only. (`DevToolsToggle` moved in #20.)
2. `Services/Import/` parsers (Import PR): replace `NSImage` with PNG `Data` and the
   `~/Library` paths with a passed-in root, keep the Mac's fixture tests.
3. `PageScript.swift`, `CraLog.swift`, `NativeMessagingHosts.swift`,
   `ExtensionProtocolReply.swift`, `SearchSuggestLoader.swift`: Foundation only today.
4. `EmojiCatalog+Data.swift`: data with no imports, for the space icon picker.
5. `AppDelegate.handleInternalURL`'s reading of cra:// links: `CraLink` (#31) reads them the
   same way; the Mac can switch over to it.
6. The bookmarks writer in `SidebarExport.swift` and the domain list behind `CraContentBlocker.h`
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

The 40 commits #30 merged (de695e2 to f547bd8):

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

PR #31 then merged 9161e2d, a Mac-only Library grid change. Upstream sync #8 reviews the
following **91 commits**, from 110b3c6 through 2bf4f8f (10 Nov 2026). This is the full triage;
shared models arriving in the merge do not make their Windows UI or integration implemented.

| Commit | What | Windows |
|---|---|---|
| 110b3c6, ad2ed55 | Update news keeps the sponsor card and reaches a hidden sidebar as a toast | Auto-update row (`UpdateNotice`); Windows updater and notices are still missing. |
| 4fd9b3e | Open an iPhone Safari Handoff page in Cra (#254) | New Handoff row; macOS integration only. |
| bccd472 | Hide Chromium's On startup settings page through CEF codecs3 | Windows fetches the same CEF version, but its stock build does not include `settings-no-on-startup.patch`. |
| 4fc05d2, 37477ee | Arc folder icon picker and masks; dropping a tab puts it first and keeps the folder shut (#250, #266) | Folder and drag/drop rows (`FolderSymbol`); Windows has neither picker nor sidebar drag/drop. |
| 4e38498, 0f20e1f | System App Shortcuts retitle Hide/Show Sidebar; Shift+digit records the digit (#253, #321) | Mac shortcut naming is system-specific. Shared `KeyChord` keeps the recording decision; Windows already matches virtual keys. |
| a7ea20f, dc404ff | Space dock dots, squeezed docks and a hovered dot expanding to its icon (#252) | Spaces row (`SpaceDock`); Windows still draws emoji buttons. |
| 001afb2 | Slow first response notice after 10 seconds, with Stop Loading (#256) | New slow-response row (`SlowResponseNotice`); Windows scheduling/toast integration remains. |
| c795319, 0051bb3 | An extension selecting a tab and creating a page never raise a background Cra (#239, #274) | Browser-window row (`TabActivationRaise`); check native focus behavior on Windows. |
| 7c98d46 | Start on a new tab when opening Cra | Launch-settings row (`LaunchStart`); not applied on Windows yet. |
| 9630b47, 249adb7, 8a6c6bf | Page menu split action, one localized new-tab item and Option-click split (#257, #276, #298) | Page context menu row (`LinkMenu`, `PageMenuLabels`, `LinkSplitClick`); Windows callbacks remain. |
| 9e27b3d, 43277d6 | Intel Mac artifacts/appcast and README links (#236) | Mac release packaging; Windows x64 artifacts remain independent. |
| c4ee4dc | A flick ticks once per page change, like a drag (#260) | Swipe row (`PageDetentHaptics`); native Windows swipe/haptics integration remains. |
| b454fdb, 5e5a220, 41deeb9, 13a283b | Violet icon, Arc rim, sharper 72 pt picker tiles and restoring the selected Dock icon (#259, #319) | General/custom-icon rows; Windows icon picker remains missing. |
| 692e524 | A Little Window route may name a space (#258) | Air Traffic Control row: sync #8 adapts the shared menu and Windows external routing, retaining the named space/profile. |
| c1b0f03 | Frame release leaves no grey pane or ghost window in fullscreen (#261) | `HiddenFrameRelease` is shared; native Mac window/CEF handling does not port automatically. |
| a4c4b9b, c247e40, 9ae7224 | PiP focus and control sizes, reopen on its display, and spring back from beyond a screen edge (#262, #316, #332) | Picture in Picture row (`PictureInPictureLayout`); Windows still has no native PiP. c247e40 also starts the Little Window target refinement below. |
| a17a8fe, 86dbb44, 9927600 | Favorite double-click returns home; Arc sidebar hover/fill/reveal parity; opt-in logo-coloured favorite outline (#264, #293, #267) | Favorites, theme and hidden-sidebar rows (`FavoriteClick`, `FavoriteSelectionTint`, `FavoriteOutlineColors`, `SidebarTones`, `CardFill`); Windows visual/gesture work remains. |
| 5fe9cd2, fe7810f | Back closes a link-opened tab; history survives relaunch (#273) | New history/referrer row (`BackToReferrer`, `PageHistory`, `PageHistoryStore.swift`); needs Windows serialized history callbacks. |
| e44ba8f | Download pause/resume/cancel, row menu, bin ring and quit confirmation (#272) | Downloads row (`DownloadMenu`); history/model changes are shared, native Windows controls/callbacks remain. |
| 5348194 | Chromium audible state governs tab sleep; log skipped pages and run a pass on wake (#275) | Tab-sleep row (`TabSleepPolicy`); Windows sleep integration remains missing. |
| f26ff34 | Test copies keep their windows on one display | Portability/test row (`TestScreen`, `TestScreen+AppKit.swift`); macOS screen placement only. |
| d336ed8, d0e7e38, bff29b8, 0002408 | Extension side-panel identity, tabs.create reply, popup close hit area and unpacked-copy precedence (#265, #292, #296, #299) | Extension rows; `UnpackedCopies` is shared. Windows extensions remain phase 2 work. |
| 6a4e05a | A background `cra://open` leaves Cra behind the app in use | Protocol row (`InternalURLRaise`); sync #8 stops activating the Windows browser for background opens. |
| f8a9d1f | Wait to ask a background tab for camera/microphone until it is shown (#286) | Permissions row (`PermissionAsk`); Windows request queue/logging remains. |
| cb03143 | Tearing a tab into a Blank Window preserves its profile (#288) | Blank Window and drag/drop rows (`TabTearOff`); Windows drag layer remains. |
| 7f5759f | Arc File menu sections, Share and New Profile (#279) | New File-menu row (`FileMenu`, `share`, `newProfile`); sync #8 exposes existing Windows actions but the menu is still missing. |
| 46cfb2a, 06d5380 | Sidebar 164–500 pt, snap to 228, drag shut under 82 and narrow header (#287) | New width/resize/header row (`SidebarWidth`, `SidebarResize`, `SidebarHeaderLayout`); Windows keeps its current fixed layout. |
| 98bb2c1, 7be55ee, fb2c304 | Little Windows over fullscreen, fullscreen window/light transitions, hidden-sidebar fullscreen reveal (#277, #308, #315) | Mac Spaces/window treatment; Windows hidden sidebar/fullscreen integration remains tracked in the window rows. |
| d34987a, b4c20de | Settings selection inset/clipping; descriptive rows, layout pictures and a Links pane (#269) | Settings rows (`SettingsArt.swift`, `SettingsPictures.swift`, `LinksPane.swift`); Windows retains its existing four panes and Tabs link controls. |
| 3bd548d, 50d2fa9, 0c81531 | Command-bar sizes, theme row/badge and the corrected search-suggestions notice (#268, #314) | Command-bar and notice rows (`CommandBarTones`, `SearchSuggestionsNotice`); Windows UI remains. |
| b2ad480, e9dca23 | Easel text pick/edit/delete and restoring backdrop when expanded from Peek (#270, #309) | Easels row; Windows still needs the canvas and its interactions. |
| 895b0c5 | Arc sidebar + creation menu and +/× transition (#271) | New creation-menu row (`SidebarCreationMenu.swift`); Windows + still creates a space directly. |
| cf0ae5a | Mouse utilities' Option+Left/Right events can switch spaces (#285) | Mouse-buttons row (`MouseButtonSpaceSwitch`); Windows XBUTTON integration remains. |
| 2e8a659 | 90/180-day cleanup and tolerant newer-setting decode (#278) | Shared `AutoArchiveThreshold` and Windows all-cases picker gain the choices; sync PC test should recheck them. |
| f6c91a3 | Per-tab/data: favicon survives relaunch on one host (#291) | Favicons row (`FaviconKey`); Windows still caches by site. |
| dd254cf, ae83b43 | Sponsor accounting and release-media style | Release tooling/docs; no Windows app behavior. |
| 9fac212, 64ccaf0 | Ideas form/housekeeping and criteria for non-Arc features (#284) | Repository policy/tooling; no Windows app behavior and no upstream contact from this fork. |
| 3a6b81b | Hidden sidebar reveals in front of a Peek (#295) | Hidden-sidebar/Peek rows; Windows does not have that sidebar mode yet. |
| cae2918 | Sidebar/settings/shortcuts sync through iCloud or a folder (#289) | New sync row (`SettingsSync`); folder mode is portable but Windows integration remains. |
| 664cc6a, b08beb3 | JavaScript live-folder providers and stable built-in plugin paths (#294) | New plugin row; `LiveFolderPlugin*` decisions are shared, Windows runtime/permissions/UI remain. Old GitHub client removed. |
| b45f55e | A fast swipe immediately after leaving Library continues to the next space | Library row (`LibrarySwipe`); Windows swipe integration remains. |
| c1aadf7 | Theme editor removes the final colour to make Arc's colourless theme (#300) | Theme editor row (`SpaceThemeVariants`); Windows editor remains missing. |
| 3d560c2 | Address-bar position can be changed in Tabs (#305) | Tabs/toolbar rows (`AddressBarPlacement`); Windows toolbar and placement control remain missing. |
| 0473e3d, 22a8552 | Library is 417 pt wide and yields to a page in a narrow window (#302) | Library row (`LibraryWidth`); Windows still widens its sidebar by its rail width. |
| e1c8765 | Music notes float from a playing favorite (#303) | New music-notes row (`MusicNotes`, `MusicNotesView.swift`); Windows audio/overlay integration remains. |
| cab6d40, d55e7a0 | Search only the current space; choose a search engine per space (#307, #306) | Command/search rows; shared decisions arrive, Windows settings and scope/engine wiring remain tracked. |
| 9d5160d, 2e0134f | Scenario reopen-alert handling, 1x snapshot reporting and re-recorded dock snapshots | Test tooling/snapshots; no new Windows app behavior. |
| 31187f8 | Agents in Cra: local MCP server (#193) | New Agents row (`MCPProtocol`, `MCPSession` and related policies); Windows transport, identity and integration remain. |
| ff99afd, c9bb58b, 2eb5877, 0495029 | Opt-in stats/crash reports, readable reporting docs, send timing and updated-user consent card | New sharing row (`Sharing`). Reviewed against the explicit opt-in exception now in CONTRIBUTING and `docs/sharing.md`; Windows does not send reports or show consent prompts. |
| 386fbf8 | Translate state, affordance and native popover (#310) | New translate row (`PageTranslation`, `BrowserManager+Translation.swift`, `TranslatePopover.swift`); Windows needs patched bridge/UI. |
| 4e5ce86, 2bf4f8f | Little Window space pick is local to that window; Arc 1.172.1 searchable/scrolling 46 pt Open In rows, no chevron with one space (#316, #331) | Little Windows row (`LittleWindowTarget`, `LittleMoveMenu`); Windows' existing flyout still needs the new target and searchable-menu behavior. |
| 43e8adc | Page/toolbar stay put while the sidebar slides (#317) | Hidden-sidebar row (`SidebarSlidePage`); Windows sidebar mode remains missing. |
| 6d6ede8 | Capture a Peek's page inside that Peek (#320) | Capture row (`CaptureAccess.swift`, window capture extensions); Windows Peek-specific capture integration remains. |
| cd8f3f5 | Copy every picked sidebar tab's URL, one per line (#322) | Copy URL/sidebar selection rows; Windows multi-selection and multi-link copy remain. |
| cbb5753 | Automatic PiP is a per-site switch (#326) | Site Control Center/PiP rows; Windows needs the switch with PiP support. |

Upstream sync #9 merged the 80 commits after 2bf4f8f (72bfc8f to b517a00). Conflicts: upstream moved
`SplitPaneLayout` into CraCore beside the fork's copy (merged, keeping Windows' `flipped` layout and
divider hits), gave keybindings.json priorities (the CraCore registry now stores `KeyBindingOverrides`),
and replaced the Mac's Dia-style Settings window with Arc's tab toolbar (the fork's CraCore Settings
types for Windows became `DiaSettingsPane`, `DiaSettingsNavigation` and `DiaSettingsMetrics`).

| Commit | What | Windows |
|---|---|---|
| 72bfc8f, bf2878d, f9319aa, 61f209d | Little Window menus act on its page; Arc 1.172.1's gradient strip and host-only pill with an http padlock (#329, #330); ⌥⌘N's compact card at the top right (#337); Open in ⌘O on the Tabs menu | Little Windows row (`LittleAddress`, `LittleCard`, `LittleWindowTrigger`, `TabsMenu`). Windows' strip is still 1.168's flat navy and ⌥⌘N opens a full window. ❌ |
| f7b1ba4, f4ddb16, 9d8749d, afe4417 | CEF 156.0.27 (Chromium 156.0.8078.96); release and CEF-update tooling | 156.0.27 is upstream's own build (CEF's 8078 head on Chromium .96, with 11 security fixes over .88); Spotify has no Windows download of it, so `fetch-deps.ps1`'s `$stockPin` keeps Windows on stock 156.0.26 (Chromium .88). Next: build CEF for Windows with Cra's patches (also needed for H.264/AAC), or follow Spotify's next stock release. 🟡 |
| 3e3a82b | Fingerprinting protection switch in Settings ▸ Privacy (a CEF patch) | Privacy pane row; Windows has no Privacy pane and the patch isn't in Windows' CEF. ❌ |
| 2b067f9, e2ba4eb, f2503d4, 7ad6b2f, f46364a | Space dock right-click opens the space menu (#339); floating and hidden sidebar reveal details (#341, #350) | Hidden-sidebar and space menu rows (`SpaceMenuLayout`, `SpaceMenuIcon.swift`, `FloatingSidebarGeometry`, now in CraCore upstream). Windows has no hidden sidebar yet. ❌ |
| ba67d78, 9a62558 | Edit the address in place in the sidebar instead of the command bar (#344) | `SidebarAddressEdit`; Windows has no sidebar address field option. ❌ |
| 50adbd4 | A screenshot app's pointer over a page picks the main window (#346) | Mac only (macOS screenshot picker): `WindowContentGrabber.swift`, `ScreenshotPick`. ➖ |
| 9ea5240 | 5-Second Previews: Arc Max hover cards on Apple Intelligence (#324) | Arc Max row (`LinkSummary`, `LinkSummaryCard`, `LinkSummaryService.swift`, `LinkSummaryPreview.swift`, `LinkSummaryShareImage.swift`); needs an on-device model on Windows. ❌ |
| 3d6548c | A double-click on a pinned tab's favicon goes back to the pinned URL (#345) | Pinned tab extras row (`PinnedIconClick`). ❌ |
| 241cc8c | One click adds Cra's MCP server to Claude Code, Cowork, Codex, Cursor and others | Agents row (`MCPAgentSetup`, `MCPAgentInstaller.swift`, `MCPAgentTiles.swift`); Windows has no Agents server yet. ❌ |
| b58b69d | The Library pushes the page past the window's edge instead of narrowing it (#340) | Library row; Windows still narrows the page. ❌ |
| 3a60bd3, 95f020f | chrome:// tabs open without their saved history (a crash at launch, #325) | Windows restores tabs through CraCore's store; the history guard is in the Mac's `BrowserManager.swift`. Check on the PC. |
| 5887873, 7143532, 0fdf7df, 4d2961d, 37efb05 | Page-top dragging: a 60 pt band, the page gets presses at once, under the toolbar too (#335, #363) | Page-top drag row (`PageTopDrag`, `PageWindowStart`, `PageWindowStart+AppKit.swift`). ❌ |
| d24295c, ad9fd40 | View Source opens the page's source in a new tab (#348) | `ViewSource`, `PageCommands.swift`; Windows' View Source still opens Chromium's own window. ❌ |
| 60eb2c7 | DevTools in a Little Window and a Peek dock beside the page (#348) | DevTools row (`DevToolsPlaceholder`, `DevToolsWindowChrome.swift`); Windows docks DevTools in the browser window only. 🟡 |
| 5eca911 | The picked app icon stays in ⌘-Tab and the Dock (#319) | Mac only: `ChromiumDockTile.swift`. ➖ |
| 52e8ef7 | Extension icons from their 2x file; install prompts over Cra's window (#349) | Extensions rows (`ExtensionIcons`). ❌ |
| 9b6877e | Live folder plugins' helper sandbox profile (#353) | Mac only (macOS sandbox). ➖ |
| ba49acf, ebce13c, ea617f9 | Sync: later bundles apply by themselves; repairs (#352, #378) | Sync row; Windows has no sync. ❌ |
| 068df70, 5e02b46 | Extension windows over a full-screen Cra; two displays and full-screen Spaces (#351, #354) | Mac only (macOS Spaces). ➖ |
| e020f1d, d31a84f, 109c697, 9dd665f, b980028, 1f88af4 | Picked tabs: Arc's menu, Copy URLs, Share N Items; Share Folder… links; the "Send this Folder" warning (#356, #357) | Sidebar multi-selection row (`PickedTabsMenu`, `FolderShareLink`; its links are raw DEFLATE, which `RawDeflate` packs and reads off Apple platforms). Windows has no multi-selection. ❌ |
| 2a0ee52 | Switch to Light/Dark Mode turns the browser too (#362) | Website appearance row; Windows has no appearance commands yet. ❌ |
| 8f9af14, c0981c0, fccc893, 43afe0e | Peek grows from web-component links (#359); ⌘-click Expand loads in the source tab (#380); Peek buttons rise and press (#385); ⌘T in a Peek (#379) | Peek row (`PeekExpand`, `PeekControlLook`). Windows has none of these yet. ❌ |
| eda6089, cba9995 | Copy URL glyph animates link → checkmark → link (#361); a Copy URL scenario (#322) | `CopyCheck`, `CopyCheckAnimation.swift`; Windows' Copy URL button doesn't animate. ❌ |
| f5751d6, 537dc09 | ⌘W closes Settings, not the tab behind it (#364) | Windows Settings is its own window: Ctrl+W there should close it. Check on the PC. |
| 2a43142, deb7808 | Blocked pop-ups: a button with Chrome's list, Open All and Always Allow (#357) | New blocked pop-ups row (`BlockedPopups`, `BrowserManager+BlockedPopups.swift`, a CEF patch). ❌ |
| 7ee415b, dd2c4e4, e9e4b7d | Homebrew cask, README, Find and Replace skipped | Nothing for Windows. |
| 747ad0a | Music notes keep floating when muted or with Reduce Motion (#303) | Music notes row. ❌ |
| 72a30bf | Sidebar rows and Favorites tiles push in while pressed (#367) | `SidebarRowPress`; Windows rows don't press in. ❌ |
| 7665a0f | Logi Options+ Back/Forward gestures (#369) | Mouse buttons row. Check on the PC whether a mouse's Back and Forward buttons already reach Windows' pages through Chromium. ❌ |
| 8d1f2b9, 761153e | Zap with a confirm popover and a shelf (`ZapShelf.swift`, `BoostZap`); Boosts gallery links (`SharedBoost`, `BoostInstall.swift`) | Boosts row. ❌ |
| e4b7447 | Easels: Arc's colours, picker, menus, undo, link cards and live captures | Easels row (`EaselHistory`, `EaselLinkMetadata`, `EaselObjects`, `EaselSnap`, `EaselCards.swift`, `EaselLivePage.swift`, `EaselServices.swift`). ❌ |
| 8ad3f9e | A two-finger swipe back closes a link's tab to the one it came from (#370) | `ChromiumHistorySwipe.swift`; Windows has no swipe back. Back itself already does it (`BackToReferrer`). 🟡 |
| e18f093, 84accc5 | Settings: Show full URL, More Settings…, Reset Translated-site Prompts; ⌥⌘-click opens a Little Window (#373) | Settings and Little Windows rows (`TranslateReset`, `TranslatedSitePrompts.swift`, `LittleWindowTrigger`). ❌ |
| 8f146f3 | Command bar rows under a still pointer leave the top row selected (#382) | Command bar row (`HoverGate`, `CommandBarOpening`). Check Windows' bar on the PC. |
| 9ce8012 | Permission requests in Arc's card at the page's top left (#371) | Permission prompts row (`PermissionPopover.swift`, `ChromiumDialog`, `ChromiumDialogs.swift`). Windows still uses its own prompt. 🟡 |
| c810a20 | A Peek from a favorite badges the tile with the page's favicon (#381) | Favorites row. ❌ |
| 80cdfe7, caaa884 | Settings: Arc's tab toolbar window, member card, Share Cra (#372, #377) | Settings window row (`SettingsTab`, `MemberCard`, `MemberCardView.swift`, `MaxMasterSwitch`). ❌ |
| a866227, f052e7c | Picture in Picture: double click returns to the tab (#383); Arc's scrubber (#384) | Picture in Picture row (`PictureInPictureScrubber`). ❌ |
| b478731 | Profiles: the per-profile "New documents" app and its command bar command (#375) | Profiles row (`NewDocumentApp`); CraCore's `SuggestionEngine` already offers the command once a profile has the setting. ❌ |
| fb6d039, b517a00 | Previews on favorites and pinned tabs: Linear, Notion, Figma, Confluence, Outlook and Notion Calendar (#376) | Favorite previews row (`RecentPagesPreview`, `OutlookPreview`, `OutlookClient.swift`). ❌ |
| 115e806 | Shortcuts: who gets the keys, Prefer Cra, Use Both or Prefer Websites (#374) | New shortcut priority row (`ShortcutPriority`, `ShortcutSearch`). ❌ |
| 9629fd1 | Expand Current Split (`expandSplitPane`) | New Expand Current Split row (`SplitPaneTransition.swift`). ❌ |

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
[#31]: https://github.com/vishnu597/cra-windows/pull/31
