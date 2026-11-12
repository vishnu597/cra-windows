import CraCore
import Foundation
import Testing

@MainActor
struct KeyBindingPluginTests {
    @Test func pluginCommandsKeepOverridesAcrossCatalogAndSyncChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = JSONStore<KeyBindingOverrides>("keybindings.json", in: directory)
        let folder = KeyAction(id: "newFolder", name: "New Folder", section: .spaces, shortcuts: [])
        let tab = KeyAction(id: "newTab", name: "New Tab", section: .file, shortcuts: [])
        let plugin = KeyAction(id: "plugin.feed", name: "Feed", section: .spaces, shortcuts: [])
        let registry = KeyBindingRegistry(defaults: [folder, tab], file: file)
        let chord = KeyChord("j", .command)
        registry.setShortcuts([chord], for: plugin.id)
        registry.setPluginActions([plugin])
        #expect(registry.actions.map(\.id) == [folder.id, plugin.id, tab.id])
        #expect(registry.action(plugin.id)?.shortcuts == [chord])
        registry.setPluginActions([])
        #expect(registry.action(plugin.id) == nil)
        registry.setPluginActions([plugin])
        #expect(registry.action(plugin.id)?.shortcuts == [chord], "an unloaded plugin's overrides are preserved")
        let synced = KeyChord("k", .control)
        file.saveNow([plugin.id: [synced], tab.id: [chord]])
        registry.reloadOverrides()
        #expect(registry.action(plugin.id)?.shortcuts == [synced])
        #expect(registry.action(tab.id)?.shortcuts == [chord])
    }
}
