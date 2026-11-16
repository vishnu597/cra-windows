import AppKit
import UniformTypeIdentifiers

/// Settings ▸ Advanced ▸ Export…: asks where to save CraCore's `BookmarksExport` file.
enum SidebarExport {
    @MainActor
    static func bookmarksHTML(_ store: SidebarStore, date: Date = Date()) -> String {
        BookmarksExport.html(store, exportedOn: date.formatted(date: .long, time: .shortened))
    }

    /// Asks where to save, then writes the file. `window` hosts the panel as a sheet.
    @MainActor
    static func run(_ store: SidebarStore, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.title = "Export Spaces"
        panel.message = "Spaces, favorites and pinned tabs, as a bookmarks file any browser can import."
        panel.nameFieldStringValue = BookmarksExport.fileName(at: Date())
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        let html = bookmarksHTML(store)
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                DispatchQueue.main.async { AppDialog(error: error).runModal(over: window ?? AppDialog.parentWindow) }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: done) } else { done(panel.runModal()) }
    }
}
