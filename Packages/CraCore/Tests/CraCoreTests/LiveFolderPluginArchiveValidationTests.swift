import CraCore
import Foundation
import Testing

/// ZIP-directory validation runs before a platform extractor is invoked.
struct LiveFolderPluginArchiveValidationTests {
    private func directory(name: String, kind: UInt32 = 0, size: UInt32 = 0) -> Data {
        func number(_ value: UInt32, _ count: Int) -> [UInt8] {
            (0..<count).map { UInt8((value >> ($0 * 8)) & 255) }
        }
        var entry = Data(repeating: 0, count: 46)
        entry.replaceSubrange(0..<4, with: number(0x02014b50, 4))
        entry.replaceSubrange(24..<28, with: number(size, 4))
        entry.replaceSubrange(28..<30, with: number(UInt32(name.utf8.count), 2))
        entry.replaceSubrange(38..<42, with: number(kind << 16, 4))
        entry.append(Data(name.utf8))
        var end = Data(repeating: 0, count: 22)
        end.replaceSubrange(0..<4, with: number(0x06054b50, 4))
        end.replaceSubrange(8..<10, with: number(1, 2))
        end.replaceSubrange(10..<12, with: number(1, 2))
        end.replaceSubrange(12..<16, with: number(UInt32(entry.count), 4))
        return entry + end
    }

    private func rejection(_ data: Data) throws -> LiveFolderPluginError? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("plugin.zip")
        try data.write(to: zip)
        do { _ = try LiveFolderPluginArchive(url: zip); return nil }
        catch let error as LiveFolderPluginError { return error }
    }

    @Test(arguments: ["../main.js", "/main.js", "a/../main.js", "a\\main.js", "-main.js"])
    func rejectsUnsafePathsBeforeExtraction(name: String) throws {
        #expect(try rejection(directory(name: name)) == .invalidManifest("Unsafe or duplicate ZIP entry: \(name)"))
    }

    @Test func rejectsLinksAndOversizedEntriesBeforeExtraction() throws {
        #expect(try rejection(directory(name: "link", kind: 0xa000)) == .invalidManifest("ZIP links and special files are not allowed"))
        #expect(try rejection(directory(name: "main.js", size: 4 * 1024 * 1024 + 1)) == .invalidManifest("Expanded plugin ZIP is too large"))
        #expect(try rejection(Data([0x50, 0x4b])) == .invalidManifest("Invalid plugin ZIP"))
    }
}
