# Mac feature parity

Every feature of the Mac app, what the Windows app has of it, and where the code that both
can share lives. The goal is the Mac app's features on Windows, built on the Mac's own logic:
what decides something goes in CraCore once and both shells call it (CLAUDE.md, rule 1).

<!-- upstream-reviewed: bb167523 -->
Upstream reviewed through **bb167523** (VictorKildahl/cra main, 21 Nov 2026), every commit triaged
under Waiting in upstream (sync #26: 16 commits after 15ae9afc). The Windows gaps below remain explicit rather
than inheriting the Mac's status.

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
| Window, pages and toolbar | 11 | 8 | 0 | 8 | 1 |
| Sidebar | 8 | 12 | 0 | 9 | 0 |
| Command bar and shortcuts | 1 | 6 | 0 | 3 | 0 |
| Split view | 2 | 3 | 0 | 0 | 0 |
| Little Windows, Peek and the Library | 2 | 4 | 0 | 4 | 0 |
| Tabs and memory | 2 | 2 | 0 | 4 | 0 |
| Media and capture | 0 | 3 | 0 | 2 | 1 |
| Profiles, privacy and site data | 6 | 2 | 0 | 6 | 0 |
| DevTools and Developer Mode | 2 | 0 | 0 | 1 | 0 |
| Extensions | 0 | 3 | 0 | 2 | 0 |
| Settings | 2 | 7 | 0 | 2 | 0 |
| Import and onboarding | 0 | 3 | 1 | 1 | 1 |
| Arc Max (on-device AI) | 0 | 0 | 0 | 0 | 6 |
| System integration and release | 4 | 3 | 0 | 10 | 9 |
| **All** | 40 | 56 | 1 | 52 | 18 |
<!-- /summary -->

## Window, pages and toolbar

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Browser window with pages inside it (CEF child windows), crash-safe start | ✅ [#2] [#3] | `main.swift`, `AppDelegate.swift`, `AppComposition.swift`, `MainWindowController.swift`, `ShellView.swift`, `BrowserManager.swift`, `EmbeddedPages.swift`, `ChromiumWindowCorners.swift`, `ChromiumChildHover.swift`, `ChromiumChildFullscreen.swift`, `WindowDragGesture.swift`, `CraCEF.mm`, `CraCEF.h`, `main.cc`, `PageHostWindows.swift` | `ChromiumCrashState`, `JSONStore`, `Scheduling`, `ObserveChanges`, `TabActivationRaise`, `TrafficLightLayout` | Windows: `HostWindow`, `CraCEFWin.cpp`. Missing: Settings' edge-to-edge pages, Escape leaves video fullscreen (check). Upstream c795319 and 0051bb3 keep a background browser behind the app in use while pages are created or extensions select a tab; Windows needs its own focus regression checks. Sync #23: the Mac engine uses a thin page-host strip instead of an invisible full-size host (#346); Windows keeps CEF child windows. |
| More than one window, window frames saved in `windows.json` | ✅ [#18] | `MainWindowController.swift`, `WindowsMenuRows.swift` | `WindowFrame`, `SpaceWindow`, `NewWindowPlacement`, `PageFullscreenWindow` | `SpaceWindow` picks the window a Little Window's page goes to (#23); `moveTabToSpaceN` still waits for a key. Sync #23: #528 opens a new window from macOS full screen on its own Space; Windows keeps its existing cascade and needs its own full-screen check. Sync #24: new windows open with the sidebar as last hidden or shown (#644, `sidebarVisibleInNewWindows`); ⌘W in video full screen leaves full screen (#636); the Dock menu lists one row per window. |
| Private (incognito) windows | ✅ [#18] | `BrowserManager.swift` | `SidebarStore`, `IncognitoPages` | Upstream c7d26226 (#412): Chrome's Settings and Extensions pages opened from an incognito window go to the normal window (`IncognitoPages`); Windows to check. Sync #26: an incognito window is the incognito of the space it was opened from, with that profile's extensions (#620, `addIncognitoWindow(frame:profileID:)`); Windows still opens Default's off-the-record profile. |
| Blank Window (`newBlankWindow`, "This Window" with a sidebar of its own); a tab dragged out of the window opens in one | ❌ | `AppDelegate.swift`, `MainWindowController.swift`, `SidebarRowViews.swift` | `BlankWindow`, `TabTearOff`, `SidebarStore` (`addBlankWindow`, `moveToBlankWindow`, `isStandalone`) | Upstream #220, #219 (f1d9c56, 9de5a59). The store already saves Blank Windows' spaces outside `spaceOrder`, so Windows needs the window, its header and the drag out of the sidebar (which waits for drag and drop). |
| Toolbar: optional (`toggleToolbar`), host-only address, Show Full URL, reload that turns into stop (`stop`), tab colour, link-copy glyph | ❌ | `PaneToolbarView.swift`, `AppKitControls.swift`, `ToolbarSampler.swift` | `ToolbarComposition`, `ToolbarColor`, `ToolbarExtensionFit`, `ToolbarAutoHide`, `ToolbarKeyboard` | Off by default as on the Mac, so it comes after the sidebar's address pill. Composition and colour decisions are already shared. Upstream 87ab765 and 15c5913 set Arc's 36 pt button pitch and right-end spacing (`ToolbarComposition`). Upstream 167c05a (#405, not in Arc) can float it over the page until the pointer rests at the top. Sync #23: Tab reveals the hidden toolbar for the focused button, and right-click reload opens its menu (#517); Windows toolbar work remains. Sync #24: the toolbar takes the page colour from its top-right corner when a load ends (#629, `ToolbarColor`), and right-clicking a split pane's reload acts on that pane. |
| Sidebar docked on the right | ❌ | `MainWindowController.swift`, `FloatingSidebar.swift`, `TabsPane.swift` | `SidebarSide` | Sync #23, #464: shared geometry mirrors the sidebar and popup side; Windows still docks left and exposes no side setting. |
| Loading bar at the top middle of the window | ✅ [#91] | `LoadingIndicatorView.swift` | `LoadingIndicator`, `LoadingIndicatorPlacement`, `LoadingIndicatorClock` | Windows draws each frame of the Mac's animation (`LoadingIndicator.Clock`: the waiting pill's pulse, its widening, the sweep, the flash) into a click-through layered window owned by the browser window (`CraLoadingBar.cpp`), centred over the page area in the top 10 DIPs. The page is edge to edge on Windows, so the bar lies on the page (ink from its background colour, `lightInk`) or on the developer bar. Tab switches skip the widening and flash as on the Mac. Not yet in Little Windows. Sync #23: shared placement/ink rules keep it at the window's top middle in full-screen, hidden-sidebar and edge-to-edge states (#548). |
| Hide the sidebar (`toggleSidebar`) and the floating sidebar that slides in from the left edge | 🟡 [#80] | `FloatingSidebar.swift`, `FloatingSidebarGeometry.swift` | `FloatingSidebarGeometry`, `SidebarMotion`, `SidebarPresentation`, `FloatingSidebarPointer` (new, the Windows poll's decision), `FloatingSidebarKeepOut`, `SidebarSlidePage` | Windows: Ctrl+S and a sidebar button hide the sidebar (pages go edge to edge) and new windows follow (#644); the window's edge, or a pointer thrown past it, brings the XAML column out over the page after Arc's dwell, and it goes past Arc's slack unless a menu, the Library or a rename holds it (`Browser/FloatingSidebar.swift`, `HostWindow.floatingSidebar`). An empty window holds it out (#483). Left: the reveal spring and shadow (Windows slides on `SidebarMotion` with a rounded region), the Mac's fixed page during the docking slide, Peek's Ctrl+S (#402), full-screen pages. Sync #25: leaving the Library by swipe or ⇧⌘L no longer flashes the floating sidebar under a resting pointer (#635, `FloatingSidebarStillPointer`); Windows' strip still reveals on dwell alone. |
| Drag the window from the top of a page (on by default, as in Arc) | ✅ [#64] | `MainWindowController.swift` | `PageTopDrag` | Upstream 3b6b27d. Windows: CraCEFWin's mouse hook takes a plain press in the page's top 60 DIPs over the arrow pointer (the rule of `PageTopDrag.holds`), gives the page the release past Windows' drag distance and starts the move (WM_NCLBUTTONDOWN with HTCAPTION). Not in HTML fullscreen or the Peek's card; Settings ▸ Advanced switch. |
| Clicks land under the pointer while Chrome's debugger bar shows (#241) | ❌ | `CraCEF.mm` | `PageViewInsets` | Upstream 7675257: the Mac page view moved down by the bar. Check on Windows when extensions that debug pages (#228) run. |
| Find in page with match count | ✅ [#10] | `Overlays.swift` | `FindInPage`, `FindBarPlacement`, `FindCommand` | Upstream 720ede7 (#418) hangs the find bar under an auto-hiding toolbar while it's out (`FindBarPlacement`); Windows has no toolbar yet. Sync #24: `FindCommand` says which find bar a ⌘F reaches (a Little Window's own, #577). |
| Back and Forward history menu: right-click or hold Back or Forward lists the tab's pages (#416) | 🟡 [#66] | `BackForwardMenuView.swift`, `ButtonHold.swift` | `BackForwardMenu` | Upstream c61aab7: rows from DevTools' `Page.getNavigationHistory` and Arc's menu geometry in CraCore. Windows: right-click the sidebar's Back or Forward lists the pages that way (`BackForwardMenu.rows`) in a WinUI menu and goes to the one picked (`Page.navigateToHistoryEntry`). Left: press-and-hold, Arc's own menu look (`BackForwardMenu.Layout`) with favicons, and the Peek bar's buttons. |
| Toasts (copied URL with Share, captures, downloads) | ✅ [#17] | `ShinyToast.swift`, `Overlays.swift` | `ToastStyle`, `ShareRetry`, `ExclusiveAccessNotice` | Windows uses DataTransferManager for Share. `ShareRetry` bounds temporary-busy retries and ends with one failure toast; commands, Site Controls and copied-URL toasts use the same path. The sheet opens with Cra's window in front (a toast's Share button hands the foreground back to its window first), and `ShareRetry.OwnerWatch` re-enables a window a sheet left disabled (gone, or in front but cloaked) and shows the failure toast when no sheet ever showed. A wedged Windows Share (ShellExperienceHost holding a dead sheet) needs a sign-out on the PC; the sheet's own close can't be driven by test input. Sync #24: a click on "New Tab Created" opens that tab (#543); full screen and pointer lock say so as in Arc (`ExclusiveAccessNotice`). |
| Site Control Center, lock badge and certificate viewer | 🟡 [#17] | `SiteControlCenter.swift`, `CertificateWindow.swift` | `SiteControlCenter`, `ConnectionSecurity`, `PageCapture` | Windows shows the sliders in the sidebar's address pill. Its Settings section has the Developer Mode and Block Ads & Trackers switches [#45]. Missing: the protected-media card (Mac only, see Media) and upstream cbb5753's per-site Automatic Picture-In-Picture switch. |
| Zoom (`zoomIn`, `zoomOut`, `resetZoom`), `print`, `viewSource` | ✅ [#58] | `AppDelegate.swift` | `KeyBindingDefaults` | Windows takes Chrome's keys for them (Ctrl+=, Ctrl+-, Ctrl+0, Ctrl+P, Ctrl+U) in its key table, the command bar and Settings ▸ Shortcuts, and zooms in the Mac's half-level steps. Ctrl+Shift+= stays Add Split View. |
| Page context menu: Open Link in New Tab and Open Link in Split View; Alt-click split | 🟡 | `BrowserManager.swift` | `LinkMenu`, `PageMenuLabels`, `LinkSplitClick` | Chromium's menu shows on Windows. Upstream 9630b47, 249adb7 and 8a6c6bf add a split action, one localized Open Link in New Tab item following the foreground setting, and Option-click split (Alt on Windows). Windows: Chrome's Open Link in New Tab, under its own localized label, follows the setting [#48]. Left: Open Link in Split View, Open Link in Little Window, Alt-click split. |
| Arc-style tooltips in the space's tones | ❌ | `ArcTooltip.swift` | `ThemeTones` (`TooltipTones`) | Windows uses plain WinUI tooltips. |
| Theme, metrics and the brand mark | 🟡 | `Theme.swift`, `ThemeNoise.swift`, `Tuning.swift`, `BrandMark.swift` | `SpaceTheme`, `ThemeTones`, `ArcMenuTones`, `SidebarTones`, `CardFill`, `CardVeil` | Sidebar palette from `SpaceTheme` is shared; Windows has its own metrics. Upstream's Arc menu, sidebar hover and card-fill policies are available but not all used by the Windows controls. Brand mark from `brand/`. Sync #23: Arc's muted palette, Light material and no-tab/empty-pane white veil are shared decisions; Windows has not adopted those refinements (#455, #490). |
| Sidebar blur, Reduce transparency, active/inactive look | ❌ | `ActiveAppearanceProbe.swift` | `SidebarBackdrop` | Windows counterpart: Mica or Acrylic, and Windows' transparency setting. Since f6b9fb6 a full-screen window keeps its active look while its Space slides away (AppKit's own answer, `windowActive(activeAppearance:)`). |
| Only one Cra running (an older copy quits) | ➖ | `NewestCopy.swift` | | Windows: a single-instance mutex when the installer lands. |
| Arc's dialog sheet for every confirmation: one card, its buttons, keys and hover | ❌ | `AppDialog.swift`, `DialogComponents.swift`, `Colors.swift`, `DialogClick.swift` | `DialogActions` | Upstream bc47470 (#224). Windows asks with WinUI flyouts and dialogs; `DialogActions` (which button Return and Escape press) is shared for the Windows card. `Colors.swift` is SwiftUI's hex colours. Sync #23: updater warning buttons reach their own window; Windows confirmations remain separate. |
| Stay On Top (`stayOnTop`), Save Page As (`savePageAs`), Copy URL as Quote (`copyURLQuote`), Copy URL without trackers, Paste and Go (`pasteAndGo`) | 🟡 [#52] [#83] | `MainWindowController.swift`, `AppDelegate.swift` | `CleanURL`, `SavePage`, `PasteAndGo` | Upstream d110dc6. Windows: Copy URL and Copy URL as Markdown leave trackers out (`CleanURL`), Copy URL as Quote copies the selection with a text-fragment link, Stay On Top keeps the window (or a Little Window) above other apps' (`HWND_TOPMOST`); both from the command bar, no keys (the Mac's ⌃⇧⌘C has no free Windows counterpart). Save Page As (Ctrl+Shift+S, the Mac's ⇧⌘S; Ctrl+S stays free for Hide Sidebar as in Arc for Windows) offers Chrome's Web Page, Single File (MHTML) and HTML Only in Windows' Save dialog, in Downloads; a typed `.html` or `.mhtml` decides the format (`SavePage`). Browser windows, Little Windows and the Peek. Left: upstream cd8f3f5's copy of every selected sidebar tab's URL, which needs multi-selection. Sync #26: Edit ▸ Paste and Go ⌥⌘V opens the copied link as a new tab or searches the copied text (#610, `PasteAndGo`); Windows has no key or command for it yet. |
| Find ▸ Use Selection to Find (`useSelectionForFind`), Jump to Selection (`jumpToSelection`) | ✅ [#83] | `MainWindowController.swift` | `FindInPage`, `FindSelection` | Upstream 894f1f6. Windows has no menu bar, so both are in the command bar (`KeyBindingDefaults.windowsCommandBarAdds`) with no default keys: the Mac's ⌘E and ⌘J are Open Extensions and Downloads (Ctrl+E, Ctrl+J) here; Settings ▸ Shortcuts can give them one. Use Selection puts the page's selection in the find bar and searches it; Jump to Selection scrolls it to the middle (also in a Little Window, which has no find bar). |
| What websites see: View ▸ Appearance (`appearanceAutomatic`, `appearanceLight`, `appearanceDark`), sound effects, "Allow websites to get your theme data" | 🟡 [#62] | `AppDelegate.swift`, `BrowserManager.swift`, `AdvancedPane.swift`, `CraCEF.mm` | `SidebarModel` (`WebsiteAppearance`), `ArcThemeData`, `ThemeTones`, `SidebarStore` (`themeDataCSS`) | Upstream 35bc84a, bfd9962. Windows has View ▸ Appearance as commands: every profile's CEF colour scheme follows it, and Light or Dark turn Settings and the Site Control Center too. Left: sound effects and the theme data `:root` style injection. |
| "When opening Cra, restore windows from previous session" and "start on a new tab" | ✅ [#59] | `AppDelegate.swift`, `AdvancedPane.swift` | `SidebarModel` (`restoreWindows`), `SidebarStore`, `LaunchStart` | Upstream 337d5f8 and 7c98d46. Windows: Settings ▸ Advanced ▸ Opening and quitting has both switches. Off, only the window in use last comes back (`keepOnlyActiveWindow`); on a new tab, the window opens with no tab selected and the command bar making one, unless another app started Cra for a link. A link arriving later closes that bar. |
| Slow first response: after 10 seconds, a waiting-page toast with Stop Loading | ✅ [#57] | `BrowserManager.swift`, `ShinyToast.swift` | `SlowResponseNotice`, `SlowResponseNotices` | Upstream 001afb2. Browser windows and Little Windows; the bridge reports commits and navigation starts, the toast stays with a ✕. PC fixes [#77](https://github.com/vishnu597/cra-windows/pull/77): every visible split pane can show its own due notice, with the toast anchored to that pane and Stop Loading targeting it; five clock tests cover selection/deadlines. The 19 Nov native check showed a notice on an unfocused split pane; Stop removed it without changing the loaded pane. The exact 10-second threshold was not timed. |
| View Source in Cra (`viewSource`, Ctrl+U and the page/frame menu) | 🟡 | `SiteData.swift`, `PageCommands.swift` | `ViewSource` | PC-test follow-up replaces CEF's temporary text-file/Windows Open With path with the shared view-source address and foreground page routing. Main/private windows open a tab, a Little Window opens another Little Window in its profile, and a Peek opens a parent-window tab, matching the Mac. The 19 Nov native check passed main-window Ctrl+U, frame-menu source and Little Window Ctrl+U, each rendering HTML inside Cra. Private and Peek variants remain on the release checklist. |
| Translate a page, Translation Available affordance and Arc's translate popover | ❌ | `BrowserManager+Translation.swift`, `TranslatePopover.swift`, `PaneToolbarView.swift` | `PageTranslation` | Upstream 386fbf8. Requires the translate CEF bridge/patch (`translate-ui.patch`) and native Windows popover; stock CEF alone does not provide Cra's state callback. |

## Sidebar

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Spaces: switch, create, delete, the space dock | 🟡 [#5] | `SidebarView.swift`, `SidebarRootView.swift`, `SpaceDock.swift`, `SpaceListView.swift`, `SpaceColumnView.swift`, `SidebarUIState.swift`, `EmojiLabelFrame.swift`, `SpaceCreationView.swift`, `NewSpacePlusView.swift` | `SidebarStore`, `SidebarModel`, `ItemTable`, `SidebarIntegrity`, `SpaceDock`, `ListKnobGate`, `SpaceCreation`, `SpaceStyleControls`, `NewSpaceSwipe` | Same `sidebar.json` as the Mac. Windows [#85](https://github.com/vishnu597/cra-windows/pull/85) draws the dock from `SpaceDock` (`Sidebar/SidebarDock.swift`): an even share of the room between the Library and + buttons up to 34 DIPs, Arc's 8 DIP dot for a space with no icon, the squeezed dock of 4 DIP dots with the open space (or the hovered one, #252) in the 22 DIP wide cell, faint unlit icons, symbols (where Segoe Fluent has one) and picture icons, + at the right end. Not yet: the 0.2 s slide and cross-fade, the unlit icons' desaturation. Sync #23: the Mac list scroller stops blinking between flicks (#544); Windows uses WinUI scrolling. Sync #24: New Space is Arc's Create a Space page in the sidebar (#576, `SidebarStore.isMakingSpace`), and a swipe past the last space brings out Arc's "+" (#564). Windows still creates a space at once. |
| Go to Space N (`spaceN`) on Alt+1–9, next and previous space on Ctrl+Alt+Right and Left | ✅ [#5] [#21] | `MainWindowController.swift`, `AppDelegate.swift` | `KeyBindingDefaults`, `SidebarStore` (`focusSpace(number:)`) | Arc for Windows' keys: Ctrl+1–9 stays Go to Tab, as in Chrome. |
| Move Tab to Space N (`moveTabToSpaceN`) | ✅ [#53] | `MainWindowController.swift`, `AppDelegate.swift` | `SpaceWindow`, `SidebarStore` | Windows' key is Alt+Shift+1–9 (Go to Space N's Alt+N with Shift, where the Mac adds ⌘ to ⌃N; Ctrl+Alt would be AltGr). The open tab, or its split, moves and the window follows it (`moveTabAndFollow`); a Little Window sends its page there. An incognito window's tabs stay put. |
| Swipe, Shift + wheel or sideways wheel between spaces | 🟡 [#85](https://github.com/vishnu597/cra-windows/pull/85) | `SpacePagerView.swift` | `WheelSpaceSwitch`, `PageDetentHaptics` | Windows [#85](https://github.com/vishnu597/cra-windows/pull/85): Shift + wheel or a sideways wheel over the sidebar switches spaces through `WheelSpaceSwitch` (one notch is one line, `lines(windowsDelta:horizontal:)`: a slow notch does nothing, a flick switches). Left: the slide between spaces, a precision touchpad's two-finger swipe, the Library as the page before the first space. Upstream c4ee4dc adds one trackpad haptic per changed page, including a flick; hardware feedback needs a Windows counterpart if supported. |
| Pinned tabs and folders, Today, Clear Today, archive on close | ✅ [#5] [#61] | `SidebarRowViews.swift`, `SidebarItemView.swift` | `SidebarStore`, `CloseSuccessor`, `SidebarClose`, `PinnedPeek`, `TodayClear` | `clearToday` (Ctrl+Shift+K, the Mac's ⇧⌘K) and `newFolder` are in the sidebar menus and the command bar [#61]; Clear keeps the tab on screen (upstream f586c7f, #406), but Windows doesn't know which tabs play sound yet, so those are archived; `SidebarClose` (Arc's close buttons per row kind) isn't used on Windows yet. |
| Pinned tab extras: back to its page by the favicon, the slash, Reset (`resetTab`), edit URL | 🟡 [#60] | `EditPinnedURLDialog.swift`, `SidebarRowViews.swift` | `PinnedNavigation` | Since 6e371cc "Back to Pinned URL" slides in under the title on hovering the icon (0.16 s). Windows [#60]: Back to Pinned Page on the tab menu of a pinned tab away from its page and in the command bar (`resetTab`). Windows [#68]: a click on its favicon goes back, Ctrl-click separates the page into a Today tab (`SidebarStore+PinnedSeparate`), a double-click there goes back once and doesn't rename (`PinnedIconClick`, 3d6548c). Left: the slash and hover slide, Edit Pinned URL…. |
| Restore Last Closed Tab (`reopenClosedTab`): a closed pinned tab comes back at the page it was on, archived tabs and a closed Peek in order; optionally only from the current space (#566, #601) | ✅ [#24] [#79] | `AppDelegate.swift`, `TabsPane.swift` | `ReopenClosedTab`, `SidebarStore` (`closePinnedTab`, `closeSuccessor`, `reopenLastClosed`) | Windows [#79]: Ctrl+Shift+T calls `reopenLastClosed(in:peek:)` with the window's closed Peek; closing an open pinned tab records it (`closePinnedTab`) and shows `closeSuccessor`, as on the Mac. Settings ▸ Tabs has "Reopen tabs from this Space only". |
| Folders: hinge animation, hover previews with search, tabs shown under a closed folder, icon picker | 🟡 | `FolderPreview.swift`, `FolderGlyphView.swift`, `FolderIconPicker.swift`, `FolderSymbolImages.swift` | `FolderPeek`, `FolderSymbol`, `FolderPreviewRows` | Windows has folders without previews or the animation. Since upstream 11ff4c9 (#234) the folder's emblem follows its front panel's perspective; 4fc05d2 adds Arc's picker and native symbol-mask rendering, still missing on Windows. Sync #23: closed folders keep their retained tab, and preview hover follows exactly one visible row while scrolling (#544, #557); Windows needs those paths. |
| Favorites | 🟡 [#5] [#82] | `SidebarRowViews.swift`, `TileColor.swift` | `FavoritesLayout`, `FavoritesSharing`, `FavoriteClick`, `FavoriteTileColors`, `FavoriteSelectionTint`, `FavoriteOutlineColors` | Windows [#82]: Arc's 4/2/1 columns by width with 47 DIP tiles 8 apart (`FavoritesLayout`, the drop slot too), Tile Color ▸ on a favorite's menu (Default, the presets, Custom, Use This Color for All Favorites; `FavoriteTileColors`, which the Mac's `TileColor` now reads) filling the tile with its shade while open and the icon in the tile's tone, a double-click going back to the pinned page (`FavoriteClick`, a17a8fe), and Settings ▸ Tabs ▸ Share Favorites across Spaces. The "Drag to add Favorites" card shows while dragging [#71]. Missing: Other Color… (a colour picker), Change Icon…/Use Site Icon, the hover fill, and the opt-in logo-coloured outline/Arc hover fills (86dbb44, 9927600). |
| Drag and drop: reorder, into folders and favorites, onto a space's icon, several picked tabs at once, reorder spaces, a link dropped in from a page or another app (#419) | 🟡 [#71](https://github.com/vishnu597/cra-windows/pull/71) | `SidebarListDrop.swift`, `SpaceListView.swift`, `SpaceListView+Drop.swift` | `SidebarStore`, `SidebarLinkDrop`, `SidebarDropPlan`, `SidebarEdgeDrag`, `SidebarChildOrder` | Windows (`Sidebar/SidebarDrag.swift`): a row, favorite tile or space icon dragged past Windows' drag distance moves before or after a row (top and bottom quarters), into a folder (its middle, or first inside an open folder's bottom), makes a split with a tab (its middle, on the side the pointer is on; on a pinned tab a pinned split), joins a split row, crosses between pinned and Today, takes a slot among the favorites (or the "Add to Favorites" card when there are none), moves to another space by its icon (which comes forward after 0.5 s), and space icons reorder along the dock. Arc's insertion ring and line, the combine's outline and dashed pane, the list scrolling near its edges, Escape to cancel. The decisions are `SidebarDropPlan` (the Mac's `SpaceListView.resolve` and `applyDrop`). A link dragged in from a page or another app (XAML's OLE drop on the sidebar: WebLink, UniformResourceLocatorW or text) opens where it is let go, behind the open page, or first in a folder let go on [#73](https://github.com/vishnu597/cra-windows/pull/73). Left: several picked tabs (Windows has no multi-select yet), drags between windows and tearing a tab out (Blank Window). Since 1f3c3d3 a tab dropped on any tab, pinned too, offers a split (no folder drop); since dfa3358 rows keep their hover through AppKit's stray exits (Mac only). Sync #23: the Mac changes space when a dragged tab rests at the sidebar edge (#499); Windows currently uses dock-icon hover. PC fixes [#77](https://github.com/vishnu597/cra-windows/pull/77) move the empty-favorites target into the overlay, preserving every row position; the final release point is hit-tested again before the drop. The owner confirmed with a real mouse that the Favorites target did not shift rows and the drop landed where indicated; broader folder/favorite/cancel variants remain on the release checklist. Sync #24: a tab dropped on a pane of a full split replaces it (#419, `addToSplit(replacing:)`). |
| Space menu: rename, icon, theme, profile, folder, export, delete | 🟡 [#5] [#19] | `MainWindowController+SpaceMenu.swift`, `EmojiLabel.swift`, `SidebarMenus.swift`, `SpaceIconPicker.swift`, `EmojiCatalog.swift`, `EmojiCatalog+Data.swift`, `SpaceIconImage.swift` | `SpaceProfiles`, `SpaceIcon` | Since upstream 8f511ac (#205) a space's icon can be a symbol (`Space.symbol`, `SpaceIcon`); Windows draws the emoji only. Upstream 0b20792 (#395) adds a PNG or SVG as an icon (`Space.iconImage`); Windows shows the emoji. Windows has Rename Space… (and a double-click on the name, `SidebarStore+Rename`'s `renameSpace`, [#44]), New Folder, New Space, Clear Today, Hide Space Header, Set Profile, Delete. `newSpace` is a command too [#61]. Missing `editSpace` (no editor yet) and `deleteSpace` (waits for a confirmation card) as commands, the emoji picker. `EmojiCatalog+Data.swift` has no imports: move it to CraCore for the Windows picker. |
| Space theme editor: Arc's presets, light and dark halves, grain | ❌ | `SpaceStyleEditor.swift`, `SpaceEditorView.swift` | `SpaceTheme`, `SpaceThemeVariants`, `SpaceColorPresets`, `ArcThemeImport` | Windows draws themes it reads; editing is missing. The colour logic is all shared. Since 6e371cc swatches and knobs grow under the pointer and shrink when pressed. Sync #25: two or three colours are see-through at the slider's intensity (#596, #643). |
| Manage Spaces page (`manageSpaces`) | 🟡 [#70] | `SpacesManagerView.swift` | `SidebarStore`, `SpacesManagerLayout`, `LibraryWidth` | Windows [#70]: the Library's Spaces page (rail, the space menu's Manage Spaces… and the command): a card per space in its colours with its pinned and Today tabs (a click opens the tab), the move handle to drag a card along the row (Move Left and Move Right in its ⋯ menu too), Open Space, Clear Today, Delete Space, and the + for a new space; the Library widens to fit the cards and leaves the page 56 DIPs. Not yet: Edit Theme Color… (no editor on Windows), the card's full space menu, the page keeping its width past the window's edge (`LibraryWidth.page`), the cards' grain; the Mac still has its own `SpacesManagerMetrics` (move it onto `SpacesManagerLayout` with the next Mac change). PC fixes [#77](https://github.com/vishnu597/cra-windows/pull/77) use fixed-root pointer coordinates plus scroll offset, clamp movement to real card positions and sample the release. Render-input caching and an interaction hold preserve drag/menu anchors; the options button uses release-mode flyout handling. Capture loss and Escape cancel the drag. Native checks passed left-click options, Move Right and one-slot grip drags before and after horizontal scrolling; the saved model showed the expected order. Pause/continue, capture-loss/cancel and second-scale variants remain on the release checklist. |
| Space tooltip with its profile and keys | 🟡 [#85](https://github.com/vishnu597/cra-windows/pull/85) | `SpaceDock.swift`, `ArcTooltip.swift` | `ThemeTones`, `SpaceDock` (`tip`) | Windows [#85](https://github.com/vishnu597/cra-windows/pull/85): a XAML tooltip with the space's name, its profile in a pill ("Default" without one) and Go to Space N's keys for the first nine. Left: Arc's tooltip look and its 0.55 s delay (`ArcTooltip.swift`). |
| Jump pill back to the open tab | ❌ | `SidebarJumpPill.swift` | | |
| Rename (`renameTab`), duplicate (`duplicateTab`), Add to Favorites (`favoriteTab`) as commands | ✅ [#44] | `SidebarMenus.swift` | `SidebarStore`, `KeyBindingDefaults`, `SidebarClick` | Windows: Rename… on a tab or folder row (and a double-click) turns its name into a field (Return keeps it, Escape doesn't); a new folder starts named. All three are commands with no default key, as on the Mac. PC fixes [#77](https://github.com/vishnu597/cra-windows/pull/77) use `SidebarClick` to pair real presses by model identity across row redraws. Time/distance/modifier bounds come from Windows; drag and keyboard actions cancel a pair, and `PinnedIconClick` still suppresses rename after going home. The owner confirmed real-mouse rename on an unselected tab, a closed folder and a space name (#424 on the Mac). Sync #24: Duplicate leaves the copy in the background, saved read; a favorite's copy is a Today tab and a split can be duplicated (#600). Windows gets this through the shared store. |
| Arc's other sidebar actions: Collapse Pinned Tabs (`collapsePinned`), Collapse and Expand All Folders (`collapseAllFolders`, `expandAllFolders`), Reveal Tab in Sidebar (`revealTab`), Reset all tabs in this Space (`resetSpaceTabs`), Archive Tabs Below, Change Icon…, Share ▸ | 🟡 [#50] [#60] | `SidebarMenus.swift`, `MainWindowController.swift`, `SiteControlCenter.swift` | `SidebarStore` (`setAllFoldersExpanded`, `revealInSidebar`, `archiveTabsBelow`) | Upstream d110dc6, 6f3f298. The store side is shared. Windows [#50]: Collapse Pinned Tabs, Collapse and Expand All Folders and Reveal Tab in Sidebar in the command bar (no keys: the Mac's ⌃Space is Ctrl+Space, an input method switch, on Windows; Reveal doesn't scroll the sidebar yet), Archive Tabs Below on a Today tab's menu. Reset all tabs in this Space (`resetSpaceTabs`) from the command bar [#60]. Left: Change Icon…, Share ▸. |
| Unread dots and theme colours | ✅ [#5] | `SidebarRowViews.swift` | `SidebarModel` | |
| Tab row on hover: the name runs to 13 pt before the close button (#243) | ❌ | `SidebarRowViews.swift` | `TabRowTrailing` | Upstream 12ab4cf. Windows' row keeps a fixed gap; use `TabRowTrailing`'s insets. |
| Mouse back and forward buttons over the sidebar switch spaces (#233) | ✅ [#47] | `SidebarView.swift` | `MouseButtonSpaceSwitch` | Upstream 2b95100. Windows: WinUI's XButton1/XButton2 release over the sidebar (`buttonNumber(windowsXButton:)`); over a page they stay Chromium's. Logi Options+'s Alt+arrow and swipe paths are Mac only. |
| Favorite previews on hover: a Gmail favorite's unread mail, a Google Calendar favorite's Live Calendar, Join Meeting (`joinNextMeeting`, ⌃⌘J) | ❌ | `FavoritePreviewCard.swift`, `LiveCalendarClient.swift` | `GmailPreview`, `CalendarPreview`, `FavoritePreviewMetrics` | Upstream 06366ad, 874e1ca, 32caaf8. Windows needs the hover card over the favorites row and the same signed-in page reads. |
| Download location per profile: a folder, or ask where to save each file (Settings ▸ Profiles) | ✅ [#84] | `DownloadDestinations.swift`, `ProfilesPane.swift` | `DownloadLocation` | Upstream ef42649. `DownloadLocation`'s decoder keeps Windows drive and share folders (`C:\…`, `\\server\share`) as well as "/" paths (`isAbsolute`). Windows: each profile's row in Settings ▸ Profiles has the Mac's pop-up (the folder, Other… with Windows' folder picker, Ask Where to Save Each File); the bridge saves each profile's downloads there (`DownloadLocation.bridgeLines`, `cra_cef_set_download_locations`), falling back to Downloads when the folder is gone, and asking opens Windows' Save dialog there. Private windows follow Default; the Library's Open Downloads Folder opens the focused space's profile's folder. |
| Downloads list in the footer, thumbnails, no Chrome download arrow | 🟡 [#10] [#12] | `DownloadsTray.swift`, `DownloadThumbnails.swift`, `ChromeDownloadAnimation.swift`, `DownloadProgressBadge.swift`, `DownloadRowMenu.swift`, `DownloadHistory.swift` | `DownloadHistory`, `DownloadRow`, `DownloadMenu`, `RelativeTime`, `DownloadsTrayHover` | `viewDownloads` is Ctrl+J (Chrome's Downloads key): the Library's Downloads page (#27), with Open, Show in Folder and Open Downloads Folder. Windows [#94]: Arc's row menu in the list and on Library ▸ Downloads (`DownloadMenu`, in Windows' words with `DownloadMenu.windowsTitle` and kinds from the extension, `DownloadMenu.Kind.of(fileName:)`): Pause, Resume and Cancel while a download runs (CEF's download callbacks, `cra_cef_control_download`, the paused state reported back), Open, Copy (the file, CF_HDROP), Show in Folder, Hide from Cra and Move to Recycle Bin once done. Missing: the flight into the bin (`DownloadFlight.swift`), the progress ring on the bin and confirmation before quitting with downloads running. Sync #23: transient/Web Store CRX downloads stay out of Mac engine guards/history (#491, #496, #519). The fork keeps `DownloadHistory` in CraCore; Windows callback/guard integration still needs testing. Sync #24: the list stays open on the way up from the Library button (#575). |
| Download flight into the Library button | ❌ | `DownloadFlight.swift` | | |
| Favicons in rows, tiles and the command bar | 🟡 [#12] | `FaviconCache.swift`, `TabIconPicker.swift` | `FaviconKey`, `TabCustomIcon` | Since upstream 061a0ef (#211) and f6c91a3 (#291), each tab's icon, including a data: icon, persists across relaunch (`FaviconKey`, `SidebarStore.setFaviconKey`). Windows still keeps one icon a site. Sync #26: Change Icon… on a favorite or tab opens Arc's Emoji | Icon picker (#640, `TabCustomIcon`, `TabIconPicker.swift`); Windows has no Change Icon yet. |
| Live folder plugins: built-in GitHub, GitLab and Jira, installed JavaScript providers | ❌ | `LiveFolderManager.swift`, `LiveFolderPluginStore.swift`, `LiveFolderViews.swift`, `PluginsPane.swift` | `LiveFolderModel`, `GitLabLiveClient` (legacy model), `LiveFolderPlugin`, `LiveFolderPluginArchive`, `LiveFolderPluginConfiguration`, `LiveFolderPluginOutput`, `LiveFolderPluginPackage`, `LiveFolderPluginProcess` | Upstream 664cc6a replaces the native GitHub/GitLab clients with bundled JavaScript providers and a package/permission flow (Settings ▸ `plugins`); b08beb3 fixes bundled paths under /private. `GitHubLiveClient.swift` was deleted upstream. Windows needs the runtime, exact-origin session reads, package settings and native live rows. Pure manifest/ZIP/output validation is portable; operational ZIP extraction and plugin process invocation explicitly report unsupported on Windows until its installer/runtime is implemented. Preserve old folder data. |
| Sidebar width, drag-to-hide, snap and narrow header | ❌ | `SidebarView.swift`, `SidebarMorePanel.swift` | `SidebarWidth`, `SidebarResize`, `SidebarHeaderLayout` | Upstream 46cfb2a and 06d5380: 164–500 pt, snap to 228, drag shut below 82, compact navigation below 212. Windows' fixed sidebar needs the resize input, saved width and narrow header; use these policies rather than duplicate thresholds. |
| Sidebar + creation menu and More options in the space's palette | ❌ | `SidebarCreationMenu.swift`, `SidebarMorePanel.swift` | `ArcMenuTones`, `SidebarTones` | Upstream 895b0c5 and 86dbb44. Windows' footer + creates a space directly; it does not yet show Arc's creation menu or the +/× transition. |
| Floating music notes on a playing favorite | ❌ | `MusicNotesView.swift`, `SidebarRowViews.swift` | `MusicNotes` | Upstream e1c8765. Shared note paths/timing are available; Windows needs audio state and the favorite overlay. |

## Command bar and shortcuts

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Command bar: tabs, archive, history, domains, actions, inline completion, ⌘Return background tab, Tab on the empty field lists actions (#195) | 🟡 [#8] [#9] [#24] | `CommandBarController.swift`, `CommandBarView.swift`, `CommandTextField.swift`, `SearchSuggestLoader.swift` | `SuggestionEngine`, `CommandBarDedupe`, `CommandBarGlyph`, `TypedURL`, `RelativeTime`, `ActionSearchScope`, `CommandBarTones`, `CommandBarClosing`, `CommandBarRanking`, `CommandBarScore`, `CommandBarProfileScope`, `SidebarAddressPanel` | Windows has the shared ranking and actions scope. `WinSuggestLoader` repeats the Mac's loader on FoundationNetworking; move it to CraCore. Missing: upstream 3bd548d's Arc sizing/row and badge tones, the theme glow and scope bounce, Alt+Return split, `checkForUpdates`, and cab6d40's current-space-only setting. Upstream 609bc7f (#429): another window keeps the keys it took from the closing bar (`CommandBarClosing`). Sync #23: closing the bar with ⌘W, search text beyond completion or ending in digits, and query persistence across app switches are corrected (#497, #513, #546, #551). Shared parsing/closing updates arrive; Windows activation remains a separate check. Sync #24: the bar's index is built as it opens and scored on bytes (#617), and searches the whole archive (#614). Windows shares `SuggestionEngine`; `prepareIndex()` isn't called there yet. A typed app address (todoist://) opens its app (#604). Sync #25: a space suggests archived tabs and visited pages from its own profile only (#609, `CommandBarProfileScope` in the shared `SuggestionEngine`); Windows passes each visit's profile, so it gets this too. Sync #26: a click on the sidebar's address opens Arc's address panel hanging from it, as wide as the address (#663, `SidebarAddressPanel`); Windows still opens the centred bar. |
| Spaces menu: existing spaces with names and icons | ❌ | `SpacesMenu.swift`, `SpaceMenuTitle.swift` | `SpacesMenuComposition` | Sync #23, #481: the Mac native menu omits nonexistent slots; Windows has Alt+1–9 and dock buttons, with no native Spaces menu. |
| Search suggestions, Site Search with Tab, % tab search, Chromium's engines | 🟡 [#9] [#13] | `SearchEngines.swift` | `SearchSuggestions`, `SiteSearch`, `TabSearchScope`, `ScopedSearchFill` | Windows reads Cra's engine setting; the Mac also reads Chromium's engine list (SQLite). Upstream d55e7a0 adds a search engine per space and cab6d40 can restrict tab results to that space; the Windows caller must use the shared engine/scope decisions. Sync #23: Tab fills the site-search scope with the site's color (#457); Windows does not draw that fill. |
| Shortcuts in `keybindings.json`, Settings ▸ Shortcuts | ✅ [#15] | `KeyBindings.swift`, `ShortcutsPane.swift`, `KeyboardLayoutCharacters.swift` | `KeyBindingDefaults`, `KeyBindingRegistry`, `KeyChord`, `KeyChord+Windows` | Since upstream 370ca1a (#212) the Mac matches by the character the layout types and falls back to the key's ANSI place (`KeyChord.match`); Windows matches virtual keys, which already follow the layout. Windows' table is `KeyBindingDefaults.windowsShortcuts`; a command joins it when Windows performs it (`parity.py report` lists the rest, each named in its feature's row). |
| Who gets a shortcut's keys while a page wants them: Prefer Cra, Use Both, Prefer Websites (#374); search by keys | ❌ | `ShortcutsPane.swift`, `AppDelegate.swift`, `CraCEF.mm` | `ShortcutPriority`, `ShortcutSearch`, `KeyBindingRegistry` | Upstream 115e806. keybindings.json carries each action's priority on its chords (`KeyBindingOverrides`), and Windows' registry reads and keeps it already; Windows still takes its keys at one point (before the page) and has no pop-up for it. |
| Help menu: Essential Keyboard Shortcuts card (`essentialShortcuts`), Reveal Cra Data (`revealData`), Copy Cra Info (`copyAppInfo`), Open Task Manager (`taskManager`), Cast… (`cast`) | 🟡 [#63] | `EssentialShortcutsWindow.swift`, `AppDelegate.swift` | `KeyBindingDefaults`, `CraInfo` | Upstream a6b5d41, d729895, d110dc6. Windows runs Reveal Cra Data (Explorer on the data folder) and Copy Cra Info (Cra, engine and Windows version, `CraInfo`, which the Mac reads too) from the command bar. Left: the shortcuts card, Task Manager and Cast (Chrome's own). |
| Recent-tab switcher on ⌃Tab (`recentTab`, `recentTabBackward`) | 🟡 [#72] | `TabSwitcher.swift`, `TabSwitcherView.swift` | `SidebarStore`, `TabSwitcherCycle`, `TabSwitcherLayout`, `RecentTabOrder`, `SwitcherSplitLayout` | Windows [#72]: Ctrl+Tab / Ctrl+Shift+Tab open Arc's card panel over the space's recent tabs (`SidebarStore.recentTabs`, upstream 5a93a4c's order); letting go of Ctrl, Return or a click switches, Escape cancels, a quick tap switches without showing it. Sidebar order moved to Ctrl+PgDn / Ctrl+PgUp, Chrome for Windows' other keys. Left: page pictures on the cards (Windows shows Arc's empty card), the panel's 26 pt corners and shadow (Windows 11 rounds the window by 8). The Mac's TabSwitcherMetrics and card highlight now read `TabSwitcherLayout` and `SpaceTheme.switcherHighlightRGBA`. Sync #23: recent order groups a split into one card (#554); Windows still needs its grouped card. `recentTabAllSpaces` and `recentTabAllSpacesBackward` add Mac ⌃⌥Tab (#467), with no Windows default. Ctrl+Escape is reserved by Windows and is not a valid cancellation-test chord. |
| Context menus show shortcut glyphs | 🟡 | `SidebarMenus.swift` | `KeyBindings` | WinUI menu items take KeyboardAcceleratorTextOverride. |
| Command bar's search-suggestions notice | ❌ | `CommandBarController.swift`, `CommandBarView.swift` | `SearchSuggestionsNotice`, `CommandBarTones` | Upstream 50d2fa9 then 0c81531: Arc's (i) opens the search-engine privacy notice, not Site Control Center; Dismiss persists. Windows needs the badge, banner and Search Settings action. Sync #25: in Dark mode the bar is see-through like Arc's (#502, `CommandBarTones`); Windows' bar is its own window. |
| File menu's Arc sections, Share… (`share`) and New Profile (`newProfile`) | 🟡 | `AppDelegate.swift` | `FileMenu` | Upstream 7f5759f. Sync #8 exposes the existing Windows profile/share capabilities as commands. The Windows shell still has no native File menu built from `FileMenu.sections`. |

## Split view

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Up to four panes, dragger, add, close, separate, flip, cycle, split menu | ✅ [#11] | `PaneCardView.swift`, `SplitDraggerHandleView.swift`, `SplitPaneLayout.swift` | `SplitPaneLayout`, `SplitPaneLimit` | Sync #23: four stays the default; Links settings can allow eight and middle-click can add a pane (#498). The shared store enforces the limit; Windows has no Links switch/middle-click path, and imported eight-pane settings need layout testing. |
| Pane controls on focus and hover, focus ring, rename a split, pinned and favorite splits | 🟡 | `PaneCardView.swift`, `SidebarRowViews.swift` | `SidebarStore` | Windows has the layout and the menu; the per-pane bar, ring and rename are missing. |
| Switch to Split View 1–4 (`splitPaneN`), Open in Split View and Add Split View on the tab menu, a tab dropped on a pinned tab makes a pinned split (#180) | 🟡 [#49] | `MainWindowController.swift`, `SidebarMenus.swift` | `SidebarStore` (`createSplit(inPlace:)`, `combineIntoSplit`, `canAddPane`, `joinSplit`), `SplitPanePick` | Upstream 56a5232, b2955ba. Windows: the tab menu's Add Split View and Open in Split View [#49]. Left: Switch to Split View 1–4, which need Windows keys (the Mac's ⌃⇧2 would be Ctrl+Shift+2, Capture, on Windows) and aren't in the command bar; a tab dropped on a tab's middle in the sidebar makes a split there, a pinned one on a pinned tab [#71](https://github.com/vishnu597/cra-windows/pull/71). Sync #25: an open tab picked for Add Split View's new pane comes into the split instead of switching to it (#645, `SplitPanePick`). |
| Expand Current Split (`expandSplitPane`): the focused pane takes the window, the others keep Arc's 220 pt minimum | ✅ [#49] | `MainWindowController.swift`, `SplitPaneTransition.swift` | `SplitPaneLayout` | Upstream 9629fd1. `SplitPaneLayout.expanding` and the 220 pt minimum are shared and lay Windows' panes out; Windows runs it from the command bar, with no key, as on the Mac. |
| Drag a sidebar tab or a page's link onto the page to split it, on the side it's let go (#419) | 🟡 [#73](https://github.com/vishnu597/cra-windows/pull/73) | `PageDropRouter.swift`, `PageSplitDrop.swift`, `SplitDropRegionView.swift` | `SplitDropProposal`, `SplitDrop` | Upstream 60cf686, 2908a25. Windows: a sidebar tab dragged off the sidebar over the panes asks `SplitDropProposal` (in DIPs, y up) and tints the region a new pane would take, or the pane a drop would replace, with an owned see-through window (`CraOverlay`); letting go makes the split (`SplitDrop.drop`, the Mac's `PageSplitDrop.drop`). The press opens the dragged tab, so over a lone page Arc's swap shows the tab from before the press again (`SplitDrop.showing`). Left: a page's link dropped on a pane's edge (Chromium's own drop target takes drags over the page), the panes making room for the region as it opens, Arc's dark card as the drag image. |

## Little Windows, Peek and the Library

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Little Windows (`newLittleWindow`, `promoteLittleWindow`, `closeLittleWindows`), profile chip, ⌥⌘N from any app | 🟡 [#23] | `LittleWindowController.swift`, `GlobalHotkey.swift`, `LittleFindBar.swift`, `WindowSpaces.swift` | `LittleWindowLayout`, `SpaceWindow`, `GlobalShortcut`, `LittleWindowTarget`, `LittleMoveMenu`, `LittleWindowReturn`, `LittleStripTones`, `LittleBarRows`, `LittleWindowLinks`, `LittleWindowRaise`, `LittleWindowActivation` | Windows: Ctrl+Alt+N (also from any app, RegisterHotKey, skipped where AltGr+N types a letter), Ctrl+O; strip, Open in Space menu, profile chip, command bar, size/cascade and archive on close. The live page moves into the browser window (`cra_browser_set_parent`). Left: upstream 2bf4f8f's searchable 46 pt rows, scrolling and hidden chevron with one space; the grow animation; "Don't ask again"; `littleWindowOpenInMenu`; archive after 1/6/12 hours (`LittleWindowArchive`). Upstream c247e40 and 4e5ce86 make a picked space stay in that Little Window only, while the next follows the browser used last; use `LittleWindowTarget` for that policy. Upstream 0ab17c2 (#430): closing a Little Window goes back to the app it was opened over (`LittleWindowReturn`); Windows to do. Sync #23: Back on a self-opened window's first page closes it; swipe/keys target it, it stays ahead of its browser, and full-screen video hides its strip (#495, #501, #540). Arc's strip palette stays fixed across spaces (#549); Windows needs these visual/navigation follow-ups. Sync #24: Ctrl/⌘F finds in a Little Window (#577), picked pages and new-tab links stay in it (#599), and a link from another app leaves the browser window behind that app (#607, Mac window server). Windows to do: find bar and link routing. Sync #25: ⌘W gives the keys to the next Little Window and a click raises one behind another app (#646, #641, `LittleWindowReturn`). Sync #26: picked in Mission Control it stays in front (#581, `LittleWindowActivation`, Mac's `WindowSpaces.swift`); Mac window server only. |
| Peek: card over the page with its own bar, Close, Expand, Add To Split | ✅ [#24] | `PeekChrome.swift`, `PeekDimPanel.swift`, `ChromiumChildFocus.swift`, `LittleWindowController.swift` | `PeekLayout`, `PeekBarColors`, `PeekTrigger`, `PeekVeil`, `PinnedNavigation`, `PeekTabs` (`openLinkTab`, `peekSplitTabs`, `joinSplit`), `PeekCloseConfirm`, `PeekAddress` | Windows: the card is an owned HostWindow with the page-coloured bar (`Peek/PeekBarView.swift`); the veil, click catcher and round buttons are owned layered windows (`CraOverlay.cpp`, `Peek/PeekOverlays.swift`). Settings ▸ Tabs ▸ Links, Shift-click, Escape (from the page or the bar), Ctrl+O, Ctrl+Shift+T reopening it, the card keeping the keyboard while it is up (#26), links leaving it for a tab, the badge on the tab it came from. Left: the card growing out of the link and back (#204, `PeekTransition`); the veil only fades. Since #24 the Mac shrinks the page behind a Peek a little unless pages fill the window edge to edge (#221, `PeekVeil`, `PeekLayout.backdrop`) and keeps the browser window's shadow (#222, `ChromiumChildFocus.swift`); Windows' browser window already stays active under the card, and its page doesn't shrink yet. Since upstream 5e777bf and 3a85ee6 (#242) a Peek waits on its tab and comes back with it, and a click on another tab's row opens that tab while the Peek waits (`PeekPresence`); Windows closes the Peek instead. Upstream e0b82e1 (#425): a call holds the first close and Close turns into a red Confirm pill (`PeekCloseConfirm`); Windows to do. Sync #23: Mac Peek closes on Escape even when a site cancels the key (#520), and its toolbar auto-hides (#493). Windows needs a real-site key-routing check. Sync #25: with the address in the sidebar, the sidebar's field and back/forward/reload drive the Peek and its card has no bar (#648, `PeekAddress`); Windows keeps the card's bar for now. |
| Air Traffic Control: route links from other apps to a space or Little Window | ✅ [#29] [#31] | `AirTrafficControlView.swift`, `LinksPane.swift`, `AppDelegate.swift` | `LinkRouting`, `AirTrafficControl`, `ExternalLink` | A URL typed in the command bar's new tab follows a route to a space too (upstream #421, `space(forTypedURL:)`). #31's PC test (10 Nov): add/edit/remove, persistence, routes, deleted-space fallback, Default, focus cycling and Escape/✕/backdrop dismissal passed. Windows keeps the sheet under Settings ▸ Tabs; the Mac moved it to Links. Sync #8 carries upstream 692e524's named Little Window space through the shared choices, a secondary space menu in the Windows sheet and `WindowList.openExternal`; this new selection still needs its sync PC test. |
| Library in the sidebar (`openLibrary`), swipe or button slides it in | 🟡 [#27] | `LibraryView.swift`, `LibraryGlyphView.swift` | `LibraryPage`, `LibraryLayout`, `LibraryList`, `LibrarySwipe`, `LibraryWidth`, `LibraryGlyphMotion`, `LibraryShortcut` | Windows (`Sidebar/LibraryView.swift`): widens 70 DIPs for the rail (Downloads, Archived Tabs), search and ⋯ menu, rows by day; Ctrl+Shift+L, footer button, Escape and Back, and reopening the last page. Left: slide/swipe, Spaces/Media/Easels/Boosts pages, drag-out, Filter by profile (`LibraryFilter`, `LibraryFilterPanel.swift`), running downloads (`DownloadList`) and archived-row accents. Upstream 0473e3d and 22a8552 give the Mac a fixed 417 pt Library sidebar that yields to the page in a narrow window; b45f55e fixes a swipe immediately after leaving it. Sync #24: the Library button's glyph moves like Arc's under the pointer (#608), and a swipe brings the Library in from a hidden sidebar (#565). Windows' button is a static glyph. Sync #25: a page shortcut (View Downloads, …) on its own page closes the Library again, and a download shows ••• on hover (#649, `LibraryShortcut`); Windows' Ctrl+J/Ctrl+H still only open it. |
| History and archive view (`viewArchive`), Archive ▸ View Archive… (`showArchive`) and Clear Archive (`clearArchive`) | 🟡 [#27] | `LibraryView.swift` | `SidebarStore`, `LibraryList`, `HistoryPage`, `ArchiveLimit` | Ctrl+H (Chrome's History key) opens the Library's Archived Tabs: search by title or address, a click restores the tab where it was closed from; Restore, Copy Link, Remove from Archive, and Clear Archive in the ⋯ menu. Upstream d110dc6 made View Archive… and Clear Archive commands of their own: in Windows' command bar too [#61]. Sync #24: ⌘Y on the Mac now opens Chromium's History page for the space's profile (#590); Windows' Ctrl+H keeps the Library's Archived Tabs (`KeyBindingDefaults.windowsText`). The archive keeps 10,000 tabs (#614). |
| Library ▸ Media (`viewMedia`): screenshots, pictures and videos from the folders shown, after Arc's opt-in card | ❌ | `LibraryMedia.swift`, `LibraryView.swift`, `MediaPreviewWindow.swift` | `MediaLibrary`, `LibraryPage` | Upstream 2294e13. Windows needs the folder scan (Pictures, Screenshots, Videos) and the grid. Since a8fde87, bf6648e and f547bd8: Arc's media preview (`MediaPreview`), grid and menu. |
| Easels (`newEasel`, `viewEasels`): Arc's canvas with text, shapes, freehand and captures, Library ▸ Easels | ❌ | `EaselBrowser.swift`, `EaselCanvasView.swift`, `LibraryView.swift`, `LibraryEaselGrid.swift` | `Easel`, `LibraryList` (`easels`), `EaselToolbar`, `EaselTileHover`, `CaptureMenuLayout`, `EaselSelection`, `EaselTextBox`, `EaselCanvas` | Upstream f7e3b8f to 3e2757b. The model, tools, hit-testing and saving are shared; Windows needs the canvas (Win2D or a XAML Canvas). Since fea3d7c and f547bd8: Arc's grid of easel cards, pictures resized by their corners (`EaselResize`). Sync #23: captures reach the target, tool keys match Arc and Library tiles grow/brighten on hover (#530); Windows has no easel canvas. Sync #24: multiple selection (#580) and wrapping text boxes. Sync #25: the canvas is endless and zooms (#580, `EaselCanvas`). |
| Boosts (`newBoost`, `viewBoosts`): restyle a site (colours, fonts, Zap, CSS and JS code with the eyedropper and hammer), Library ▸ Boosts with each site's icon | ❌ | `BoostStore.swift`, `BoostEditor.swift`, `LibraryBoostRow.swift`, `SiteIconLoader.swift` | `Boost`, `BoostPicker`, `SiteIcon`, `BoostWheel` | Upstream 415ff0e, 5da196f, 8878058, a8fde87, 6523975. The model, picker and icon choice are shared; Windows needs the editor panel and injecting the boost into pages through CEF. `LibraryPage.boosts` is in CraCore; Windows' rail doesn't show it yet. Sync #23: Arc's wheel, related-elements slider, editable Code and Site Control Center New Boost are implemented on the Mac (#478); Windows still needs the editor. |
| Now-playing player in the sidebar | ❌ | `NowPlayingTray.swift`, `NowPlaying.swift` | `AudibleHold` (Mac's WebKit tabs), `PlayerCardSession` | Windows counterpart for media keys: System Media Transport Controls. Upstream 44cce5e: on the Mac's Chromium engine the card follows the page's media session (`PlayerCardSession`); CEF pages follow the audible state. |
| Downloads rename card | 🟡 | `DownloadRenameCard.swift` | `TidyDownloads` | The Windows list has open and Show in Folder; the rename card comes with Tidy Downloads. |

## Tabs and memory

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Auto-archive Today tabs after a set time | ✅ [#14] | `TabsPane.swift` | `SidebarModel` (`AutoArchiveThreshold`) | Upstream 2e8a659 adds 90/180 days and tolerant decoding of newer values. Windows' picker lists the shared cases, so the new thresholds arrive with the model; recheck the menu in the sync PC test. |
| Tab freezing and sleeping, Tab Cleanup timers, calls stay awake | 🟡 [#69] | `BrowserManager.swift` | `TabSleepPolicy`, `TabSleepProbe`, `MemoryReclaim`, `RetainedPageBudget` | The policy is shared; Windows needs the CEF discard calls and the two Settings ▸ Tabs switches. Since upstream 135f794 (#214) the policy reads a `PageState` per page and says why it passed one over. Since upstream c09f3c3 (#237) critical memory pressure closes 9 pages a pass and each pass logs one line per way of closing (`TabSleepPolicy.PassLog`). Windows [#69]: Settings ▸ Tabs ▸ Memory's switch and time, and the minute's pass per window (`TabSleepPolicy.timer`, candidates, holds): a page passing `TabSleepProbe` (no edited fields, no playing sound, no onbeforeunload) closes and its tab reloads its address when shown. PC fixes [#77](https://github.com/vishnu597/cra-windows/pull/77): a document-start main-frame recorder retains trusted controlled-input edits and tracks running Web Audio contexts; cleared/disconnected fields and suspended/closed contexts release those holds. A missing recorder refuses sleep. Production JavaScript has Node regressions. In an overnight native check, the plain baseline reloaded while a controlled draft and an early running Web Audio context stayed at load 1. Continuous audible output was not monitored. The recorder covers the main frame; running contexts are held even when their graph is silent. Left: Chromium's discard that keeps back/forward history, freezing, the memory-pressure sweep, Chromium's audible state and freezing reasons (calls, devices). Sync #24: a window keeps its 32 most recent slept pages and the clock asks at most 16 pages a pass (#616). |
| Tabs ▸ "Always keep these sites active" (#458): listed sites never sleep on the timer, and go last under memory pressure | ❌ | `KeepActiveSitesView.swift`, `ChromeKeepActiveSites.swift`, `TabsPane.swift` | `KeepActiveSites`, `TabSleepPolicy` (`Page.keptActive`) | Upstream 67ffea8. Windows' tab sleeping (#69) can pass `keptActive` once Settings ▸ Tabs has the list. |
| Spare pages: a page made ahead for the next new tab, link or restored tab | ❌ | `SparePages.swift` | `SparePage` | Upstream 935cca1: CEF's window-making (~34 ms on the Mac) moves off the click. Windows makes each page on the click; its HWND cost is unmeasured. |
| Mute a tab (`muteTab`), speaker icon, camera and microphone dot | 🟡 [#51] | `SidebarRowViews.swift` | `SidebarModel`, `TabSound`, `RecordingDot`, `TabSharing` | Windows mutes from the tab menu (Mute / Unmute), the command bar (Mute / Unmute Tab) and a muted tab's speaker between its favicon and title (a click unmutes it). The mute is saved (`Tab.muted`) and the bridge keeps it on the next page, when the page is made again and after a relaunch. Left: the speaker on a tab that plays sound, the music notes and the camera dot need the page's audible state, which the Mac's CEF gets from a patch (`audible-state.patch`) the stock Windows CEF lacks; a favorite's tile has no Mute yet. Sync #24: the recording dot leads the row and pulses; a tab a call shares is ringed and others offer "Share this tab instead". Windows draws a still dot. |
| Open links in new tabs in the background | ✅ [#48] | `TabsPane.swift` | `LinkMenu` | The page menu's Open Link in New Tab leaves the page in front, as in Arc; Settings ▸ Tabs ▸ "Switch to links opened in new tabs from the page menu" (`openLinksInForeground`, the Mac's Links pane row) brings the tab forward. Ctrl-click and Ctrl+Shift-click keep Chrome's meaning. |
| Background tabs laid out at the pane's size, first seconds of a tab, hidden tabs give their GPU tiles back (#195) | ❌ | `BrowserManager.swift`, `PageProbe.swift`, `PageScript.swift` | `HiddenFrameRelease` | `PageScript.swift` is Foundation only: move it to CraCore. |
| Tabs keep back/forward history across relaunch; Back closes a link-opened tab and returns to its source | ❌ | `PageHistoryStore.swift`, `BrowserManager.swift` | `PageHistory`, `BackToReferrer` | Upstream 5fe9cd2 and fe7810f. Windows needs Chromium serialized-history save/restore callbacks and referrer-aware Back behavior; the shared model alone does not preserve a CEF page's history. |

## Media and capture

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Capture (`capturePage`): copy the page | 🟡 [#17] | `CaptureOverlay.swift`, `ViewSnapshot.swift`, `CaptureAccess.swift`, `MainWindowController+Capture.swift`, `LittleWindowController+Capture.swift`, `ScreenshotPick+AppKit.swift` | `PageCapture`, `ContentCapture`, `CaptureMenuLayout` | Windows copies the visible page or the full page. Missing: element/region pick with copy/save/send, `captureFullPage` and `capturePortrait` as commands, New Easel and Send To… an easel. Upstream 6d6ede8 makes capture target a Peek's page and show its result inside the Peek; that path also needs Windows support. Sync #23: Option picks the element under the pointer (#451), and screenshot apps pick the actual Little Window (#539); Windows element/region capture remains missing. |
| Pause All Media (`pauseAllMedia`) | 🟡 [#86] | `PauseAllMedia.swift` | `MediaPause`, `MediaPauseProbe` | Sync #23, #438: pause loaded pages across windows/profiles/Little Windows/Peeks, reporting pages that keep playing (including Web Audio). Windows [#86]: the command bar's Pause All Media asks every loaded page in every window, Little Window and Peek (sleeping tabs stay asleep) and shows Mac's toast (Paused N Tabs, N Kept Playing with Show). Stock CEF has no Cra.pauseMedia and no audible state, so the page's own script (`MediaPauseProbe`) pauses and counts the top frame's and same-origin frames' players; frames from other sites are paused unheard (`cra_browser_execute_javascript_in_subframes`). Left: media sessions without elements, Web Audio and cross-site frames can't be reported as kept playing until the bridge knows a page's sound. |
| Picture in Picture (`pictureInPicture`), automatic on leaving a video tab or a Meet call (Document Picture in Picture, upstream #198), throw into corners | ❌ | `PictureInPictureChrome.swift`, `PictureInPictureControls.swift`, `ChromiumPictureInPictureSeal.swift` | `PictureInPictureGesture`, `PictureInPictureThrow`, `PictureInPictureLayout`, `PictureInPictureInput`, `PictureInPicturePinch`, `WindowCoverage`, `PictureInPictureFingers`, `PictureInPictureRequest`, `WebKitPictureInPicture` | Shared gestures, throws, bar/scrim and limits. Upstream a4c4b9b, c247e40 and 9ae7224 refine Chrome window focus, reopen on the previous display and spring-back from beyond the screen edge. Windows needs the native window and bridge; cbb5753's automatic PiP setting is per site. Sync #23: Minimize works at every size (#462, #475), pinch resizes, throws keep the pointer/window in reach, Chromium controls take no input and an uncovered second-display window keeps its video (#516, #533, #534, #535). Windows has no PiP host yet. Sync #24: pinch resize (#573), PiP on WebKit pages (#585). |
| Protected media (DRM services in Safari's engine) | ➖ | `PageEngines.swift`, `WebKitBrowser.swift`, `WebKitStores.swift` | `ProtectedMedia`, `ProtectedVideos` | Mac only (FairPlay in WebKit). On Windows the counterpart is a Widevine-capable CEF build; the per-site choices in `ProtectedMedia` can be reused. Sync #24: Fandango at Home and YouTube's protected videos ask per video (#588). |
| Screen sharing with tab audio, web notifications shown and clicked | 🟡 [#17] | `CraCEF.mm` | `PermissionPrompt` | The prompts work on Windows; Chrome's screen picker and notifications opening their page haven't been checked on the PC. |
| Speech recognition on device | ❌ | `CraCEF.mm` | `ChromiumLocale` | The `speech-on-device` CEF patch is Mac only. |

## Profiles, privacy and site data

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Permission prompts | 🟡 [#17] | `CraCEF.mm`, `BrowserManager.swift` | `PermissionPrompt`, `PermissionAsk` | Windows prompts work. Upstream f8a9d1f queues a hidden tab's camera/microphone request until the tab is shown and logs outcomes; Windows does not yet use `PermissionAsk` for that waiting policy. |
| Profiles: per-space cookie folders, Set Profile, Change Profile, New Profile, Settings ▸ Profiles | ✅ [#19] | `ProfilesPane.swift`, `ProfileDialogs.swift`, `NewProfileDialog.swift` | `SpaceProfiles`, `DeletedProfiles` | |
| Website languages per profile in Settings ▸ Profiles, Language Settings (`languageSettings`) opens Chromium's page (#209) | 🟡 [#63] | `ProfilesPane.swift` | `BrowserLanguages` | Upstream b528590. Windows has the command ([#63], Chromium's page in a tab of the window's space). Left: the row in its Profiles pane, reading each profile's Preferences. |
| Rebuild profiles from Arc (`rebuildArcProfiles`) | ❌ | `ArcProfileRebuilder.swift` | `ArcProfileRebuild` | Waits for Arc import. |
| Clear Cache, Clear Cookies | ✅ [#17] | `SiteData.swift` | `SiteDataClearing` | |
| Clear Browsing Data (`clearBrowsingData`) | ✅ [#55] | `AppDelegate.swift` | `BrowsingDataClear` | Windows: Ctrl+Shift+Delete (Chrome for Windows' key; `KeyChord.forwardDelete`), the command bar and Settings ▸ Privacy ▸ Data ▸ Clear… open Chrome's dialog in a tab; what it deletes from history leaves the command bar too (`BrowsingDataClear.watchScript`, the Mac's script). Not from a private window. |
| Added block lists in Settings | ❌ | `BlockLists.swift`, `PrivacyPane.swift` | `CustomBlocklists`, `CustomBlocklist`, `FilterList`, `BlocklistRules` | Sync #23, #507: URL validation, kept copies and domain parsing are shared. Windows still loads only the bundled list; added-list UI/fetching/persistence and merged-domain bridge remain. Sync #24: added lists apply their path and hiding rules (#570). |
| Ad and tracker blocker | ✅ [#45] | `CraContentBlocker.h`, `CraCEF.mm` | `SiteControlCenter` | `CraCEFWin.cpp` includes the Mac's `CraContentBlocker.h` as is: the same matcher, the same third-party rule and the same `resources/blocklist` list, copied beside Cra.exe by build.ps1 and read off the UI thread at launch. The switch follows `blockAdsAndTrackers` live, from Settings ▸ Privacy, the Site Control Center and the onboarding. |
| Block Cookie Banners (Arc's, off by default) | ✅ [#46] | `BrowserManager.swift`, `PrivacyPane.swift` | `CookieBanners` (`pageScript`), `SidebarStore` (`cookieBannerCSS`) | Upstream 93b20a6. The stylesheet is shared. Windows: Settings ▸ Privacy's switch; each page adopts it as it commits (`cra_cef_set_page_start_script`, from the main world, where the Mac uses an isolated one; nothing is left on `window`). |
| Always use secure connections (HTTPS-only), Secure DNS | ✅ [#54], [#56] | `PrivacyPane.swift`, `SecureDNSSetting.swift` | `SecureDNS` | Both are Chromium prefs; the decisions are shared. Windows: Settings ▸ Privacy ▸ Connections has the HTTPS-only switch (`httpsOnly`, Chrome's `https_only_mode_enabled` on every profile, private windows and profiles that load later included) and the Secure DNS menu (Automatic, Off, Chrome's providers, Custom… with a template field; `SecureDNSChoice.menuGroups`, `SecureDNS.footnote(managed:)`), read from and written to Local State, read-only when a policy sets it. |
| Passwords and cookies encrypted with a key of Cra's own | ❌ | `SafeStorage.swift`, `keychain-service-name.patch` | | Windows counterpart: DPAPI, which Chromium uses by default. Confirm the stock CEF build does. |
| Safe Browsing, Web Push | ❌ | `CraCEF.mm`, `safe-browsing-update-interval.patch`, `gcm-enabled.patch` | | Needs Cra's CEF patches on the Windows build (today it uses Spotify's stock build). |
| Passkeys with the platform authenticator | ❌ | `webauthn-keychain-access-group.patch` | | Windows counterpart: Windows Hello, which Chromium uses on Windows. Check it works in CEF. |
| Opt-in anonymous usage stats and crash reports | ❌ | `SharingService.swift`, `PrivacyPane.swift`, `OnboardingSteps.swift`, `SidebarView.swift` | `Sharing` | Upstream ff99afd, 2eb5877 and 0495029; `docs/sharing.md` describes the fields, release-only guard, daily timing and separate consent. Upstream CONTRIBUTING now expressly documents this opt-in exception. The models and Mac service arrive in the sync; Windows has no sending service, consent UI or sidebar prompt, so the Windows app sends none of these reports. |

## DevTools and Developer Mode

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| DevTools docked in the page's place (`devTools`, `inspectElement`, `jsConsole`), Chrome's dock sides and undocking | ✅ [#20] | `MainWindowController.swift` | `DevToolsToggle` | Moved to CraCore in #20; both apps decide each press with it. |
| Developer Mode for a site (`toggleDeveloperMode`): the striped bar with the full URL edited in place, Copy, Console, Network, Inspect; host and port under the tab's title; the ring round the open tab | ✅ [#22] | `PaneToolbarView.swift`, `SidebarRowViews.swift` | `ToolbarComposition`, `DeveloperBar` (`SpaceTheme.developerBar`, `DeveloperStripes`, `DeveloperTabRing`, `OKLab`) | Windows: Ctrl+Shift+D (the Mac's ⌃D is Pin Tab there). The bar's colours, stripes and ring moved to CraCore in #22 for both apps. Not in a split, as on the Mac; Windows has no normal toolbar yet, so a split pane shows no bar. localhost, 127.0.0.1 and *.localhost start in Developer Mode on any port (upstream 0efe33a, 6d65cf8): Windows gets it from the shared `isDeveloperMode`. |
| Performance recorder, Settings ▸ Performance, Export Diagnostics | ❌ | `PerformancePane.swift`, `Perf.swift`, `PerfCEF.swift`, `PerfFiles.swift`, `PerfRecorder.swift`, `PerfSamplers.swift`, `MainLoopObserver.swift`, `HitchMonitor.swift`, `Diagnostics.swift`, `CraLog.swift` | `PerfHistory`, `PerfInsights`, `PerfMetric`, `PerfProcessTable`, `PerfReport`, `PerfSampleStack`, `PerfSession`, `PerfStall`, `PerfState`, `LogHistogram`, `SiteNames`, `DiagnosticsRedaction`, `DisplayDiagnostics`, `PerfRunaway` | The recorder's model is shared; samplers are per platform. `CraLog.swift` is Foundation only: move it to CraCore so both apps log the same way. |

## Extensions

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Install from the Chrome Web Store or a folder, Extensions menu (`openExtensions`, `manageExtensions`) | 🟡 [#39](https://github.com/vishnu597/cra-windows/pull/39) | `ExtensionStore.swift`, `ExtensionsMenu.swift`, `DebugFileDrop.swift` | `InstalledExtensions`, `ExtensionManifest`, `ExtensionLaunch`, `ExtensionPagePlacement`, `ExtensionProfiles`, `ExtensionPageRetry`, `WebStoreInstalls`, `ExtensionImport`, `ExtensionStartUpPages`, `ExtensionCopyRemovals` | Stock CEF runs Web Store installs with Chrome's own dialog, content scripts and chrome://extensions (PC experiment, 12 Nov 2026). Windows lists each profile's installs live (`extensions.settings`) in the Site Control Center (Ctrl+E), and pages Chromium opens in windows of its own (options, welcome pages, `chrome.tabs.create`) become Cra tabs. Settings ▸ Extensions ▸ Add Unpacked Extension… copies a folder into Cra's Extensions/, loaded with `--load-extension` at the next launch (`ExtensionFolders`, location 8 listed with the rest), with Chromium's web request proxy on from the start, as on the Mac, so an ad blocker loading late doesn't strand a page. Import from Another Browser copies the picked extensions in as Extensions/<id> [#41](https://github.com/vishnu597/cra-windows/pull/41) (`ExtensionImport`). Their onInstalled welcome pages, which Chromium fires on every launch for `--load-extension` extensions, open only on the launch after one arrives [#42](https://github.com/vishnu597/cra-windows/pull/42) (`ExtensionStartUpPages`, the Mac's AppDelegate rule; the Mac could read it too). Left: per-profile loading (`ExtensionProfiles`; stock CEF loads Cra's folders in every profile), dropping a copy once the Web Store installs the same extension (`WebStoreInstalls`), the "Switch to Chrome" banner on the Web Store, an extension's open pages closing when it is turned off (they turn into a blank tab), external extensions other software registers for Chrome (they arrive turned off), popup-type `windows.create` windows (they open as tabs). Upstream 3fe0c5b (#227): quitting while a Web Store install runs no longer crashes. Sync #23: chrome://extensions removal prevents a folder-loaded copy returning on the Mac; Windows' copy loader still needs the shared policy. Engine CRX/permission/full-screen fixes do not change stock CEF. Sync #25: a .crx dropped on chrome://extensions installs, tested through `cra://debug?dropFile=` (`DebugFileDrop.swift`, #593); Windows needs its own drop check. |
| Toolbar and pinned buttons, popups, badges, live icons | 🟡 [#39](https://github.com/vishnu597/cra-windows/pull/39) | `ExtensionActions.swift`, `ChromiumPageFocus.swift`, `ExtensionPopupWindow.swift`, `ExtensionPopupCandidate.swift` | `ExtensionActionState`, `ExtensionBadge`, `PinnedExtensions`, `PinnedExtensionGrid`, `ToolbarExtensionFit`, `DismissingClick`, `FirstClick` | A Site Control Center tile opens the popup page in a card of its own (360 × 480, not sized to the page) or the options page (`ExtensionLaunch.popupWindow`); Chrome's action doesn't run, so a popup's "current tab" is itself (uBlock Origin Lite's popup says "not a website"). Left: pins, badges, live icons, Chrome's own action (the extension CEF patches, `extension-popup-browser-info.patch` and the others, need the Windows CEF build: PC experiment, 13 Nov 2026, the DevTools pipe and `Extensions.loadUnpacked` work on stock CEF 156, but `Extensions.triggerAction` on a Cra tab crashes it, the null tab-browser `extension-trigger-action-null-checks.patch` fixes). |
| Extension side panels (MetaMask) | ❌ | `ExtensionSidePanel.swift` | `ExtensionSidePanel` | |
| Native messaging hosts (1Password and others) | ❌ | `NativeMessagingHosts.swift`, `ExtensionProtocolReply.swift` | `ExtensionProxyControl` | Windows reads hosts from the registry, not folders. Both files are Foundation only: move the shared part to CraCore. |
| Settings ▸ Extensions | 🟡 | `ExtensionsPane.swift` | `ExtensionFolders` | See the Settings section's Extensions row. |

## Settings

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Settings window, back and forward, panes listed by `DiaSettingsPane.windowsPanes` | 🟡 [#14] | `SettingsWindowController.swift`, `SettingsKit.swift`, `MemberCardView.swift`, `SettingsArt.swift`, `SettingsPictures.swift` | `DiaSettingsNavigation`, `DiaSettingsMetrics`, `SettingsTab`, `MemberCard`, `MaxMasterSwitch`, `TranslateReset` | Windows has General, Tabs, Privacy, Profiles, Extensions, Shortcuts and Advanced (Opening and quitting, page-top dragging; built since #59 and #64 but listed only after the 17 Nov PC test found it unreachable). Panes not on Windows yet: `links`, `max`, `plugins`, `performance`. Upstream d34987a/b4c20de add inset selection, pane clipping, descriptive rows and layout pictures; Windows needs those visual refinements. The #31 PC test still showed clipped Back/Forward focus outlines; keyboard reactivation needs a separate focused reproduction. Upstream 80cdfe7/caaa884 (#372) moved the Mac to Arc 1.172.2's window: 684 × 650 pt with ten tabs in a toolbar (`SettingsTab`), a member card first. Windows still draws Dia's sidebar window (its CraCore types are now `Dia*`); next: follow the tab toolbar. PR #75 lists Advanced; the next PC test must verify its opening/quitting and page-top-drag switches are reachable. |
| General | 🟡 [#14] [#29] | `GeneralPane.swift`, `AppIconPicker.swift` | | Windows has default-browser registration and Open at login. #31's PC test verified title-bar icons on browser, Settings and Little Windows; taskbar-button appearance remains unverified. Missing: the app icon picker, including upstream's Violet choice and 72 pt tiles (b454fdb, 5e5a220, 41deeb9). |
| Tabs | 🟡 [#14] | `TabsPane.swift` | `SidebarModel`, `AddressBarPlacement` | New Tab placement, single-space header, cleanup, Peek, external links and the #31 Air Traffic Control sheet are present. Missing: address-bar position (3d560c2), current-space-only search (cab6d40), sleeping, shared favorites, background-tab preference, Little Window archive time and upstream's descriptive/pictured layout. |
| Links | 🟡 [#31] | `LinksPane.swift`, `AirTrafficControlView.swift` | `LinkRouting`, `AirTrafficControl` | Upstream b4c20de moves Little Windows, Peek, foreground-link preference and Air Traffic Control out of Tabs into Settings ▸ Links. Windows keeps its implemented rows under Tabs; it does not list a Links pane yet. |
| Shortcuts | ✅ [#15] | `ShortcutsPane.swift` | `KeyBindingRegistry` | |
| Profiles | ✅ [#19] | `ProfilesPane.swift` | `SpaceProfiles` | |
| Privacy | 🟡 [#45] | `PrivacyPane.swift` | `SecureDNS` | Windows has the Content blocking card's ad and tracker [#45] and cookie banner [#46] switches. Left: fingerprinting protection, secure connections and DNS, the Data card. |
| Extensions | 🟡 | `ExtensionsPane.swift` | `ExtensionFolders`, `InstalledExtensions` | Windows lists every profile's installs once each, with Remove (Cra's own folder) or Remove… (chrome://extensions), Add Unpacked Extension… (Windows' folder picker) and Open Chrome's Extension Manager. Cra's folders load in every profile (stock CEF has no `extension-profiles.patch`). No Live Folder plugins under it yet (Plugins row). |
| Plugins | ❌ | `PluginsPane.swift` | `LiveFolderPlugin`, `LiveFolderPluginPackage` | With the live-folder plugin runtime: install, permission summary, enable/disable, reload and remove packages. |
| Advanced: engine, export bookmarks, versions | 🟡 [#65] | `AdvancedPane.swift`, `SidebarExport.swift` | `BookmarksExport` | The bookmarks-file writer is CraCore's `BookmarksExport` ([#65]); the Mac's `SidebarExport` keeps its save panel. Windows: Settings ▸ General ▸ Your data ▸ Export spaces and pinned tabs, with Windows' Save dialog. Left: the engine and version rows. Sync #23: clicking the Mac version copies bug-report text (#461); Windows still needs the version/engine rows. |
| Max, Performance | ❌ | `MaxPane.swift`, `PerformancePane.swift` | | See Arc Max and DevTools. |

## Import and onboarding

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Import from Arc and Dia: spaces, pinned, folders, favorites, archive, profiles (`importData`) | 🟡 [#35](https://github.com/vishnu597/cra-windows/pull/35) | `Importers.swift`, `DiaSidebar.swift`, `BrowserSources.swift`, `YabImporter.swift`, `ArdiaImporter.swift`, `ImportTree.swift` | `ImportPlan`, `ArcImporter`, `SidebarStore+Import` (`apply`), `WindowsImportSource`, `MD5`, `ArcThemeImport`, `ExtensionProfiles`, `ArcSpaceIcon`, `ExtensionImport` | Extensions: after a browser is picked, the ones Cra doesn't have are listed to tick (those on in the browser ticked), and the picked ones load from the next start [#41](https://github.com/vishnu597/cra-windows/pull/41); the onboarding's import doesn't offer them yet. Windows lists Chrome, Brave, Edge, Opera, Opera GX, Vivaldi, Chromium, Helium (`%LOCALAPPDATA%\imput\Helium\User Data`, as the Mac does) and Aside (`%LOCALAPPDATA%\Aside\User Data`, Windows only) besides Arc [#42](https://github.com/vishnu597/cra-windows/pull/42). Since upstream 272980a an Arc space with an Icon-tab glyph imports as its symbol (`ArcSpaceIcon`), which Windows doesn't draw yet (space menu row). Windows: Import from Another Browser… (command bar, Settings ▸ General ▸ Your data) reads Arc for Windows' package folder (`%LOCALAPPDATA%\Packages\TheBrowserCompany.Arc_*\LocalCache\Local\Arc`): spaces, profiles, pinned, favorites, archive, Air Traffic Control. Arc for Windows' own preferences (toolbar, auto-archive) aren't read. No Dia on Windows. Next: the onboarding flow (item 11). Sync #23: Mac import also reads Yab/Ardia spaces, pinned tabs, folders and favorites; Windows has no source discovery/UI for those Mac browsers. |
| Import from Chrome, Edge, Brave, Opera, Vivaldi, Helium: tabs, bookmarks, history, extensions | 🟡 [#35](https://github.com/vishnu597/cra-windows/pull/35) | `ChromiumImporter.swift`, `ExtensionImporter.swift` | `ChromiumImport` (`ChromiumImporter`: profiles, bookmarks, sessions), `TopSite`, `ChromiumTime` | Bookmarks and the last session's tabs, one space per profile, from Chrome, Brave, Edge, Opera, Opera GX, Vivaldi and Chromium. Left: extensions, Helium (its Windows folder is unconfirmed). |
| Passwords and sign-ins | 🟡 [#36](https://github.com/vishnu597/cra-windows/pull/36) | `CredentialImport.swift` | `ImportedCredentials` (`ImportedLogin`, `ImportedCookie`), `PendingCredentials`, `CredentialImportReport`, `ChromiumOSCrypt`, `ChromiumCredentialRows`, `AESGCM`, `SHA256Hash` | Windows: the import card's "Passwords and sign-ins" box reads each profile's Login Data and Cookies with the browser's Local State key (DPAPI, then AES-GCM in CraCore), seals them with Cra's key and stages them in the Mac's `pending-credentials.json`; they go into Cra's profile at the next launch (`CraData.cpp`: DPAPI and winsqlite3). Chrome 127+ seals cookies to itself (app-bound "v20"): those stay, and the card says so. A running browser holds its Cookies shut: the card asks to quit it. Left: a Restart button, Firefox. The Mac still keeps its own copy of the staging code. |
| Firefox and Zen | ❌ | `FirefoxImporter.swift`, `ZenImporter.swift` | | Same move. |
| Safari | ➖ | `SafariImporter.swift` | | No Safari on Windows. |
| Onboarding: import, theme colour, address bar placement | 🔜 | `ImportFlow.swift`, `ImportFlowArt.swift`, `ImportFlowViews.swift`, `OnboardingSteps.swift` | `Onboarding` (`isNeeded`, `Flow`, `presetPins`, `pinCandidates`), `TopSite` (`historyQuery`, `ranked`, `faviconQuery`), `ImportSourceList` | Windows: on a fresh install a card over the first window runs the cover, default browser (with open at sign-in), the import list, pinned tabs (the imported browser's most visited sites and Dia's presets, with their icons), the space's colour and the outro (`OnboardingView`, `OnboardingSites`). Not yet: the privacy step (no ad blocker or usage stats on Windows), the address bar layout (no toolbar), Dia's artwork and slide transitions. The Mac reads the shared step rules and pin suggestions. Sync #23: Mac onboarding lists every supported browser and dims those without readable data; Windows still uses its available-source list. |

## Arc Max (on-device AI)

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Tidy Tabs | ➖ | `TidyTabsService.swift`, `TidyTabsModel.swift` | `TidyTabs`, `AppleIntelligenceStatus` | Runs on Apple Intelligence; Cra sends nothing to a server. A Windows counterpart would need an on-device model (Windows AI APIs on Copilot+ PCs); the prompts and parsing in CraCore can be reused. Sync #23: Max distinguishes unavailable on-device models on Apple silicon from unsupported hardware (#538); this status is Apple-specific. |
| Tidy Tab Titles (and Arc's rules for 52 sites) | ➖ | `TidyTitlesService.swift`, `TidyTitlesModel.swift`, `TidyTitleLayout.swift`, `TidyTitleSweep.swift` | `TidyTitles`, `TidyTitleRules`, `TidyTitleRules+Data` | The rule-based titles need no model and could ship on Windows on their own. |
| Ask on Page: find-or-ask card on ⌘F (#393) | ➖ | `AskOnPageService.swift`, `AskOnPageCard.swift`, `BrowserManager+AskOnPage.swift` | `AskOnPage`, `AskOnPageContent`, `AskOnPagePrompt` | Upstream 2b39a45, dc6d118: answered by Apple Intelligence on the Mac. Windows keeps plain find in page until it has an on-device model. |
| Instant Links: Shift-Return on a search opens the top results (#409) | ➖ | `InstantLinksService.swift` | `InstantLinks` | Upstream 426c345: planned by Apple Intelligence on the Mac. Windows' command bar has no Shift-Return until it has an on-device model. |
| Tidy Downloads | ➖ | `TidyDownloadsService.swift`, `TidyDownloadFiles.swift` | `TidyDownloads` | As Tidy Tabs. |
| 5-Second Previews: hover a link for a summary card (#324, #442) | ➖ | `LinkSummaryService.swift`, `LinkSummaryPreview.swift`, `LinkSummaryShareImage.swift`, `LinkSummaryFetch.swift`, `LinkSummaryImageFetch.swift`, `LinkSummaryEligibility.swift` | `LinkSummary`, `LinkSummaryCard`, `LinkSummaryShareBitmap` | Runs on Apple Intelligence, as Tidy Tabs. The fetch, eligibility and card rules in CraCore can be reused once Windows has an on-device model. |

## System integration and release

| Feature | Windows | Mac code | Shared in CraCore | Notes and next step |
|---|---|---|---|---|
| Open at login | ✅ [#14] | `SystemIntegration.swift` | | Windows: the Run key. |
| Default browser (`setDefaultBrowser`), opening links from other apps | 🟡 [#29] | `SystemIntegration.swift`, `AppDelegate.swift` | `ExternalLink` | Windows registers under HKEY_CURRENT_USER (`CraHTML`, `StartMenuInternet\Cra`, RegisteredApplications) and opens Windows' Default apps; the user chooses the default. External links and second launches work through Chromium's process singleton (`OnAlreadyRunningAppRelaunch`). #31's PC test confirmed the remaining Windows 11 25H2 gap: searching Default apps still does not list Cra, despite registration. No default association was changed by the test. Signing, installer registration and refresh at sign-in remain avenues to investigate; pinning to taskbar remains a release task. |
| Background link tabs: placement and creation notice | 🟡 | `BrowserManager.swift`, `MainWindowController.swift` | `LinkTabPlacement`, `BackgroundTabToast` | Sync #23, #532/#543: Windows already opens foreground/background tabs. The off-by-default below-current-tab setting, source-relative middle/Ctrl-click slots and hidden-sidebar creation toast still need integration. |
| Another app's link (zoommtg:, slack:) in a new tab or window opens the app after asking, not a blank tab (#207) | ❌ | `AppLinkPrompt.swift`, `CraCEF.mm` | `AppLinks` | Upstream d1ad2af. Windows: CEF's external-protocol callback and a prompt in the page's place. |
| Links Cra opens to crabrowser.app (release notes, help) name the button they came from | ❌ | `AppDelegate.swift`, `SoftwareUpdater.swift` | `SiteLinks` | Upstream 94c1fc3. Comes with Windows' help links and the updater. |
| `cra://` scheme for scripting (`cra://open?space=`) | 🟡 [#31] | `AppDelegate.swift`, `TestGesture.swift` | `CraLink`, `ExternalLink`, `InternalURLRaise` | #31's PC test passed registration, commandbar query/edit, dismiss, foreground/named-space/background/Little Window opens, normal-mode refusals, opt-in action/navigate and cold starts. The background tab remained unread and selection did not change. Sync #8 carries upstream 6a4e05a's no-activation policy for background opens. Left: key, import, debug and `CRA_COMMAND_FILE`; Mac link parsing still has not switched to `CraLink`. |
| Auto-update (`checkForUpdates`), update banner | ❌ | `SoftwareUpdater.swift`, `UpdateBanner.swift`, `UpdaterWindow.swift`, `UpdatePrewarmer.swift` | `UpdateNotice`, `UpdatePrewarm`, `UpdateChannel` | WinSparkle reads the same appcast. Upstream 110b3c6/ad2ed55 keep the news/sponsor card and show an update-news toast with the sidebar hidden. Windows needs its updater and this notice flow. Phase 3. Sync #23: Mac Stable/New feeds, promotion/rollback and preserved release download counts; Windows has no updater/channel selector. |
| Daily installation count | ➖ | `SharingService.swift` | `Sharing`, `InstallCheckIn` | Sync #23: the released Mac sends a daily random install id, version and chip independently of usage-sharing consent. Windows has no reporting service/startup call; this sync adds no Windows check-in. |
| Signed installer | ❌ | | | Authenticode and MSIX or Inno Setup. Phase 3. |
| Custom app icon | ❌ | `AppIconManager.swift` | | |
| Bluetooth device cache for Chromium | ➖ | `ChromiumBluetoothCache.swift` | | Mac only (CoreBluetooth). |
| Chromium follows the system language | ✅ [#67] | `AppDelegate.swift` | `ChromiumLocale`, `ChromiumLocale+Paks` | Windows picks from CEF's `locales/*.pak` and the user's display languages (`ChromiumLocale.pick(localePaks:)`, where the folder's en-US is plain English). |
| Window switchers and window managers see one window per Cra window (#391, #401) | ➖ | `DockedWindowAccessibility.swift`, `SwitcherWindows+AppKit.swift`, `WindowManagers+AppKit.swift` | `SwitcherWindows`, `WindowManagers` | Upstream ac12d60, 192b41e: macOS lists docked Chromium windows through accessibility. On Windows CEF's pages are child windows of Cra's top-level window, so Alt+Tab and snapping already see one window. Check on the PC that a Little Window's or Peek's page doesn't show as a window of its own. Sync #23: the Mac Little Window exposes standard movable/resizable accessibility attributes; Windows uses top-level windows and needs no macOS AX adapter. |
| Shortcuts set in the system's keyboard settings work in pages | ➖ | `AppDelegate.swift` | | macOS only. |
| AppleScript with Arc's dictionary, JavaScript from Apple Events off by default (`allowAppleEventsJavaScript`) | ➖ | `AppleScripting.swift` | | macOS only (upstream de695e2). Windows' scripting goes through `cra://` (its own row). |, `AppleScriptTabOrder`
| "Quit Cra?" asked once, also while downloads run; windows quit in full screen reopen in full screen (#272, #426) | ❌ | `ChromiumQuitCancel.swift`, `AppDelegate.swift` | `QuitRequests` | Upstream 067918e, b87ce5f. Windows closes without asking. |
| Keep Cra in the menu bar after quitting (#231) | ❌ | `MenuBarItem.swift` | `MenuBarMode` | Upstream 96c0255. Windows' counterpart is a notification-area icon that keeps Cra running. |
| Open a Safari page handed off from an iPhone | ➖ | `AppDelegate+Handoff.swift` | | Upstream 4fd9b3e uses macOS Handoff/NSUserActivity. There is no direct Windows Handoff counterpart in this port. |
| Chromium engine: Cra's own build of Chrome's framework in place of CEF, its version in Settings and About | ➖ | `EngineFramework.swift`, `EmbeddedDevTools.swift`, `PageDialogs.swift` | `EngineVersion`, `PageDialogPlacement` | Upstream 5bb7467 onward (Chrome 158.0.8127.37, `fetch-engine.sh`). The Mac leaves CEF; Windows stays on stock CEF (`fetch-deps.ps1` still reads `fetch-cef.sh`). A Windows engine build would be its own project. `EngineVersion.label` is portable for a Windows About line. Sync #23: engine -15 through -27 correct page creation, dialog/print placement (#574), bars, DevTools and extension hosts; Windows retains stock CEF and its existing window ownership. |
| Chrome's bars over a page ("<extension> started debugging this browser", #241) drawn by Cra | ➖ | `InfoBarStrip.swift` | `PageInfoBar` | Upstream: only the Mac engine reports infobars; on CEF, Windows included, Chrome draws its own. |
| Launch migrations run when no other process holds the data folder, not when no other Cra runs (#299) | ❌ | `AppDelegate.swift` | `DataFolderOwner` | Upstream 2f5e3b0. Windows' launch steps (extension copies, `extensions-welcomed.json`) don't check the folder's `SingletonLock` yet. |
| The iPhone app (Arc Search's design) and its Mac sync | ➖ | `iOS/Cra` | `MobileAI`, `MobileArchive`, `MobileBlockerNotices`, `MobileBlocklist`, `MobileBrowseForMe`, `MobileBrowseToggle`, `MobileChrome`, `MobileCoachMark`, `MobileDownloads`, `MobileFidget`, `MobileMotion`, `MobileOnboarding`, `MobilePageMenu`, `MobileSearchEngine`, `MobileSettings`, `MobileShareInbox`, `MobileSpaces`, `MobileSuggestions`, `MobileSummary`, `MobileSwipe`, `MobileSyncIntro`, `MobileTabCarousel`, `MobileTabs`, `MobileTranslate`, `MobileBlockerReadiness`, `MobileFavicons`, `MobileKeyboard`, `MobileSpacesSheet`, `MobileExternalLinks`, `MobileLinkMenu`, `MobileLoadFailure`, `MobileRecentTabs`, `MobileStatusBand` | Upstream's iPhone app (iOS/, after Arc Search 1.49). Its decisions live in CraCore's Mobile folder and build on Linux and Windows too, but they serve the phone. Windows has nothing to port. Sync #23: iOS passkeys, collapsing bar/keyboard, previous-tab flicks, newer Mac sidebar loading and cached Spaces sheets serve the phone, not a Windows UI. |
| Sync sidebar, settings and shortcuts through iCloud or a folder | ❌ | `SettingsSyncService.swift`, `SyncSection.swift` | `SettingsSync`, `SidebarMerge` | Upstream cae2918. Folder manifests, merge and conflict decisions are portable; Windows needs the folder chooser, file coordination/watching and settings UI. iCloud integration is Mac-specific. Sharing consent and MCP permissions do not sync. Sync #23: bundle merge keeps closed tabs closed and a live page's address (#474, #479); Windows still has no sync transport/UI. |
| Agents in Cra: permissioned local MCP server and bridge | ❌ | `MCPServer.swift`, `MCPListener.swift`, `MCPConnection.swift`, `MCPPeer.swift`, `MCPInput.swift`, `MCPPage.swift`, `MCPTransfers.swift`, `AgentFace.swift`, `AgentPill.swift` | `MCPAgents`, `MCPAgentAids`, `MCPInputPlan`, `MCPProtocol`, `JSONNumber`, `MCPReferences`, `MCPSession`, `MCPUploadTarget`, `MCPAgentPresence` | Upstream 31187f8. Protocol/session/reference/input policies are shared. Windows needs transport/client identity, approval UI and native page/input/capture integration; this sync does not start an MCP listener on Windows. JavaScript and history access remain separate opt-ins in the model. Sync #23: face/cursor and Take Over pill show actions on the watched tab and follow smooth scrolling; Windows starts no MCP listener/presence UI. |
| Feature flags | ❌ | `FeatureFlags.swift` | | |
| Persistence of the data folder | ✅ [#5] | `Persistence.swift`, `SidebarStore+App.swift`, `Scheduler.swift` | `JSONStore`, `Scheduling`, `SidebarStore` | `%LOCALAPPDATA%\Cra` holds the same files. Keep both versions of `Persistence.swift` in step: Mac tests compile it with CraCore. |
| Portability helpers, CraCore seen by every Mac file | ✅ [#1] [#16] | `CraCoreExports.swift`, `TestScreen+AppKit.swift` | `CGVector+Portable`, `CGAffineTransform+Portable`, `ChromiumLocale`, `TestScreen` | `TestScreen` is the portable test-display decision; `TestScreen+AppKit.swift` applies it only on the Mac. New shared geometry helpers stay guarded for Linux and Windows. |

The #31 PC test also reproduced black text on a dark background on an unstyled page, over
both file:// and localhost HTTP. The cause is still open. Escape worked during ordinary sheet
editing; one Escape after external navigation and automated Settings reactivation was ignored,
as were some Alt+F4 attempts. Close buttons worked and no crash dump was produced; this remains
an unconfirmed reactivation/focus follow-up, not a demonstrated #31 regression.

Sync #23 merges **8cda780..d1d90693** (156 commits, 18 Nov 2026). Every commit is assigned below; test/merge follow-ups keep the same feature decision. This brings no Mac engine, Apple Intelligence service or iOS adapter to Windows.

| Commit | What | Windows |
|---|---|---|
| 75a5bed9, 0888d019, fda97501, d09bb79b, a2b25f27, e4cce714, a341c09f, afe1754e, 7f1c8209, f709508c, 8f990359, 6c4244a8 | PiP Minimize, document players, bounds, coverage, input and pinch | Picture in Picture row (`PictureInPictureInput`, `PictureInPicturePinch`, `WindowCoverage`); Windows host/controls absent. ❌ |
| f7e0af27, e8c93002, af7078bd | Ask on Page prompt/theme and Max model availability | Arc Max rows (`AskOnPagePrompt`, `AppleIntelligenceStatus`); Apple-only on-device services. ➖ |
| 46109356 | Pause All Media and engine -15 | New Pause All Media row (`MediaPause`, `pauseAllMedia`); Windows enumeration/bridge absent. ❌ |
| c3cacdad, ae4a7e22, f4fdf6f4, d885d37e, ed49115f | Command scope fill, close, search continuation and query across app switches | Command/search rows (`ScopedSearchFill`, `TypedURL`, `CommandBarClosing`); shared decisions arrive, Windows visuals/focus still need checks. 🟡 |
| 860044ca | Copy version for bug reports | Advanced row; Windows version/engine rows missing. ❌ |
| b83b41ee, 5b969e95 | Option element capture; screenshot picking a Little Window | Capture row (`ContentCapture`, `ScreenshotPick`, `ScreenshotPick+AppKit.swift`); Windows element/region capture absent. 🟡 |
| fac5b66c, 49015481, f3a0804e, ca31e20b, b98e03e4, 17ea0812, af12654c, dc9813c2, 09370439, b15d20fe, cf15b8c0, bd860ef5, dcec5d85, fef17899, 12889a60, 0981b4e5, 42beb860, a733e1b6, 9ed24a81, f0d5e0ac, 74510443, b283d3cb, a649b12a, 996c12e4, e2a0633c, e59cf2c1, d1d90693 | Mac engine -16..-27, page/profile/permission crashes, DevTools, menus, focus, downloads, screenshot hosts, dialogs/print | Chromium-engine row (`PageDialogPlacement`, `PageDialogs.swift`, `PageHostWindows.swift`, `EmbeddedDevTools.swift`); Windows remains stock CEF, so these native fixes are not implied there. ➖ |
| dbcfa585, 11f07f90, 614c1dfb | Across-space recent switching; splits count as one tab/card | Switcher/sidebar rows (`RecentTabOrder`, `SwitcherSplitLayout`, `recentTabAllSpaces`, `recentTabAllSpacesBackward`); shared order, Windows grouped cards/all-space commands still missing. 🟡 |
| 3823ea61 | Right-hand sidebar | New sidebar-side row (`SidebarSide`); Windows docks left. ❌ |
| 85966832, 051d458e, e1fad540, 720f5eda, e236fe10, 967497bd | Stable/New feeds, warning clicks, promotion/rollback and counts | Updater row (`UpdateChannel`, `DialogClick.swift`); Windows updater absent. ➖ |
| 4d786416, 0da8088e | Light material and muted space palette | Theme row (`SpaceTheme`, `CardVeil`); shared palette, Windows visuals incomplete. 🟡 |
| 09bbc07d, 8de6853e | Rename-field key focus, locked scenarios | Rename row; Mac AppKit fix. Windows double-click/name-focus needs its PC follow-up. 🟡 |
| ee8938f8, 145444a1 | Import list dims unavailable browsers; Yab and Ardia | Import/onboarding rows (`ImportSourceList`, `YabImporter.swift`, `ArdiaImporter.swift`, `ImportTree.swift`); Windows discovery/UI gaps remain. 🟡 |
| 8733b8f3 | Spaces menu lists only existing named/icon spaces | New Spaces menu row (`SpacesMenuComposition`, `SpacesMenu.swift`, `SpaceMenuTitle.swift`); Windows has dock/keys, no native Spaces menu. ❌ |
| 402b5826, c410da9f, ab61185e, 894f9ca2, 1e2dd4f9, 1aea4168, a5c79d0e, f6b8a2f9, 11652908, 88a604ee, 44eb08e0, c6e75330, 73bd220d, d3a895a4 | iPhone sidebar formats, sheets, keyboard/bar, default browser, blockers, passkeys and recent-tab flicks | iPhone row (`MobileKeyboard`, `MobileSpacesSheet`, `MobileFavicons`, `MobileBlockerReadiness`); portable decisions serve the phone. ➖ |
| 98ea02df | Performance counters saturate rather than overflow | Performance row (`PerfProcessTable`, `PerfState`); shared protection, Windows samplers missing. 🟡 |
| 5086deb6, ea1dcd80 | Cross-display and empty-sidebar window drags | Window/sidebar rows (`WindowDragGesture.swift`); Windows page-top dragging exists, AppKit gestures do not port automatically. 🟡 |
| 845a7a09, 136594c0, 81359203, 5189ac7d | Native key priority, find focus, Secure Input release, no tooltips over sheets | Shortcut/find/tooltip rows; AppKit/secure-input fixes. Windows has its own native routing and needs direct checks. 🟡 |
| 11c7351f | Window managers move/resize Little Windows | Window-manager row (`WindowManagers`, `WindowManagers+AppKit.swift`); Mac AX adapter. ➖ |
| 400cc919, 0511d2ba, acaf35d0 | Sync closes stay closed, live addresses stay live; loaded store checks | Sync/switcher rows (`SidebarMerge`, `SettingsSync`); shared merge/order tests, Windows sync shell missing. 🟡 |
| 4ceba06b, a5a6b4d1, 86e6c82c, c03d5d31, a83cfe3e, ad6e7c7e, 6b33001c, 3b96bad2, 058595af, 5fc4143a, c285217c | Coverage, notarization/recovery, test/promise rules, crash locks, DRM/release/sponsor documentation and bytecode ignores | Build/release/test tooling, no new Windows capability. Upstream promises stay locked; Windows signing/installer remain. ➖ |
| 6c602824, 873735b6, a485f4d5 | Web Store/transient downloads do not hold guards or become ghosts | Downloads row (`DownloadList`, `DownloadHistory`); shared model changes, CEF callback behavior needs checking. 🟡 |
| 2ac5b26d, 0ffdeaa5 | Imported extension removed in Chrome settings stays removed | Extensions row (`ExtensionCopyRemovals`); Windows copy loader has not adopted policy. ❌ |
| 2933078c, e79c6ba8, 97a0eddc | Peek auto-hide toolbar and Escape even when page cancels it | Peek row; Windows native controls/key paths remain to check. 🟡 |
| a276dc62, 27c1e93f | Boost code editing, Arc wheel, Site Controls action and Zap slider | Boosts row (`BoostWheel`, `BoostZap`); Windows editor/injection absent. ❌ |
| bc1e4f2b, debd5621, 1b17dcb3, ebbe2eea, afa95707, 8cb4fb9c, 32544a23, e8ff166d, f33ed3e5 | Little Window DevTools/Back/swipe/focus, full-screen strip and fixed tones | Little Windows row (`BackToReferrer`, `LittleStripTones`); native Windows visual/navigation follow-ups remain. 🟡 |
| a6ae85b5, c43ab151, 7e0e2617 | Full split limit, optional eight panes and middle-click split | Split rows (`SplitPaneLimit`, `SplitDropProposal`); shared store limit, Windows Links switch/middle-click path absent. 🟡 |
| 7b9bd2ad | Drag a tab at sidebar edge to change space | Drag/drop row (`SidebarEdgeDrag`); Windows currently hovers dock icons only. ❌ |
| 8aee0370, 421bf98d | Agent face/cursor/Take Over pill and watched scrolling | Agents row (`MCPAgentPresence`, `AgentFace.swift`, `AgentPill.swift`); Windows MCP transport/UI absent. ❌ |
| e6dbd066, fc7082cb | Reload context menu and keyboard reveals hidden toolbar | Toolbar row (`ToolbarKeyboard`, `ToolbarAutoHide`); Windows normal toolbar absent. ❌ |
| a3b9ca3c, a8e8a310, 7e97a909, b117033b, c0609d3d, 8ba2428d, a195c0c0 | GitHub open-PR folders, Jira Cloud and SSO recovery with locked tests | Live-folder rows (`LiveFolderModel`); shared filters/models, Windows plugin runtime/folder UI absent. ❌ |
| e14b06b4, cec21dbb, fc32ae5c, 4b19f873 | Offscreen other-space rows/favorites/tips take no pointer | Sidebar/preview rows; AppKit hit testing/scenarios. Windows displays one list, so no Mac pager fix is implied. ➖ |
| 5cc8561a, 0c6c54c3 | Added block lists and kept copies, tested | Added-lists row (`CustomBlocklists`, `CustomBlocklist`, `BlockLists.swift`); Windows bundled list remains, custom-list shell absent. ❌ |
| add32130, 9ece8124, 264b8be5, 5d6081a6 | Floating sidebar holds popups/empty windows and correct shadow | Hidden-sidebar row (`FloatingSidebarKeepOut`, `SidebarPresentation`); Windows floating sidebar absent. ❌ |
| 66a8e707 | Easel capture delivery, menu/tools and tile hover | Easels/capture rows (`CaptureMenuLayout`, `EaselToolbar`, `EaselTileHover`); Windows canvas absent. ❌ |
| 74db1cec | New Window from full screen gets a macOS Space | Multiple-window row (`NewWindowPlacement`); subject says Windows but means Mac windows. Windows full-screen needs its own native check. ➖ |
| 520923c3, 6d7d193f | Optional background tabs below source; hidden-sidebar creation toast | Background-link row (`LinkTabPlacement`, `BackgroundTabToast`); Windows setting/toast integration missing. 🟡 |
| 2b5a11a2, 7ee4feca | Scroller keeps momentum; single preview hover; closed folder retains tab | Sidebar/folder rows (`ListKnobGate`, `FolderPreviewRows`); portable rules, Windows preview/layout work remains. 🟡 |
| efa3de10 | Daily install count independent of usage-sharing consent | Installation-count row (`InstallCheckIn`); released Mac only, no Windows service/check-in added. ➖ |
| b659963e | Loading bar top-middle across full-screen/hidden/edge-to-edge | Loading row (`LoadingIndicatorPlacement`); Windows loading bar absent. ❌ |

## Moving Mac code into CraCore

Code that decides something without a window, written once for both apps. In order of what
the next Windows PRs need:

1. The Mac's `SpaceListView.resolve` and `applyDrop`, the favorites slot drop and the dock's
   reorder can read `SidebarDropPlan` (written from them for Windows' sidebar drag), and `PageSplitDrop.drop` can call `SplitDrop.drop`.
2. The rest of `Services/Import/` (Firefox, Zen, Dia, extensions, credentials): replace `NSImage`
   with PNG `Data` and SQLite with a reader each app passes in. Arc's and Chromium's readers and
   `apply` moved in #35, tested on the Mac's fixtures by CraCore's `ImportTests`. The credential
   rows, the staged file's format and Windows' os_crypt moved in #36; the Mac's `CredentialImport`
   can switch to `PendingCredentials` and `ChromiumCredentialRows`.
3. `PageScript.swift`, `CraLog.swift`, `NativeMessagingHosts.swift`,
   `ExtensionProtocolReply.swift`, `SearchSuggestLoader.swift`: Foundation only today.
4. `EmojiCatalog+Data.swift`: data with no imports, for the space icon picker.
5. `AppDelegate.handleInternalURL`'s reading of cra:// links: `CraLink` (#31) reads them the
   same way; the Mac can switch over to it.
6. The domain list behind `CraContentBlocker.h` (a header both C++ bridges can include). The
   bookmarks writer moved to CraCore's `BookmarksExport` in #65.

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
| 001afb2 | Slow first response notice after 10 seconds, with Stop Loading (#256) | New slow-response row (`SlowResponseNotice`); Windows has it since [#57]. |
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
| f7b1ba4, f4ddb16, 9d8749d, afe4417 | CEF 156.0.27 (Chromium 156.0.8078.96); release and CEF-update tooling | Windows now pins stock 156.0.27+ga10dae3 on Chromium .88, with the official archive checksum and a full-version cache check. Its sole CEF change over .26 is the external-message-loop keep-alive fix for CEF #4353. The 19 Nov comparison passed docked/undocked DevTools closure and subsequent page input on both builds. After closing the last tab, .26 ignored new-page relaunches while .27 rendered the new page. The .27 Manage Spaces/options-menu exit had no new event or dump; the original long-session tab-drag shutdown AV was not independently reproduced and eliminated. A separate .26 run produced a XAML/UI Automation AV, retained for diagnosis. The Mac's custom Chromium .96 build still includes 11 security fixes over .88 and Cra's CEF patches (including H.264/AAC); stock Windows does not inherit them. 🟡 |
| 3e3a82b | Fingerprinting protection switch in Settings ▸ Privacy (a CEF patch) | Privacy pane row; Windows has no Privacy pane and the patch isn't in Windows' CEF. ❌ |
| 2b067f9, e2ba4eb, f2503d4, 7ad6b2f, f46364a | Space dock right-click opens the space menu (#339); floating and hidden sidebar reveal details (#341, #350) | Hidden-sidebar and space menu rows (`SpaceMenuLayout`, `SpaceMenuIcon.swift`, `FloatingSidebarGeometry`, now in CraCore upstream). Windows has no hidden sidebar yet. ❌ |
| ba67d78, 9a62558 | Edit the address in place in the sidebar instead of the command bar (#344) | `SidebarAddressEdit`; Windows has no sidebar address field option. ❌ |
| 50adbd4 | A screenshot app's pointer over a page picks the main window (#346) | Mac only (macOS screenshot picker): `WindowContentGrabber.swift`, `ScreenshotPick`. ➖ |
| 9ea5240 | 5-Second Previews: Arc Max hover cards on Apple Intelligence (#324) | Arc Max row (`LinkSummary`, `LinkSummaryCard`, `LinkSummaryService.swift`, `LinkSummaryPreview.swift`, `LinkSummaryShareImage.swift`); needs an on-device model on Windows. ❌ |
| 3d6548c | A double-click on a pinned tab's favicon goes back to the pinned URL (#345) | Pinned tab extras row (`PinnedIconClick`). ✅ [#68] |
| 241cc8c | One click adds Cra's MCP server to Claude Code, Cowork, Codex, Cursor and others | Agents row (`MCPAgentSetup`, `MCPAgentInstaller.swift`, `MCPAgentTiles.swift`); Windows has no Agents server yet. ❌ |
| b58b69d | The Library pushes the page past the window's edge instead of narrowing it (#340) | Library row; Windows still narrows the page. ❌ |
| 3a60bd3, 95f020f | chrome:// tabs open without their saved history (a crash at launch, #325) | Windows restores tabs through CraCore's store; the history guard is in the Mac's `BrowserManager.swift`. Check on the PC. |
| 5887873, 7143532, 0fdf7df, 4d2961d, 37efb05 | Page-top dragging: a 60 pt band, the page gets presses at once, under the toolbar too (#335, #363) | Page-top drag row (`PageTopDrag`, `PageWindowStart`, `PageWindowStart+AppKit.swift`). ❌ |
| d24295c, ad9fd40 | View Source opens the page's source in a new tab (#348) | `ViewSource`, `PageCommands.swift`; Windows PC-test follow-up routes page/frame source through the shared address policy into Cra, preserving its profile/window behavior; native main-window, frame-menu and Little Window checks passed; private/Peek checks remain. 🟡 |
| 60eb2c7 | DevTools in a Little Window and a Peek dock beside the page (#348) | DevTools row (`DevToolsPlaceholder`, `DevToolsWindowChrome.swift`); Windows docks DevTools in the browser window only. 🟡 |
| 5eca911 | The picked app icon stays in ⌘-Tab and the Dock (#319) | Mac only: `ChromiumDockTile.swift`. ➖ |
| 52e8ef7 | Extension icons from their 2x file; install prompts over Cra's window (#349) | Extensions rows (`ExtensionIcons`). ❌ |
| 9b6877e | Live folder plugins' helper sandbox profile (#353) | Mac only (macOS sandbox). ➖ |
| ba49acf, ebce13c, ea617f9 | Sync: later bundles apply by themselves; repairs (#352, #378) | Sync row; Windows has no sync. ❌ |
| 068df70, 5e02b46 | Extension windows over a full-screen Cra; two displays and full-screen Spaces (#351, #354) | Mac only (macOS Spaces). ➖ |
| e020f1d, d31a84f, 109c697, 9dd665f, b980028, 1f88af4 | Picked tabs: Arc's menu, Copy URLs, Share N Items; Share Folder… links; the "Send this Folder" warning (#356, #357) | Sidebar multi-selection row (`PickedTabsMenu`, `FolderShareLink`; its links are raw DEFLATE, which `RawDeflate` packs and reads off Apple platforms). Windows has no multi-selection. ❌ |
| 2a0ee52 | Switch to Light/Dark Mode turns the browser too (#362) | Website appearance row; Windows' Light and Dark turn its Settings and Site Control Center ([#62]). 🟡 |
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

Upstream sync #10 merged the 10 commits after b517a00 (ad76399 to 192b41e). One conflict:
`SidebarStore.recentTabs` (upstream's background-tab order, kept `public` with the fork's `window:`).

| Commit | What | Windows |
|---|---|---|
| ad76399 | Import offers Chrome and Firefox from their data alone, without the app installed | Mac's `BrowserSources.swift`. Windows' `WindowsImportSource` already offers a browser from its data. |
| 7cd69db, 4d9beb0 | Mute / Unmute on a favorite's menu; a muted tab stays quiet on its next page and after a relaunch (#387) | Mute row. ❌ |
| 5c6439a | A space's emoji keeps its bottom row when macOS clips labels (#399) | Mac only (`EmojiLabelFrame.swift`, AppKit text layout). ➖ |
| 915260b | Picked tabs: Open in Split View splits the picks (a test) (#386) | Sidebar multi-selection row. ❌ |
| ac12d60, 192b41e | Window managers move the whole window; window switchers list one window per Cra window (#391, #401) | Window switchers row (`SwitcherWindows`). ➖ |
| 1fd954f | Mouse back over the first space opens the Library, like the swipe (#233) | Mouse buttons row (`MouseButtonSpaceSwitch`). ❌ |
| 5a93a4c | A tab opened in the background is next on ⌃Tab (#394) | Recent-tab switcher row; the store order came with the sync. ❌ |
| ffd7de6 | Dark theme colours without the purple cast (#392) | Space theme editor row (`SpaceThemeVariants`, shared). Windows doesn't draw a theme's dark half yet, so nothing changes there. ❌ |

Upstream sync #11 merged the 14 commits after 192b41e (02d8f9a to 4967f24). Conflicts: `createSpace`
gained `iconImage` (kept `public`), `SpaceDock.swift`'s imports, and `test-browser-manager.sh`'s file
list (kept CraCore paths, added `MemoryReclaim.swift`). `ToolbarAutoHide`'s CoreGraphics import is guarded.

| Commit | What | Windows |
|---|---|---|
| 02d8f9a, 904c9ca | Dark and Light keep the picked colour as it is (#392) | Space theme editor row (`SpaceThemeVariants`). ❌ |
| 2b39a45, dc6d118 | Ask on Page: Arc Max's find-or-ask card on ⌘F (#393) | Ask on Page row (`AskOnPage`); Apple Intelligence only. ➖ |
| 0b20792 | A PNG or SVG as a space's icon (#395) | Space menu row (`SpaceIcon`, `Space.iconImage`, `SpaceIconImage.swift`). ❌ |
| 546d50a | Picture in Picture resizes up to the full display (#388) | Picture in Picture row (`PictureInPictureLayout`). ❌ |
| ed26238 | ⌘S in a Peek toggles the browser window's sidebar (#402) | Peek row. ❌ |
| 167c05a | Hide the toolbar until the pointer rests at the top (#405, not in Arc) | Toolbar row (`ToolbarAutoHide`). ❌ |
| dc4ed11 | MCP page_upload finds hidden file inputs | Agents row (`MCPUploadTarget`). ❌ |
| 39aa7bb, 4b0ba66 | Tab freezing spares WebSocket pages; closed tabs' memory goes back; five hidden tabs keep frames (#195) | Tabs and memory rows (`TabSleepPolicy`, `MemoryReclaim`, `HiddenFrameRelease`). ❌ |
| f13c956 | The downloaded update runs once hidden first | Auto-update row (`UpdatePrewarm`, `UpdatePrewarmer.swift`). ❌ |
| 21bee29, 4967f24 | Test copies' windows report visible; the speed bench (scripts/perf, docs/speed.md) | Nothing for Windows. |

Upstream sync #12 merged the 2 commits after 4967f24, with no conflicts.

| Commit | What | Windows |
|---|---|---|
| 2165ca1 | The update warm-up runs the helper apps too | Auto-update row (`UpdatePrewarm`). ❌ |
| 0b0b328 | A window manager's nil child window no longer crashes Cra (#391) | Mac accessibility (`DockedWindowAccessibility.swift`). ➖ |

Upstream sync #13 merged the 4 commits after 0b0b328; `Tests/test-browser-manager.sh` conflicted
(the fork's CraCore paths plus upstream's spare-page files).

| Commit | What | Windows |
|---|---|---|
| ae7afb5 | Speed journeys on a real sidebar and real sites | Mac perf scripts. ➖ |
| 935cca1 | Spare pages: a page made ahead for the next new tab (`SparePage`) | Spare pages row. ❌ |
| 4ad54a1 | A sidebar tab switches on the press, not the release (`SidebarRowPress.selectsOnPress`) | Sidebar rows. ❌ |
| f6a8736 | Space switches don't ask which window is under the pointer every frame | Mac only (AppKit hit testing). ➖ |

Upstream sync #14 merged the 16 commits after f6a8736 (55f5549 to 805a3b7). Conflicts: `SidebarStore`
(`clearToday(playing:)`, incognito guards on `exportSpace` and `setProfile`, kept `public`), the Mac's
`Importers.swift` (kept the fork's thin wrapper; CraCore's `ArcImporter.plan` takes `symbolExists`,
which the Mac answers with SF Symbols and Windows leaves false), `ShortcutsPane.swift` (the new Clear
Today description went into CraCore's `ShortcutDescriptions`) and the release checklist.

| Commit | What | Windows |
|---|---|---|
| f586c7f | Clear keeps the tab on screen and tabs playing sound (#406) | Pinned tabs and Today row (`TodayClear`). Windows passes no playing tabs yet. 🟡 |
| 115a201 | A link dragged in from a page or another app opens where it is let go (#419) | Drag and drop row (`SidebarLinkDrop`). ❌ |
| 305439a | An incognito space's menu has no Set Profile, Export or other space-only rows (#413) | Space menu row (`SpaceMenuLayout.sections(incognito:)`); Windows' menu already hides those, and the store now refuses them. ✅ |
| 272980a | Arc spaces with an Icon-tab glyph keep it (`ArcSpaceIcon`) | Import row; Windows draws no symbols yet. 🟡 |
| 426c345 | Instant Links (#409) | Instant Links row (`InstantLinks`); Apple Intelligence only. ➖ |
| 8429b73, 805a3b7 | Ask on Page: the question's dark card (#408), a follow-up's own answer (#417) | Ask on Page row. ➖ |
| 14b921f | A notification ding or Web Audio alone makes no player card (#411) | Now-playing row. ❌ |
| f3cf96e | Docked page and DevTools corners stay square on macOS 27 (#400) | Mac only (`ChromiumWindowCorners.swift`). ➖ |
| 3726f65 | Google services Cra never offers are off (optimization hints, AI history search, Gemini, Lens) | Chromium switches: Windows' `CraCEFWin.cpp` turns off the same features. ✅ |
| ff83e6e | Hidden tabs' frames go 2 s after a switch, a few windows at a time | Tabs and memory row (`HiddenFrameRelease`). ❌ |
| 55f5549, 729d671, b8de1e5, a531a29, b309829 | Speed notes, CEF 158 beta, framework linked at launch, release-note sponsors | Mac build and docs. ➖ |

Upstream sync #15 merged the 9 commits after 805a3b7 (308817d to fca4564), with no conflicts. The
new CraCore files' CoreGraphics imports are guarded.

| Commit | What | Windows |
|---|---|---|
| 3831d67 | A URL typed in ⌘T follows an Air Traffic Control route to a space (#421) | Air Traffic Control row: Windows' command bar does the same (`AppSettings.space(forTypedURL:)`). ✅ |
| c61aab7 | Right-click Back or Forward lists the tab's history (#416) | New Back and Forward history menu row (`BackForwardMenu`); Windows right-click menu in [#66]. 🟡 |
| 308817d, 4e0c10b, a4192fe | A link let go on a tab's middle opens nothing, on a folder's middle goes in the folder; Arc's insertion ring and line (#419) | Drag and drop row (`SidebarLinkDrop`). ❌ |
| 720ede7 | The find bar hangs under an auto-hiding toolbar (#418) | Find in page row (`FindBarPlacement`). Windows has no toolbar. ➖ |
| 30afd28 | Extensions see the page Cra has focused as the active tab (#414) | Toolbar and popups row (`ChromiumPageFocus.swift`); on Windows a popup's tabs.query doesn't see the Cra tab yet (patched CEF). ❌ |
| c9e0134 | A ⌃, ⌥ or F-key App Shortcut works while a page has the keyboard (#253) | Mac only (macOS App Shortcuts). ➖ |
| fca4564 | A space's emoji draws itself so macOS 27 doesn't cut it (#399) | Mac only (`EmojiLabel.swift`). ➖ |

Upstream sync #16 merged the 71 commits after fca4564 (5aa1df1 to 56be95d), most of them the
iPhone app. Conflicts: CLAUDE.md's layer table (both rows kept) and `addEmptyPane` (upstream's
`title:` parameter, kept public). The new CraCore files' CoreGraphics imports are guarded, and
`LiveFolderPluginArchive` is left out on iOS only, since its ZIP checks are tested on Linux and Windows.

| Commit | What | Windows |
|---|---|---|
| 60cf686, 2908a25 | Drag a sidebar tab or a page's link onto the page to split it (#419) | New page split drop row (`SplitDropProposal`). ❌ |
| 990cae0, 9cc14d3 | Ask on Page: quotes from the page, follow-ups, streaming; an answer that echoes the page is asked again (#417) | Ask on Page row. ➖ |
| 20de2af | Instant Links: a Google /goto result opens its own page | Instant Links row. ➖ |
| 56be95d and the other iPhone app commits | The iPhone app, its widgets and share extension, synced Spaces, CI's iPhone build | New iPhone app row (`Mobile*`). ➖ |
| 2d7e110, docs commits | One repo for both apps: README, contributor docs, issue forms | Docs only. ➖ |

Upstream sync #17 merged the 103 commits after 56be95d (5bb7467 to 72b25f2). Nearly all of them move the
Mac from CEF to Cra's own build of Chrome's framework ("the engine"). The only conflict was CLAUDE.md's
layer table, which keeps upstream's engine rows and the Windows rows. Windows stays on stock CEF
(`fetch-cef.sh` is unchanged).

| Commit | What | Windows |
|---|---|---|
| 5bb7467 to 72b25f2 (Chromium engine, Engine doc, fetch/publish-engine.sh, xbench) | The Mac runs on Chrome's framework with Cra's patches: Chrome 158, its own bars, pop-ups as tabs, keys to Cra, downloads, permissions, DevTools, Picture in Picture, Web Store installs | New Chromium engine row (`EngineVersion`). ➖ |
| 44cce5e | The sidebar player card follows the page's media session (#411) | Now-playing row (`PlayerCardSession`). ❌ |
| 2f5e3b0 | A Cra owns its data folder when no other process holds it (#299) | New data folder row (`DataFolderOwner`). ❌ |
| e402f77 | cra://open closes the command bar that waited for a new tab | cra:// row. The fix is for the engine, where no page window takes the bar's key. On CEF, the Mac before it and Windows (`openCraLink` activates the window, and the bar closes when it loses the front), the bar already went. ➖ |
| 8280b11, c33d3eb and the other engine bridge commits | The engine's page menu, infobars, favicons, find and zoom reach Cra as CEF's did | New Chrome bars row (`PageInfoBar`). Otherwise engine plumbing. ➖ |

Upstream sync #18 merged one commit after 72b25f2, with no conflicts.

| Commit | What | Windows |
|---|---|---|
| 4cf04e2 | The floating sidebar runs no pointer timer while the sidebar is anchored | Hidden and floating sidebar row; Windows has no floating sidebar yet. ❌ |

Upstream sync #19 merged two commits after 4cf04e2, with no conflicts.

| Commit | What | Windows |
|---|---|---|
| 11a2a55, 7fc0341 | The engine's hidden window's blank page makes no renderer (engine -9) | Chromium engine row: Mac only. ➖ |

Upstream sync #20 merged one commit after 7fc0341, with no conflicts.

| Commit | What | Windows |
|---|---|---|
| 335bb79 | xbench reads the URL back before Return, and gains a probe mode | Mac benchmark tooling. ➖ |

Upstream sync #21 merged one commit after 335bb79, with no conflicts.

| Commit | What | Windows |
|---|---|---|
| 0ea8123 | Theme grain: a pattern Core Animation tiles, not a drawn view | Mac drawing of the theme's grain (`ThemeNoise.swift`), in the theme row. Windows draws no grain yet. ➖ |

Upstream sync #22 merged 165 commits after 0ea8123, to 8cda780. Most are upstream's Arc Max work
(Varun's #440 to #444, landed as single commits) and its merge branches.

| Commit | What | Windows |
|---|---|---|
| 1b0634cc, a9baa45, 529308b, 15b125c, 5d4b15c, 52529b2 and the tidy-downloads branch | Tidy Downloads: Arc's prompt, suffix and clash rules, moves and undo keep the download's ownership (#441, #448) | Tidy Downloads row; `DownloadHistory.move(from:to:id:)` in CraCore now takes the entry's id. ➖ |
| d455cb4, 3681a95 and the tidy-tabs branch | Tidy Tabs: Arc's grouping prompt, stable group ids, fitted requests (#443) | Tidy Tabs row (`TidyTabsModel.swift`). ➖ |
| a3b22e8, f47c3ce and the tidy-titles branch | Tidy Tab Titles: Arc's two-name answer, fitted to the sidebar row (#444) | Tidy Tab Titles row. ➖ |
| dc7e3ef and the askonpage branch | Ask on Page: typed answers, whole quotes checked on the page (#440) | Ask on Page row (`AskOnPageContent`, `AskOnPagePrompt`). ➖ |
| 234639e, e47da6a and the previews branch | 5-Second Previews: optional summary, checked redirects, bounded share images (#442) | New 5-Second Previews row (`LinkSummaryShareBitmap`). ➖ |
| 2507db1, 205b937 | Search queries keep a literal plus sign (#447) | The search URL is built in CraCore's `SidebarModel`, which Windows shares. ✅ |
| 39615a1, a86b572, 11e4dec, a3c6789 | iPhone popups and store callbacks | iPhone only. ➖ |
| 5c074f6 | Pinning a tab uses the window it was asked from (`withPinningWindow`) | Store side, shared. Windows pins from its own window. ✅ |
| 64b20c0 | Import offers a browser macOS keeps from Cra, asking for Full Disk Access; Chromium import reads AccountBookmarks and every listed profile | Import rows; `ChromiumImport` in CraCore gained the account bookmarks and Local State profile list. 🟡 |
| 8cc7ac7 | The find bar goes with its tab (#454) | Find in page row; Windows to check that switching tabs hides and brings back the bar. 🟡 |
| f11c0eb, a4e67c2, eb6fd55 | Blocker fails blocked requests; engine -11 and -13 | Mac engine. ➖ |
| be0ee52, b41e8a3 | AppleScript lists every space's tabs, makes incognito windows (#427, #428) | AppleScript row (`AppleScriptTabOrder`). ➖ |
| 0ab17c2 | A Little Window closes back to the app it was opened over (#430) | Little Windows row (`LittleWindowReturn`). ❌ |
| 9f74e36 | Picture in Picture: Arc's Minimize and PiP glyph (#434) | Picture in Picture row. ❌ |
| 57fa3bf | Settings opens over a full-screen window (#431) | Mac window spaces. ➖ |
| e0b82e1 | Peek: a call holds the first close, Close becomes a red Confirm pill (#425) | Peek row (`PeekCloseConfirm`). ❌ |
| 609bc7f | Another window keeps the keys it took from the command bar (#429) | Command bar row (`CommandBarClosing`). 🟡 |
| 067918e, b87ce5f | One ⌘Q asks "Quit Cra?" once; full-screen windows reopen full screen (#426) | New quit row (`QuitRequests`, `ChromiumQuitCancel.swift`). ❌ |
| c7d2622 | Chrome's Settings and Extensions pages from incognito open in the normal window (#412) | Private windows row (`IncognitoPages`). Check on Windows. |
| 3a11ffc, f27aa5c, 319d0a0, 5fc2322, 79ddc8e, 12d5dab, bfdbacb | Notification icon, theme grain scale, engine updates, build signing, live folder plug-in errors, xbench docs | Mac build and engine. ➖ |
| 7d6b943, c2998e2 and the "remove" and docs commits | Test snapshots in sRGB, branch docs and selectors removed | Nothing for Windows. |
| c13a19c | Picture in Picture's hover controls stay inside the window's rounded corners (#463) | Picture in Picture row. ❌ |
| b165d96, 1875397, 6ad7cdb | Runaway pages: a hidden page whose process passes 8 GB sleeps (`PerfRunaway`, `TabSleepPolicy.runaway`) | Performance and tab sleeping rows. Windows' tab sleeping (#69) has the timer only. ❌ |
| 6c3f292 | Ask on Page matches a hyphen for an en dash | Ask on Page row. ➖ |
| 4234c1f | A double click on the sidebar's empty space opens the New Tab bar (#446) | Sidebar. Windows to do. ❌ |
| c0a4b86 | Traffic lights keep the system's spacing (#445) | Mac window buttons (`TrafficLightLayout`). ➖ |
| 1f0a1bb | Launch after deleting a profile no longer crashes (WebKit stores) | Mac WebKit data. ➖ |
| 67b40a4 | Site Control Center lists each extension once | Site Control Center row; Windows lists no extensions there yet. |
| 11784ca | Zen import draws favicons at favicon size | Mac import. ➖ |
| 46991d9, 0bdc493 | Agents: Stop ends one agent's session; 32 connections | Agents row. ❌ |
| 726403b | Little Window: hide the toolbar until needed (#435, `autoHideLittleWindowToolbar`) | Little Windows row; the setting is shared in `AppSettings`. ❌ |
| 114d317 | Cra listed in macOS' Default web browser menu (#452) | Default browser row: Mac `Info.plist`. ➖ |
| 0fbf85c | Theme pad keeps a dark colour dark, no + on greys (#455) | Theme row (`SpaceColorPresets`). |
| 67ffea8 | Tabs: Always keep these sites active (#458) | New keep-active row (`KeepActiveSites`). ❌ |
| 8cda780 | Hidden traffic lights wait outside the window (#449) | Mac window buttons (`TrafficLightLayout`). ➖ |

Upstream sync #24 merged 142 commits after d1d90693, to 41897831. Conflicts were the fork's usual
ones: `SidebarStore`, `SuggestionEngine` and `SiteControlCenter` live in CraCore (upstream's code
taken, its new API made `public`; `SuggestionEngine.watchSearchEngines` stays on the Mac as an
extension over the new `reloadEngines()`), `KeyBindingDefaults.mac` regenerated from upstream's list,
`ShortcutDescriptions` kept in CraCore.

| Commit | What | Windows |
|---|---|---|
| 1cd2fc57, 9e2ecc01, f5b4bcc8, 2c71729d, b53980b0, cc6e343f | Command bar at 5,000 tabs: byte scoring, index built as the bar opens, only shown rows finished, the whole archive searched (#614, #617) | Shared `SuggestionEngine`, `CommandBarScore`, `CommandBarRanking`: Windows gets them. ✅ |
| 147ff63a, ccffb972 | Archive keeps 10,000 tabs; bulk archiving in one pass (#614) | Shared store (`ArchiveLimit`, `archiveTabs`). ✅ |
| b3c498d0, 08a71d93 | Tab sleeping: 32 slept pages kept per window, 16 pages asked a pass (#616) | Tab sleeping row (`RetainedPageBudget`). ❌ |
| 385d8088, 47a5444e | Sidebar list rebuild speed (#618) | Mac AppKit list. ➖ |
| 4bb66dbb, 35bc7523 | Sync: unchanged looks encode nothing; changes written after 3 s (#598, #615) | Sync row (`SidebarStore.documentKey`). ❌ |
| da170a16 | View History (⌘Y) opens Chromium's History page (#590) | History row; Windows keeps Ctrl+H on the Archived Tabs. 🟡 |
| da45b31e, e33f5023 | ⇧⌘T brings back a closed pinned tab at its page; option to stay in the space (#566, #601) | New Restore Last Closed Tab row (`ReopenClosedTab`). 🟡 |
| 8e362eaa, 914375c5, 16de7203, 9495f8da, b0921136 | Arc's tab, favorite and split menus row for row; Duplicate in the background (#600, #387) | Store side shared; Windows' menus to compare with Arc's. 🟡 |
| a0c8d859, be77474b | Tabs menu: Arc's rows and groups (#622) | Mac menu bar. ➖ |
| 3ae377fc | New windows remember the sidebar's hidden state; ⌘W closes a window with no tab (#644) | Window row (`sidebarVisibleInNewWindows`); Windows has no hidden sidebar yet. ❌ |
| 4da70e63, 58c56468, 525020b6, 57840938 | Create a Space page, the "+" past the last space, 64 more space icons (#576, #564, PR #638) | Spaces row (`SpaceCreation`, `NewSpaceSwipe`, `SpaceStyleControls`). ❌ |
| 643ee524, b939e02a | Library swipe from a hidden sidebar (#565); Library button glyph motion (#608) | Library row (`LibraryGlyphMotion`). ❌ |
| 094470d7 | Downloads list stays open from the Library button (#575) | Downloads row (`DownloadsTrayHover`). ❌ |
| 66b82a97, 6909463f, c9d2e7ad, 9c1f3efc, 8ff12568 | Little Window: own find bar, links stay in it, browser window stays behind the other app (#577, #599, #607, #581) | Little Windows row (`LittleFindBar.swift`, `FindCommand`, `LittleWindowLinks`, `LittleWindowRaise`). ❌ |
| 3da92624 | A tab dropped on a pane of a full split replaces it (#419) | Drag and drop row (`addToSplit(replacing:)`). ❌ |
| dfc7809e, adc60064 | Toolbar colour from the page's corner (#629); reload menu per split pane | Toolbar row (`ToolbarSampler.swift`). ❌ |
| 5950e506 | ⌘W in video full screen leaves full screen (#636) | Window row (`PageFullscreenWindow`). ❌ |
| 6462a32c | "New Tab Created" toast opens the tab (#543) | Toasts row. ❌ |
| 849118c3, 4cc83fe9 | Recording dot pulses; shared tab ringed, "Share this tab instead" | Mute row (`RecordingDot`, `TabSharing`). ❌ |
| 1d32098f | Extension `chrome.action.openPopup()`; full screen and pointer lock notices | Extensions and Toasts rows (`ExclusiveAccessNotice`). ❌ |
| 01a099af, 236af275, a5792a68, 20031d58, 1ac13513 | Extension popups hang under their button; dialogs back over the window; about:blank windows; refused Web Store imports (#634, #578, #491) | Extensions rows. Check on Windows. |
| 7eb1a350, 163dfa04 | Easels: multiple selection, wrapping text (#580) | Easels row. ❌ |
| c3b01c8d, 9ed9d488, e9051c03, 1006e84b, b48e8d0c | Picture in Picture on WebKit pages, pinch resize, Dock not counted (#585, #573, #533) | Picture in Picture row. ❌ |
| 5d5ac240, 995fe2d7, be5dd4d1, ce02ed0d, fb926579, 5cac7889 | Protected media: Fandango at Home and YouTube ask per video (#588) | Mac only (Safari's engine). ➖ |
| 211fb846, 625ee08e, 3463e2eb, 45f68d54, a666edc2 | A video in a background tab waits until shown (#552, #597) | Windows to check with CEF's background tabs. |
| 94bc9426, 56f56737 | App addresses (todoist://) from the bar; a page's redirect to an app asks once (#604, #561) | App links row (`AppLinks`). ❌ |
| 5498fd8f | A site search just saved takes Tab in an open bar (#562) | Command bar row, shared. ✅ |
| d19b7dda, 6222e8c4, c64a72b8 | Added lists apply path and hiding rules; Reddit loads with blocking (#570, #586) | Added block lists and blocker rows (`FilterList`, `BlocklistRules`). ❌ |
| bf61107f, 216db5ea | Ask on Page refusals; Tidy Tabs keeps singletons loose (#584, #594) | Arc Max. ➖ |
| 655e1e02, dd2f2b2e | Live folders: SSO key, Azure DevOps (#521, #542) | Live folders row. ❌ |
| e5202b04 | Site Controls opened from a key hang from their button | Mac popover. ➖ |
| 46aa4040, e722c736 | Window coverage readout; LittleWindowRaise Mac-only | Test tooling and Mac window server. ➖ |
| e69b3eac | Dock menu: one row per window | Mac Dock (`WindowsMenuRows.swift`). ➖ |
| 4a57ff0b | MCP: `Cra --mcp` without stderr | Agents row. ❌ |
| 0caac82e, 713e1e78, 179cfeee, 45e45c68, accb31dd, fa9214e1, 2e464b70, 933bb0b7, 5deba169, a81fb2f5 | Engine on Chrome 159 and its fixes (#626, #630, #631) | Mac engine; Windows stays on stock CEF 156. ➖ |
| d5bc1b18, fceb74d3, 41bbc3e7, 7367ffe1, 5b66c9ba, ed2173ff, a7ed4664, 847498e1, 4efb6f0a, 6933986a, c1c0d2ac, 635490de | iPhone app | iPhone only (`Mobile*`). ➖ |
| bf517f33, 010c3246, 9c15abea, 1b2887a1, 54ac12ae, b7152806, 172ca0d0, 917d06ed, 38c72953, a35f0d9f, and the "Tests:"/"Locked test"/scenario commits | Releases, Nightly, test tooling, the web-features map | Nothing for Windows. |

Upstream sync #25 merged 15 commits after 41897831, to 15ae9afc. The one conflict was
`SidebarStore.recordVisit`, which now takes the visit's profile (#609); Windows passes it from the
page's tab or the Little Window's profile.

| Commits | What | Windows |
|---|---|---|
| c77e50d5 | Command bar suggests archive and history from the space's own profile (#609) | Command bar row; shared engine, Windows passes profiles. ✅ |
| a5e30f17 | Peek driven from the sidebar's address field (#648) | Peek row (`PeekAddress`). ❌ |
| fdbef123 | Add Split View brings an open tab into the split (#645) | Split View 1–4 row (`SplitPanePick`). ❌ |
| 2b63fb39 | Library page shortcuts toggle; download ••• on hover (#649) | Library row (`LibraryShortcut`). ❌ |
| 866f509f | Little Window ⌘W hands keys on; click raises (#646, #641) | Little Windows row (`LittleWindowReturn`). ❌ |
| bd6fe28f | See-through command bar in Dark mode (#502) | Search-suggestions notice row (`CommandBarTones`). ❌ |
| 2df0d224 | Endless, zooming Easel canvas (#580) | Easels row (`EaselCanvas`). ❌ |
| 9c4edb4e | No floating-sidebar flash leaving the Library (#635) | Hide the sidebar row (`FloatingSidebarStillPointer`). ❌ |
| 15ae9afc | See-through two- and three-colour themes (#596, #643) | Space theme editor row. ❌ |
| d2447924 | Dragged extension popups keep their place (#634) | Extension popups row; Mac window placement. ❌ |
| cdeb0b4d | .crx dropped on chrome://extensions (#593) | Extensions install row (`DebugFileDrop.swift`). ❌ |
| d91803ad | Engine 159: HTTPS-only allows the local network (#625) | Mac engine; Windows stays on stock CEF 156. ➖ |
| 16dd1659, 071aac9c | iPhone search | iPhone only (`Mobile*`). ➖ |
| 4e318e3f | Tampermonkey popup buttons locked (#653) | Test tooling. Nothing for Windows. |

Upstream sync #26 merged 16 commits after 15ae9afc, to 53322240. Conflicts: `SidebarStore`'s
incognito profile (#620, upstream's code taken and made `public`), the Mac key list (`pasteAndGo`
added to `KeyBindingDefaults.mac` and `ShortcutDescriptions`; the regenerated list matches upstream's
exactly) and `Tests/test-browser-manager.sh`.

| Commits | What | Windows |
|---|---|---|
| b5245aee | Paste and Go ⌥⌘V (#610) | Copy commands row (`PasteAndGo`). ❌ |
| 77b8c20a | The sidebar's address opens Arc's address panel (#663) | Command bar row (`SidebarAddressPanel`). ❌ |
| 02adb189 | Change Icon… with Arc's Emoji \| Icon picker (#640) | Favicons row (`TabCustomIcon`, `TabIconPicker.swift`). ❌ |
| 2128e392, 56dfffbb | Incognito follows the space's profile (#620) | Private windows row. ❌ |
| 6a769a55 | Little Window stays in front from Mission Control (#581) | Little Windows row (`LittleWindowActivation`, `WindowSpaces.swift`). ➖ |
| 1cccfeff | Theme presets place the second and third colour as Arc does (#632) | Space theme editor row (`SpaceColorPresets`). ❌ |
| 6039bb3e | Easel text takes a colour (#658) | Easels row (`EaselObjects`). ❌ |
| f7dff872 | Only View Downloads toggles the Library (#649) | Library row (`LibraryShortcut`). ❌ |
| 53322240, 31e90cbc | Engine 159: Boost tint leaves images; store copies install normally (#602, #660) | Mac engine; Windows stays on stock CEF 156. ➖ |
| d4efdf26, 8b68a0e3, 6b0ab370, ae468dc7 | iPhone (#656, #655, #657) | iPhone only (`MobileStatusBand`). ➖ |
| f879942b | Extension action across two profiles locked (#621) | Test tooling. Nothing for Windows. |

Upstream sync #27 merged 2 commits after 53322240, to bb167523, with no conflicts.

| Commits | What | Windows |
|---|---|---|
| bb167523 | Folders: Move to ▸ in the right-click menu, as in Arc (#662) | Folders row. The store's `moveTab` already moves a whole folder (CraCore); Windows' folder menu lacks Move to Space. ❌ |
| 62e2b2f3 | A real mouse drag moves an extension popup again (#664) | Extension popups row; Mac window placement. ➖ |

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
[#44]: https://github.com/vishnu597/cra-windows/pull/44
[#45]: https://github.com/vishnu597/cra-windows/pull/45
[#46]: https://github.com/vishnu597/cra-windows/pull/46
[#47]: https://github.com/vishnu597/cra-windows/pull/47
[#48]: https://github.com/vishnu597/cra-windows/pull/48
[#49]: https://github.com/vishnu597/cra-windows/pull/49
[#50]: https://github.com/vishnu597/cra-windows/pull/50
[#51]: https://github.com/vishnu597/cra-windows/pull/51
[#52]: https://github.com/vishnu597/cra-windows/pull/52
[#53]: https://github.com/vishnu597/cra-windows/pull/53
[#54]: https://github.com/vishnu597/cra-windows/pull/54
[#55]: https://github.com/vishnu597/cra-windows/pull/55
[#56]: https://github.com/vishnu597/cra-windows/pull/56
[#57]: https://github.com/vishnu597/cra-windows/pull/57
[#58]: https://github.com/vishnu597/cra-windows/pull/58
[#59]: https://github.com/vishnu597/cra-windows/pull/59
[#60]: https://github.com/vishnu597/cra-windows/pull/60
[#61]: https://github.com/vishnu597/cra-windows/pull/61
[#62]: https://github.com/vishnu597/cra-windows/pull/62
[#63]: https://github.com/vishnu597/cra-windows/pull/63
[#64]: https://github.com/vishnu597/cra-windows/pull/64
[#65]: https://github.com/vishnu597/cra-windows/pull/65
[#66]: https://github.com/vishnu597/cra-windows/pull/66
[#67]: https://github.com/vishnu597/cra-windows/pull/67
[#68]: https://github.com/vishnu597/cra-windows/pull/68
[#69]: https://github.com/vishnu597/cra-windows/pull/69
[#70]: https://github.com/vishnu597/cra-windows/pull/70
[#72]: https://github.com/vishnu597/cra-windows/pull/72
[#82]: https://github.com/vishnu597/cra-windows/pull/82
[#83]: https://github.com/vishnu597/cra-windows/pull/83
[#84]: https://github.com/vishnu597/cra-windows/pull/84
[#86]: https://github.com/vishnu597/cra-windows/pull/86
[#91]: https://github.com/vishnu597/cra-windows/pull/91
[#94]: https://github.com/vishnu597/cra-windows/pull/94
