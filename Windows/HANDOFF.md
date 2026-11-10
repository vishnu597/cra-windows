# Handoff: the Windows port, as of 10 Nov 2026

This file hands the Windows port of Cra to the next coding agent (Codex). It says where the
work stands, the rules the owner set, how each piece of work is done and tested, what comes
next, and what we learned the hard way. Read it top to bottom once. After that, use it as a
checklist.

Read these next, in this order:

1. [`CLAUDE.md`](../CLAUDE.md): the upstream repo's layer rules. They are the agent rules for this
   repo whatever the agent's name; treat it as your `AGENTS.md`.
2. [`CONTRIBUTING.md`](../CONTRIBUTING.md), [`docs/testing.md`](../docs/testing.md),
   [`docs/reviewing.md`](../docs/reviewing.md) and [`docs/development.md`](../docs/development.md).
3. [`docs/windows.md`](../docs/windows.md): how the Windows app is built and why it is built that way.
4. [`Windows/PARITY.md`](PARITY.md): every Mac feature and its state on Windows.

---

## 1. Where things stand right now

| | |
|---|---|
| Fork (all work goes here) | https://github.com/vishnu597/cra-windows |
| Upstream (macOS only, read only) | https://github.com/VictorKildahl/cra |
| Fork `main` | `f8c0251` (PR #30 merged 8 Nov 2026) |
| Upstream merged into the fork through | `9161e2d` (on PR #31's branch); `f547bd8` on `main` |
| Upstream `main` today | `b4c20de`, **90 commits** past `9161e2d` (see section 8) |
| Open PR | **#31**: Air Traffic Control routes editor and `cra://` links. CI is green (7 of 7 checks). **Its PC test has not been run yet.** |
| PR #31 branch | `claude/project-thread-gk0b7m`, head `9e9ee5a` |
| PR #31 Windows build | Actions run **42498836788**, artifact `Cra-windows-x64` |

**Your first job:** run the PC test for PR #31 (section 7), fix what fails, get the owner's OK and
merge. Then run upstream sync #8 (section 8), then the next plan PR (section 9).

---

## 2. The project

### Goal

Cra is an open-source Arc replacement for macOS (Swift, AppKit and SwiftUI, Chromium through CEF).
This fork ports it to **Windows with full feature parity**, reusing as much Mac code as possible.
Arc for Windows is the reference for Windows-specific behaviour (keys, for example).

### The owner's rules

The owner is Vishnu (GitHub `vishnu597`). These rules come from them and are not up for debate:

- **No upstream contact.** Don't open PRs, issues or discussions on VictorKildahl/cra. All work
  stays on the fork. The owner will contact the upstream author themselves.
- **Keep the fork upstream-friendly**, so the port could one day fold back into the original repo:
  - Windows-only code lives in `Windows/` and `.github/workflows/windows.yml`. The fork's own
    `.github/workflows/upstream-drift.yml` is left out when folding back.
  - The macOS app stays untouched, except where a decision moves into CraCore. Then change it the
    way upstream would write it.
  - Keep PRs small, clean and self-contained.
- **Merge upstream `main` into the fork before starting each new PR** (section 5).
- **Reuse Mac logic.** A decision (model, file format, layout rule, policy) goes in
  `Packages/CraCore` once, with a test, and both apps call it. Windows code that repeats Mac logic
  instead of calling CraCore is a bug.
- **Keep the parity tracker current.** Update `Windows/PARITY.md` in every Windows PR and every
  upstream sync (section 5.4).
- **Follow Cra's own design references** for the Windows UI:
  [brand](https://crabrowser.app/brand) and [design notes](https://crabrowser.app/design-notes).
  To learn how a Mac feature behaves, read the code plus the
  [release notes](https://crabrowser.app/release-notes) and the
  [changelog](https://crabrowser.app/changelog). Brand colours: blue `#3f6df5`, green `#4fbe7e`,
  coral `#f0574f`, yellow `#f6c34a`, sand `#f2e3c4`, cobalt `#2f55f0`. The product name is "Cra".
- **The owner merges, or tells you to.** Every merge so far followed the owner's explicit OK,
  usually after a passing PC test. They often choose "merge on green CI and fold the leftover
  check into the next PC test". Ask; don't assume.
- **The PC is their working machine.** Ask before you take it over, and follow the safety rules
  in section 6.3 to the letter.

### Chosen stack (decided 1 Nov 2026)

- Keep the **CEF/Chromium** engine, with the same CEF version as the Mac (`fetch-deps.ps1` reads
  `scripts/fetch-cef.sh`). It uses Spotify's stock CEF build for now: no H.264/AAC and none of
  `scripts/cef-patches`.
- Rebuild the AppKit/SwiftUI UI (about 27k lines) in **Swift + WinUI 3**, through The Browser
  Company's Swift/WinRT projections (swift-winrt, swift-winui).
- Carry over the models, importers and services by moving them into **CraCore**, which already
  builds and tests on macOS, Linux and Windows.

The porting plan doc (with the audit and the Phase 2 PR order) is at
https://claude.ai/artifact/CRBJfFSSoc2NMyh513rzMJ. It may not be readable outside Claude.
Sections 9 and 10 below repeat everything still relevant from it.

---

## 3. Architecture

### Layers (from CLAUDE.md)

| Layer | Where | Imports |
|---|---|---|
| Core | `Packages/CraCore` | Foundation, CoreGraphics (guarded), Observation |
| Mac app | `Sources/Cra` | CraCore, AppKit, SwiftUI, CraCEF |
| Mac bridge | `Sources/CraCEF` | CEF (Objective-C++) |
| Windows app | `Windows/Sources/CraWin` | CraCore, WinUI and WinAppSDK (Swift/WinRT), CraCEFWin |
| Windows bridge | `Windows/Sources/CraCEFWin` | CEF (C++, behind the C header `include/CraCEFWin.h`) |
| Windows helper | `Windows/Sources/CraHelperWin` | CEF (the Chromium subprocess) |

CraCore never imports AppKit, Cocoa, SwiftUI, UIKit or CraCEF. Apple-only frameworks go behind
`#if canImport(...)`, and `scripts/lint.py` (`core-platform-import`) enforces it. Its public API is
`public`, because both apps are other packages.

### How the Windows app is built (details in `docs/windows.md`)

- **`HostWindow`** (`App/HostWindow.swift`): the browser window is not a WinUI `Window`. A
  Window's XAML bridge covers the whole client area, and while it covers a page no real click or
  wheel reaches the page. So `HostWindow` is an `AppWindow` with a `DesktopWindowXamlSource`
  island kept to the sidebar column. Pages are Win32 child windows beside it. A second island
  strip sits over the page area's top for the Developer Mode bar.
- **`MessageLoop`** (`App/MessageLoop.swift`): a custom run loop. swift-winui's default loop calls
  `ContentPreTranslateMessage` on every message, which steals keys from Chromium's `Chrome_*`
  windows. Ours skips it for those windows. It also hands `WM_HOTKEY` to `GlobalHotkey`.
- **CEF on the main thread**: `external_message_pump` sends Chromium's work to a message-only
  window, so every callback arrives on the main thread with no locks.
  `App/MainThread.swift`'s `onMain` asserts the main actor for C callbacks.
- **No Foundation RunLoop**: `Timer` and `RunLoop.main` never fire. Use `WinScheduler` (CraCore's
  `Scheduler` on DispatcherQueue timers) and `DispatcherQueue.tryEnqueue`.
- **Floating UI** (command bar, find bar, profile dialog): `UI/FloatingWindow.swift`, a
  borderless owned AppWindow with its own XAML island.
- **Peek**: a `LittleWindow` in peek mode, a HostWindow owned by the browser window. The veil,
  click catcher and round buttons are owned layered windows drawn with GDI+ in
  `CraCEFWin/CraOverlay.cpp`.
- **Data folder**: `%LOCALAPPDATA%\Cra`, holding the same file formats as the Mac's
  (`sidebar.json`, `settings.json`, `windows.json`, `keybindings.json`, `downloads.json`,
  `Favicons\`). See `App/WinPaths.swift`.
- **Keys**: `KeyBindingDefaults` (CraCore) has `.mac` and `.windows` tables. On Windows,
  `keybindings.json`'s `.control` bit means Ctrl and `.option` means Alt. `WinKeyBindings.shared`
  drives the page keys, the command bar and Settings ▸ Shortcuts.
- **Build**: `Windows/scripts/build.ps1` (fetches deps through `fetch-deps.ps1`, builds the WinUI
  projections, then SwiftPM, compiles `Windows/Resources/Cra.rc` and writes the icon and version
  into `Cra.exe` and `CraHelper.exe`). `Windows/Resources/app.manifest` (Windows 10 support,
  per-monitor DPI) must stay embedded in both executables, or the GPU process crashes and pages
  go black.

### Windows source map

```
Windows/Sources/CraWin/
  CraApp.swift                 app start, launch arguments, relaunch handler
  App/       HostWindow, MessageLoop, MainThread, WinScheduler, WinKeyBindings, GlobalHotkey,
             WinRegistry (+ LaunchAtLogin), DefaultBrowser, WindowIcon, WinShell, WinPaths, Names
  Browser/   BrowserWindow, WindowList, WebPage (CEF wrapper), CrashRecovery, Favicons,
             DeveloperBarView, PermissionPromptView
  CommandBar/ CommandBarView, WinCommands
  Find/      FindBarView
  Little/    LittleWindow (also Peek), LittleStripView
  Peek/      PeekBarView, PeekOverlays
  Profiles/  ProfileDialogView
  Settings/  SettingsWindow, SettingsPanes, ShortcutsPaneView, AirTrafficControlSheet (PR #31)
  Sidebar/   SidebarView, DownloadsTray, LibraryView
  SiteControl/ SiteControlCenterView
  UI/        Controls, FloatingWindow, Images, ToastView
Windows/Sources/CraCEFWin/   CraCEFWin.cpp (bridge), CraShell.cpp, CraOverlay.cpp,
                             CraImages.cpp (WIC), CraDownloadAnimation.cpp, include/CraCEFWin.h
Windows/Sources/CraHelperWin/main.swift   subprocess; CraRendererApp exposes window.__craReport
Windows/scripts/   build.ps1, fetch-deps.ps1, parity.py
```

---

## 4. Building, testing and CI

- **No Windows build on Linux.** Cloud agent containers run Linux. The owner's PC has **no** Swift
  toolchain, VS 2022 or CMake on PATH, so `build.ps1` can't run there either. **The Windows CI
  job is the only Windows build.** Its artifact `Cra-windows-x64` (the whole `Windows/build/Cra`
  folder) is what PC tests run.
- **CraCore runs anywhere Swift 6.1+ does:** `swift test --package-path Packages/CraCore`. (Our
  container's proxy blocked download.swift.org, so we relied on CI. Try installing Swift in
  yours.)
- **Python checks you can run anywhere:**
  - `python3 -I Windows/scripts/parity.py check --upstream upstream/main --base origin/main`
  - `python3 -I scripts/lint.py`
  - `python3 -I scripts/promises.py`
- **Mac checks:** `scripts/test.sh` is the full Mac gate (it needs macOS). CI runs it.

### CI jobs on a PR (all 7 should be green)

| Workflow | Job | Notes |
|---|---|---|
| `windows.yml` | CraCore on Windows, CraCore on Linux (85 % line coverage gate), **Build Cra for Windows** (uploads `Cra-windows-x64`) | about 6 min with a warm cache |
| `ci.yml` | Build Cra.app, Tests (macOS) | skipped by `paths-ignore` for changes only under `Windows/**`, `windows.yml` or `docs/windows.md` |
| `upstream-drift.yml` | Feature parity tracker (on PRs), drift (weekly, skipped on PRs) | |

### CI quirks

- **A red or grey macOS job with no runner** (it waits 15 min, then "not acquired by Runner…
  capacity constraints") is GitHub runner capacity, not code. There's no branch protection on
  main. macOS runners worked again from 6 Nov.
- **Windows "cancelled"** means a newer push to the same branch (`cancel-in-progress: true`).
- **Mac CI catches what Windows can't**:
  - Mac test scripts compile `Persistence.swift` with CraCore's files as one module, so don't
    move or rename Mac types into CraCore under names that clash.
  - `Tests/BrowserManagerSupport/AppServices.swift`'s stub store needs every `SidebarStore`
    method `BrowserManager` calls.
  - The Mac compiler can time out type-checking `@Test(arguments:)` tuple literals; give them
    explicit types.
- **Keep the WinUI step's flags in sync with `build.ps1`** (`-Xlinker /DEBUG`, no `-v`), or the
  projections rebuild every run (+12 min).
- The nightly macOS workflow fails on unchanged upstream code (scenarios, fuzz). Ignore it.

---

## 5. How each piece of work is done

### 5.1 The loop for every PR

1. **Sync upstream first** (5.2). If the sync is big, it is its own PR ("Upstream sync #N"),
   merged before the feature PR. A sync of a few commits can ride at the start of the feature
   PR, as in #31.
2. Branch from the fork's `main`. Use one branch per PR, e.g. `codex/<topic>`; past branches
   were `windows/*` and `claude/project-thread-*`.
3. **Move the decisions into CraCore first**, with tests, and make the Mac app read them. That's
   a separate commit, titled `CraCore: …`. Then write the Windows shell, in a commit titled
   `Windows: …`.
4. Update `Windows/PARITY.md`: the feature's row (status, PR link, CraCore types, what's left),
   then `python3 -I Windows/scripts/parity.py summary --write`.
5. Run lint, parity and promises locally (and CraCore tests if you have Swift). Push, then open
   the PR against the fork's `main`. **Never against upstream.**
6. Get CI green.
7. **PC test** (section 6) with the CI artifact. Fix what fails, then recheck only the failed
   steps.
8. Ask the owner whether to merge. Merge with a merge commit (that's what the fork's history
   uses), not squash.
9. **Follow-up on the same topic after a merge:** restart the branch from the new `main`. Don't
   stack commits on merged history, and **don't force-push** over shared history: start the
   branch fresh so every push is a fast-forward.
10. **Bug fixes** follow CLAUDE.md rule 6: write the test first and see it fail. If no test can
    reach the bug, move the decision into CraCore. Only what needs a real site, the GPU or a
    human eye becomes a PC-test step.

### 5.2 Upstream sync procedure

```sh
git remote add upstream https://github.com/VictorKildahl/cra.git   # once
git fetch upstream main
git checkout -b codex/upstream-sync-8 origin/main
git merge upstream/main          # merge, never rebase: keep upstream's history intact
# resolve conflicts (see 5.3), then:
python3 -I Windows/scripts/parity.py report --upstream upstream/main   # what to triage
```

After the merge, every time:

- **CraCore must still build on Linux and Windows.** Upstream adds files that `import CoreGraphics`
  unguarded, use Apple-only formatters, or use `CGAffineTransform` (there's a
  `CGAffineTransform+Portable` shim). Guard each with `#if canImport(CoreGraphics)` or a portable
  path, including in new **tests**.
- **CraCore API changes** break the Windows app. For example, `SiteSearch.color` became optional
  and `SuggestionEngine` takes an injected engine reader. Grep `Windows/` for every changed
  CraCore symbol.
- **Regenerate `KeyBindingDefaults.mac`** from upstream's `Sources/Cra/App/KeyBindings.swift`
  mechanically (`Shortcut` becomes `KeyChord`, `NSEvent.ModifierFlags` becomes
  `KeyChord.Modifiers`). Check first that the old list was identical. Then update
  `KeyBindingsTests`' Mac action count, currently `104 + 4 + 27`. Add new Windows-relevant
  actions to `.windows`, or to the "not on Windows yet" list.
- **`Tests/promises.lock`**: if upstream added `.bug` tests, run `scripts/promises.py --update`
  and say so in the commit.
- **PARITY.md**: add a row for every new Mac feature, file and command, triage the commits in
  "Waiting in upstream", and move the `<!-- upstream-reviewed: <sha> -->` marker to the newest
  upstream commit you read. `parity.py check` fails CI otherwise.
- Check that `fetch-cef.sh`'s CEF version still downloads for Windows (`fetch-deps.ps1` reads it).

### 5.3 Known conflict patterns

- **`SidebarStore.swift`, `JSONStore`, `SuggestionEngine.swift`** live in CraCore on the fork but
  are edited upstream. Take upstream's code, re-add `public`, and keep the fork's hooks
  (`CoreLog.note` / `CoreLog.time` / `CoreLog.count`).
- **Download history.** Upstream has a CraCore `DownloadList`. The fork's CraCore
  `DownloadHistory` wraps it with typealiases, the tray and library extensions, and
  `Entry(path:date:profile:)`. Upstream may still edit `Sources/Cra/Services/DownloadHistory.swift`,
  which the fork deleted (a modify/delete conflict). Carry upstream's change into the CraCore
  version.
- **`LibraryView.swift` (Mac)**: take upstream's file wholesale, minus its `LibraryPage` enum.
  `LibraryPage` stays in CraCore.
- **Mac Settings panes, `AirTrafficControlView`, `TabsPane`, `ShortcutsPane`**: the fork made
  them read CraCore's words and helpers. Take upstream's layout and keep the CraCore calls.
- **`PeekLayout.BarColors`** lives in `PeekBarColors.swift`, because upstream's
  `test-peek-dim-panel.sh` compiles `PeekLayout.swift` alone.
- **`AppDelegate.swift`, `BrowserManager.swift`, `MainWindowController.swift`,
  `LittleWindowController.swift`**: the fork only swapped Mac logic for CraCore calls (`ExternalLink`,
  `CraLink` and so on). Keep upstream's change and re-apply the call.

### 5.4 PR conventions

- PR body sections follow `.github/pull_request_template.md`: **What and why**, **How I tested
  it**. Say plainly what you couldn't build or run, and what the PC test still has to check.
- **Assign `vishnu597`** and request their review on each PR.
- Previous PRs started with a Claude attribution block and ended with a Claude Code footer. You
  don't need to copy those. Use your own tool's attribution, if any.
- Commit titles: `CraCore: …`, `Windows: …`, `Merge upstream main (<from>..<to>): …`. In the body,
  say why, and name an issue when a locked promise changes.
- Never put model names or secrets in commits or PRs.

---

## 6. PC testing

The owner's PC runs Windows 11 25H2 (build 26200). The repo clone is at
`C:\Users\Vishnu\Documents\Coding\cra-windows`. It has `gh` and
[agent-desktop](https://github.com/vercel-labs/agent-desktop) installed globally, for driving
and screenshotting Cra. It has an Iriun virtual webcam (useful for camera prompts) and runs
Bitdefender.

### 6.1 Who runs it

- **Codex running on the PC** (Codex CLI in PowerShell) can run the steps itself with
  `gh`, PowerShell and `agent-desktop`.
- **Codex in the cloud** can't reach the PC. Write the test steps for the owner, and wait for the
  results.

Either way, **ask the owner first** and have them leave the PC alone while it runs. A stray
click from a test once hit Outlook. If the owner starts using the PC mid-test, pause and wait for
them to say "continue".

### 6.2 Setup

```powershell
$dir = "$env:TEMP\cra-pr31"            # one folder per PR, under %TEMP%
gh run download 42498836788 -R vishnu597/cra-windows -n Cra-windows-x64 -D $dir
Get-Process Cra -ErrorAction SilentlyContinue | Stop-Process   # only with the owner's OK
& "$dir\Cra.exe"
```

- Always use the newest green Windows run for the PR's head commit:
  `gh run list -R vishnu597/cra-windows -b <branch> -w Windows`.
- **Bitdefender** once quarantined `Cra.exe` and `agent-desktop`. If the exe vanishes, ask the
  owner to add exclusions for `%TEMP%\cra*` and agent-desktop.
- Cra uses the owner's real data folder `%LOCALAPPDATA%\Cra`. **Back up `settings.json` and
  `sidebar.json` before a test that changes them, and restore them afterwards.**

### 6.3 Safety rules (mandatory)

1. **Before every key press or click, check that a Cra window is the foreground window, and the
   expected one** (the browser window, Settings, a Little Window, a Peek). If it isn't, **stop**
   and report. Never keep going.
   - On 5 Nov a recheck script kept sending Ctrl+N, Ctrl+Shift+W and clicks after Cra had quit.
     They landed in the Claude desktop app and in another browser (Aside).
   - Never run multi-round input loops without this per-step check.
2. **Ask before downloading** any test file on the PC.
3. **Never change the owner's default browser** or any system-wide setting.
4. For "another app" steps, use **Calculator**. Notepad restores the owner's open files. Close
   only the Calculator windows you opened, not every Calculator window.
5. Don't sign the owner out (a Default apps experiment would need sign-out, so it was never run).

### 6.4 agent-desktop quirks

- It is stateless and can't hold modifier keys.
- It can't send `Ctrl+Shift+=` by name: send raw VK `0xBB`.
- It can't send the comma key (for Ctrl+,): use a small keystroke script (`SendInput` from
  PowerShell), or open Settings from the command bar ("Settings…").
- Screenshots miss animations under about 500 ms.

### 6.5 Cleanup after every PC test

- Close Cra and delete the test tabs it created, or restore the backed-up `sidebar.json`. Restore
  `settings.json`.
- Delete crash dumps from the test in `%LOCALAPPDATA%\CrashDumps` (`Cra*.dmp`, `CraHelper*.dmp`).
- Remove registry keys the test created (for PR #31, see step 7.6).
- Delete `%TEMP%\cra-pr<N>` when the PR has merged.

---

## 7. NEXT: PC test for PR #31

### What PR #31 adds

PR #31 is PR 9b of the plan: https://github.com/vishnu597/cra-windows/pull/31

- **Upstream sync** to `9161e2d` (one Mac-only Library grid commit). The PARITY marker is
  `9161e2d`.
- **CraCore** (`CraLink.swift`, `LinkRouting.swift`):
  - `CraLink` reads `cra://` links the way the Mac's `AppDelegate.handleInternalURL` does:
    `commandbar?query=…&mode=edit`, `dismiss`, `open?url=…&space=<uuid>&background=1|little=1`,
    `action/<id>` and `navigate?url=…`.
  - `AirTrafficControl` holds the sheet's words and Arc's destination menu (Most Recent Space,
    each space, then Little Window after a separator), shows a route to a deleted space as Most
    Recent Space, and builds the "1 route" / "3 routes" summary.
  - The Mac's `AirTrafficControlView` and `TabsPane` read these. Tests: `CraLinkTests`, and new
    cases in `LinkRoutingTests`.
- **Windows: the sheet.** `Settings/AirTrafficControlSheet.swift`, opened from Settings ▸ Tabs ▸
  "Air Traffic Control…" (route count beside it). It's a 508×440 card over the dimmed Settings
  window with:
  - New Route
  - per route: an "Is equal to" / "Contains" menu, the URL field, a ⊖ remove button, and an
    "Open in" menu
  - Default (below the second hairline)

  Edits save straight to `settings.json`. Escape, ✕ or a click beside the card closes it.
- **Windows: `cra://` registration.** `App/DefaultBrowser.registerScheme()` registers the scheme
  under HKCU `Software\Classes\cra` on every launch. A link runs
  `Cra.exe --single-argument <link>` and reaches the running Cra through Chromium's process
  singleton.
- **Windows: link handling.** `Browser/WindowList.openCraLink`:
  - `commandbar`, `dismiss` and `open` (http and https only) work from any app
    (`ExternalLink.isUserFacing`).
  - `action` and `navigate` work only if Cra started with the environment variable
    `CRA_SCRIPTING_URLS=1`.
  - `key`, `import` and `debug` aren't done on Windows.
- Links from other apps go through Air Traffic Control: `WindowList.openExternal` uses
  `ExternalLink.target`, which checks the routes and then the default.

### Test plan

Run the setup in 6.2 with run **42498836788**. Back up `%LOCALAPPDATA%\Cra\settings.json` and
`sidebar.json`. The owner needs at least 2 spaces; make a test space if needed and delete it
afterwards. Take a screenshot at each step and check foreground before every input (6.3).

**A. The sheet**

1. Open Settings (command bar "Settings…" or Ctrl+,), then go to **Tabs**. Expect an
   "Air Traffic Control…" button with no count beside it (0 routes).
2. Click it. Expect the card centred over the dimmed Settings window, the title, New Route, the
   empty note ("Add a route to open matching links from other apps in a chosen space."), and
   Default at the bottom.
3. Click **New Route**. Expect a row: 🔗 URL [Contains ⌄] [field with the keyboard,
   placeholder `crabrowser.app`] ⊖, then "↳ Open in [Most Recent Space ⌄]".
4. Type `example.com`. Set the match to **Is equal to**, then back to **Contains**. Open the
   **Open in** menu. Expect Most Recent Space, each space (emoji and title), a separator, then
   Little Window. Pick the second space.
5. Add a second route `wikipedia.org` → **Little Window**. Add a third route and remove it
   with ⊖.
6. Press **Escape**. The sheet closes. Expect "2 routes" beside the button. Reopen it: both
   routes are still there. Close it with ✕. Reopen it and close it by clicking beside the card.
7. Check `settings.json` holds both routes. Close and reopen Settings: still "2 routes".
8. Tab key: focus cycles inside the card, not into the pane behind.

**B. Routes taking effect** (links from another app; Cra is running and its window is in front
or behind)

1. Run `& "$dir\Cra.exe" --single-argument https://example.com/`. Expect a new foreground tab in
   the **second space's** Today list, with that window switched to the space.
2. Run `& "$dir\Cra.exe" --single-argument https://en.wikipedia.org/wiki/Arc`. Expect a
   **Little Window**.
3. Run `& "$dir\Cra.exe" --single-argument https://crabrowser.app/`. No route matches, so it
   follows the default: a tab in the most recent space (or a Little Window if Settings ▸ Tabs
   "Links from other apps open in a Little Window" is on).
4. Delete the second space (or use a test space and delete that). The route's menu now shows
   **Most Recent Space**, and step B1 opens in the most recent space.

**C. `cra://` links from a terminal.** Start the commands from PowerShell, through the shell
handler, so the registration is tested.

1. `reg query HKCU\Software\Classes\cra /s` shows `URL:Cra`, `URL Protocol`, and
   `shell\open\command` = `"<path>\Cra.exe" --single-argument %1`.
2. `Start-Process "cra://commandbar?query=hello"`. Expect Cra in front with the New Tab command
   bar showing "hello".
3. `Start-Process "cra://commandbar?mode=edit"`. Expect the Ctrl+L bar (edit the current URL).
4. `Start-Process "cra://dismiss"`. Expect the command bar to close.
5. `Start-Process "cra://open?url=https://example.org/"`. Expect a new foreground tab in the
   space in use.
6. `Start-Process "cra://open?url=https://example.org/&space=<uuid of another space>"`. Take the
   uuid from `sidebar.json`. Expect the tab in that space.
7. `Start-Process "cra://open?url=https://example.org/&background=1"`. Expect an unread tab in
   the sidebar, with the page in front unchanged.
8. `Start-Process "cra://open?url=https://example.org/&little=1"`. Expect a Little Window.
9. **Refusals** (Cra started normally):
   - `Start-Process "cra://navigate?url=https://example.org/"` does nothing.
   - `Start-Process "cra://action/newTab"` does nothing.
   - `Start-Process "cra://open?url=file:///C:/Windows/win.ini"` does nothing.
10. **Scripting mode**: quit Cra, set `$env:CRA_SCRIPTING_URLS="1"`, start Cra from that shell,
    and run C9's `navigate` and `action/newTab` links with `& "$dir\Cra.exe" --single-argument
    <link>`. They now work. (`Start-Process` with a URL goes through the shell, which starts a
    new process without that variable. That only matters for a cold start.)
11. Run a `cra://` link while Cra is **not running**. Cra starts and acts on it.

**D. Pending checks carried from earlier PRs**

1. The taskbar button and title bar show the Cra icon, also for Little Windows and Settings
   (`WindowIcon`, from PR #29).
2. Settings ▸ General ▸ "Set Cra as Default". Cra is still not listed in Windows' Default apps:
   a known gap, just record it. **Don't pick Cra as default.**
3. Open an unstyled local page (an `.html` file with just `<h1>Test</h1>`, created in `$dir`) and
   an unstyled http page. In the PR #29 test, `file://` showed black text on dark grey `#1F1F1F`
   although CEF's background colour is white. Record what each shows.
4. Cosmetic: the focus ring on the focused Back button in Settings is clipped into a half circle.
   Check whether it's still clipped.

### Cleanup (step 7.6)

- Close Cra.
- Restore `settings.json` and `sidebar.json`.
- Delete crash dumps.
- Delete the `cra://` registration: `reg delete HKCU\Software\Classes\cra /f`.
- If "Set Cra as Default" was pressed, delete the default-browser registration (Cra re-creates it
  when that button is pressed):
  - `reg delete HKCU\Software\Classes\CraHTML /f`
  - `reg delete HKCU\Software\Clients\StartMenuInternet\Cra /f`
  - `reg delete HKCU\Software\RegisteredApplications /v Cra /f`
- Close only the Calculator windows you opened.

Fix what fails in the PR branch, following CLAUDE.md rule 6 (a test first wherever the decision
is reachable from CraCore). Recheck the failed steps on the new CI build. Then ask the owner
whether to merge. After the merge, set the Air Traffic Control and `cra://` rows in
`PARITY.md` to ✅ (or note gaps), in the next PR.

---

## 8. Then: upstream sync #8

As of 10 Nov 2026, upstream `main` (`b4c20de`) is **90 commits** past `9161e2d`. A trial merge
into PR #31's branch conflicts in 20 files:

- CraCore: `SidebarStore.swift`, `SuggestionEngine.swift`
- Mac app: `AppDelegate.swift`, `KeyBindings.swift`, `BrowserManager.swift`,
  `Services/DownloadHistory.swift` (modify/delete), `Services/GitHubLiveClient.swift` (deleted
  upstream, modified on the fork)
- Mac Settings: `AirTrafficControlView.swift`, `SettingsKit.swift`,
  `SettingsWindowController.swift`, `ShortcutsPane.swift`, `TabsPane.swift`
- Mac UI: `SiteControlCenter.swift`, `LittleWindowController.swift`,
  `MainWindowController.swift`
- Tests and scripts: `Tests/PolicyTests.swift`, `Tests/test-browser-manager.sh`,
  `scripts/fuzz.sh`, `scripts/test-policies.sh`, `scripts/test-store.sh`

Do it as its own PR right after #31 merges. Commits that touch Windows work directly:

- `692e524` **Air Traffic Control: a Little Window route can name its space (#258)**. This
  changes `LinkDestination`, which PR #31's sheet and `ExternalLink` use. Update the Windows
  sheet's menu and `openExternal`.
- `6a4e05a` `cra://open` with `background=1` leaves Cra behind the app in use. Mirror it in
  `WindowList.openCraLink`: don't call `activate()` for background opens.
- `664cc6a` / `31187f8`: live folders became JavaScript plugins, and **Agents in Cra** (a local MCP
  server). These are new PARITY rows. `GitHubLiveClient.swift` is deleted upstream, so drop it
  from PARITY's "Moving Mac code into CraCore" list.
- `cae2918`: **sync through iCloud or a folder**. A new row; the folder sync is portable.
- `ff99afd` / `2eb5877` / `0495029`: opt-in usage stats and crash reports. Check them against
  the "nothing leaves the Mac" rule in CONTRIBUTING, and add PARITY rows.
- `fe7810f` / `5fe9cd2`: tabs keep their back and forward history across relaunch; Back closes
  a link-opened tab. Check what lives in CraCore.
- Settings changes (`b4c20de`: every setting describes itself; `3d560c2` address bar position;
  `cab6d40` search only the current space; `7c98d46` start on a new tab; `2e8a659` Tab Cleanup
  90/180 days). The Windows panes read `SettingsPane`, so check the Windows Settings window
  still builds and shows the new rows (or list them in PARITY).
- Sidebar sizes (`46cfb2a`, `06d5380`: 164 pt minimum, snap to 228, drag shut under 82), the `+`
  menu (`895b0c5`), the command bar sizes (`3bd548d`): PARITY rows and Windows metrics.
- `e44ba8f`: downloads gained pause, resume and cancel, plus a row menu. The CraCore
  `DownloadHistory` and `DownloadList` merge comes up again here.

Run `parity.py report --upstream upstream/main` for the full list, triage it into PARITY's
"Waiting in upstream", and move the marker to `b4c20de` (or whatever is newest then).

---

## 9. Roadmap after that

### Phase 2 plan, in order

These are from the porting plan. Each one is a small PR, synced with upstream first and tested
on the PC before it merges.

| # | Plan PR | State |
|---|---|---|
| 1 | Split view | ✅ #11 |
| 2 | Settings window (General, Tabs) | ✅ #14 |
| 3 | Shortcuts pane | ✅ #15 |
| 4 | Permissions, Site Control Center, private windows | ✅ #17, #18 (with multiple windows) |
| 5 | Profiles | ✅ #19 |
| 6 | DevTools, Developer Mode bar | ✅ #20, #22 |
| 7 | Little Windows, Peek | ✅ #23, #24 to #26 |
| 8 | Library and archive | ✅ #27 (rail: Downloads and Archived Tabs; no Media, Easels or Boosts pages yet) |
| 9 | Air Traffic Control and system integration | 9a ✅ #29 (links from other apps, default browser registration, icon); **9b 🔜 #31** |
| 10 | **Import**: Chrome, Edge, Brave, Opera, Vivaldi, Arc for Windows, Dia; passwords through DPAPI (`CryptUnprotectData`) and Windows Credential Manager. Move the parsers in `Sources/Cra/Services/Import/` into CraCore first (replace `NSImage` with PNG `Data`, and `~/Library` paths with a passed-in root; keep the fixture tests in `Tests/Fixtures`). | next |
| 11 | **Onboarding**: the first-run flow, using the importers | |
| 12 | **Extensions, part 1**: Chrome Web Store installs, the extensions menu, toolbar buttons, popups | |
| 13 | **Extensions, part 2**: the Extensions pane, native messaging hosts | |
| 14 | **Privacy and Advanced panes** | |

### Big ❌ areas in PARITY.md not covered by the plan list

Pick these up between plan PRs, or after them. PARITY.md has the Mac files and CraCore types for
each.

- **Hide the sidebar and the floating sidebar.** Move `FloatingSidebarGeometry.swift` into
  CraCore in that PR; it's a CLAUDE.md known exception.
- **Toolbar** (optional, off by default), the loading bar, dragging the window from the page top
  (`PageTopDrag`).
- **Blank Window** and tab tear-off (needs drag and drop in the sidebar).
- **Sidebar**: Move Tab to Space N (no Windows chord yet; the owner's call), wheel and swipe
  between spaces (`WheelSpaceSwitch`), mouse buttons switch spaces, pinned-tab extras
  (`PinnedNavigation`), folder previews (`FolderPeek`), favorites layout and tile colours
  (`FavoritesLayout`), space rename and emoji picker (move `EmojiCatalog+Data.swift` to CraCore),
  live folders.
- **Command bar extras**: Alt+Return split, theme glow, and commands for
  `editSpace`/`newSpace`/`deleteSpace`/`clearToday`/`duplicateTab`/`newFolder`. Zoom, print and
  view source in `KeyBindingDefaults.windowsShortcuts`.
- **Arc's dialog sheet** for confirmations (`DialogActions`). Windows Delete Space currently
  deletes without confirming.
- Arc tooltips (`TooltipTones`), Mica or Acrylic sidebar, website appearance and theme data,
  "restore windows" setting, Stay On Top, Save Page As, Copy URL as Quote, clean Copy URL
  (`CleanURL`).
- Media (now playing, Picture in Picture), Easels, Boosts, favorite previews (Gmail, Calendar),
  tab sleeping (`TabSleepPolicy`), cookie banners.
- Release: installer, signing, auto-update, single-instance, notification-area icon
  (`MenuBarMode`'s counterpart).

### "Moving Mac code into CraCore" (from PARITY.md)

1. `FloatingSidebarGeometry.swift`
2. `Services/Import/` parsers
3. `PageScript.swift`, `CraLog.swift`, `NativeMessagingHosts.swift`,
   `ExtensionProtocolReply.swift`, `SearchSuggestLoader.swift` (and `GitHubLiveClient.swift`
   until upstream's deletion lands)
4. `EmojiCatalog+Data.swift`
5. The Mac's `AppDelegate.handleInternalURL` can switch over to `CraLink`
6. The bookmarks writer in `SidebarExport.swift`, and the content blocker's domain list
   (`CraContentBlocker.h`)

---

## 10. Known open bugs and follow-ups

- **Default apps**: Windows 11 25H2 doesn't list Cra in Settings ▸ Default apps, so "Set Cra as
  Default" lands on the general list.
  - Registry entries match Microsoft's docs and Chromium's.
  - Tried without luck: running from `%LOCALAPPDATA%\Programs`, a Start menu shortcut with
    AUMID, an Uninstall entry, `ApplicationCompany`, unquoted icons, no `URL Protocol`, icon
    plus VERSIONINFO.
  - Ideas left: the list refreshes only at sign-in; the exe is unsigned; a per-machine installer
    registration.
- **Unstyled pages**: an unstyled local page renders black text on dark grey `#1F1F1F`. Cause
  unknown (step D3).
- **Settings Back button**: its focus ring is clipped into a half circle.
- **Settings and profiles**: Settings drops behind the browser after Create Profile from
  Settings. Settings sidebar buttons and Developer Mode bar buttons lack UIA accessible names.
  Set Profile toggle items don't expose their checked state.
- **Developer Mode bar**: the Inspect glyph is a pointer, the Copy URL toast colour is off, and
  the split URL prompt lists a tab twice.
- **Downloads**: `DownloadLocation` doesn't handle Windows drive paths.
- **Peek**:
  - Hiding Chrome's download arrow was never confirmed on the PC (the animation is too fast for
    screenshots).
  - After Add To Split from a pinned tab, the first click into the new copy pane used to be
    ignored. Fixed in #25 by the WH_MOUSE hook; watch for regressions.
  - The grow-from-link animation (#204) is Mac only.
- **Focus**:
  - A window with no tabs right after launch takes no keys until clicked (XAML island focus).
  - Focus after switching into an empty space sometimes lands on the address field with a
    focus ring.
- **Delete Space** has no confirmation (waits for the dialog sheet).
- **Split view**: DevTools width in a split pane is Chrome's own behaviour; left as is.

---

## 11. Lessons and gotchas (Windows)

### Swift/WinRT

- **Weak captures of non-subclassed WinUI controls go nil.** A `TextBox()`, `Flyout()`,
  `CheckBox()` or `MenuFlyout()` made from Swift is only a wrapper. Once no Swift strong
  reference is left, it is freed and `[weak x]` is nil, although XAML still shows the control.
  Keep controls in a Swift array or property (see `AirTrafficControlSheet.kept`). A strong
  capture in the control's own handler leaks through a cycle.
- **The WinUI projection has no `ComboBoxItem`**: use `MenuFlyout` menus, as the Air Traffic
  Control sheet does.
- **Disabled WinUI buttons and `Grid.cornerRadius`** didn't round fills as expected. Use a `Border`
  capsule, and don't disable buttons that need their look.
- **XAML controls are created in `onLaunched`**, not in the `SwiftApplication` init (otherwise
  `RPC_E_WRONG_THREAD`).
- **XAML buttons use `ClickMode.press`**: the release is lost when focus moves from a page into
  the island.
- **Island focus**: clicking a page fires `LostFocus`, but XAML focus stays on a TextBox (its ×
  and selection remain). Keep fields read-only when not editing, and `select(0,0)`.
  - A view drawn by `refresh()` must be drawn inside its observation tracking, or it won't redraw
    (the Library bug).
  - `root.tapped` that nothing handled should give focus back, or Escape stops working (the
    Library rail).

### Win32

- In Swift's WinSDK, `GetCursorPos` and `GetWindowRect` return `Bool`, not `WindowsBool`.
- Hover in the downloads tray works from the pointer position, not from XAML enter and exit
  events.

### CEF

- The CEF wrapper is MSVC-built and the bridge is clang-built. `CraCEFWin.cpp` must empty
  `TRIVIAL_ABI` before CEF headers (a compile-time check guards it), or `CefRefPtr` arguments
  crash.
- **Closing**:
  - Close CEF pages on `AppWindow.closing`, before the window goes (exits used to be WinUI
    fail-fast `0xE0464645`).
  - Defer `finishClosing` out of `OnBeforeClose`.
  - Defer a window close requested from inside its own key handler through the dispatcher
    (Ctrl+Shift+W crash).
- **Chrome-style CEF runs its own commands** (Ctrl+T, N, H) for keys Cra doesn't consume, and
  opens a bare Chromium window. `CefCommandHandler::OnChromeCommand` has a blocklist.
- **Pages are created hidden**: strip `WS_VISIBLE` in Create.
- **Focus between pages**:
  - Chromium focuses a new browser itself. `BrowserWindow` ignores a new page's first unclicked
    focus within 2 s, and refreshes before activating so a stale page doesn't reselect its tab.
  - A `WH_MOUSE` thread hook in CraCEFWin reports every mouse press in a page through
    `focus_received`.
- **Cra's own page probes** report through `window.__craReport` (CraHelperWin's renderer), so
  nothing of Cra's shows in a page's console.
- **Chromium's crash recovery is off** (`CrashRecovery` and `ChromiumCrashState`). Otherwise
  Chromium reopens the session in a stock window.
- **Second launches** reach the running Cra through Chromium's process singleton
  (`OnAlreadyRunningAppRelaunch`). Links use `--single-argument`, so a link can't add switches.

### comctl32

- **Avoid comctl32 tooltips.** Cra loads comctl32 5.82 (there's no v6 manifest). `TOOLINFOW`
  needs `TTTOOLINFOW_V2_SIZE`, `TTF_SUBCLASS` sees no hover over layered windows, and tracking
  tooltips crashed inside comctl32. Peek's tips are an own GDI+ layered window.

### Global hotkeys

- `RegisterHotKey` for Ctrl+Alt+N. Skip chords that type a character on the current layout
  (AltGr+N is ń on Polish keyboards; `WinKeyboard.typesCharacter`).

### Registry and shell

- Write per-user (HKCU) entries only.
- Send `SHChangeNotify(SHCNE_ASSOCCHANGED)` after registering.
- Launch at login uses the user's Run key. Turning it on clears Task Manager's StartupApproved
  flag.

---

## 12. History of merged PRs

| PR | What |
|---|---|
| #1 | CraCore builds off Apple platforms, tested on Windows CI |
| #2 | Windows shell skeleton: a WinUI 3 window with one Chromium page (Phase 0 done) |
| #4 | `SidebarStore` moved into CraCore |
| #3 | The full CEF page bridge |
| #5 | Sidebar on the shared `SidebarStore` |
| #6 | Faster Windows CI, macOS CI skipped for Windows-only changes |
| #7 | Upstream sync #1 (34 commits), weekly drift check |
| #8, #9 | Command bar ranking (`SuggestionEngine`) into CraCore; Windows command bar |
| #10 | Find in page, the downloads list (Phase 1 done) |
| #11 | Split view |
| #12 | Favicons, download thumbnails, Chrome's download arrow hidden |
| #13 | Upstream sync #2 |
| #14 | Settings window (General, Tabs) |
| #15 | Shortcuts pane, key bindings into CraCore |
| #16 | Upstream sync (31 commits), CraCore portability fixes |
| #17 | Permission prompts, Site Control Center, toasts, captures |
| #18 | Upstream sync #3, multiple windows, private windows |
| #19 | Profiles |
| #20 | Docked DevTools |
| #21 | Feature parity tracker (`PARITY.md` and `parity.py`); Alt+1–9 go to space N |
| #22 | Developer Mode bar |
| #23 | Little Windows, global Ctrl+Alt+N |
| #24 | Peek |
| #25 | Upstream sync #5, first click into a new split pane (WH_MOUSE hook) |
| #26 | A Peek keeps the keyboard |
| #27 | The Library (Downloads, Archived Tabs) |
| #28 | Upstream sync #6 (Easels, Media, dialog sheet, Arc's menu items) |
| #29 | Links from other apps, default browser registration, Cra icon and version info |
| #30 | Upstream sync #7 (Boosts, favorite previews, Library, Peek, PiP; CEF 156.0.26) |
| #31 | **open**: Air Traffic Control editor and `cra://` links |

---

## 13. Links

- Fork: https://github.com/vishnu597/cra-windows; upstream: https://github.com/VictorKildahl/cra
- Parity tracker: [`Windows/PARITY.md`](PARITY.md); script: [`Windows/scripts/parity.py`](scripts/parity.py)
- Windows build doc: [`docs/windows.md`](../docs/windows.md)
- Cra site: [release notes](https://crabrowser.app/release-notes),
  [changelog](https://crabrowser.app/changelog), [brand](https://crabrowser.app/brand),
  [design notes](https://crabrowser.app/design-notes). Fetching them with curl can be blocked by
  sandbox proxies; a browser or web-fetch tool works.
- Arc measurements and behaviour: [`docs/arc-reverse-engineering.md`](../docs/arc-reverse-engineering.md),
  [`docs/arc-parity.md`](../docs/arc-parity.md)
