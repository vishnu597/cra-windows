import CraCore
import Foundation
import Testing

/// Firefox's and Zen's files, read the same on the Mac and on Windows (FirefoxImport, ZenImport):
/// LZ4 written by hand, profiles.ini, places.sqlite's rows and the session stores.
struct FirefoxImportTests {
    /// A mozLz4 file whose one LZ4 block holds `json` as literals only.
    static func mozLz4(_ json: String) -> Data {
        let bytes = Array(json.utf8)
        var out = Array("mozLz40\0".utf8)
        let n = bytes.count
        out += [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)]
        if n < 15 {
            out.append(UInt8(n << 4))
        } else {
            out.append(0xF0)
            var rest = n - 15
            while rest >= 255 { out.append(255); rest -= 255 }
            out.append(UInt8(rest))
        }
        return Data(out + bytes)
    }

    /// A profiles.ini saved as UTF-16 with a byte order mark (a Windows PC's, 22 Nov 2026) is
    /// read like Firefox's own UTF-8 one, so Firefox is offered for import.
    @Test func readsProfilesIniInUTF16AndUTF8() throws {
        let ini = "[Install308046B0AF4A39CB]\r\nDefault=Profiles/abc.default-release\r\n\r\n[Profile0]\r\nIsRelative=1\r\nPath=Profiles/abc.default-release\r\n"
        let le = Data([0xFF, 0xFE]) + ini.data(using: .utf16LittleEndian)!
        let be = Data([0xFE, 0xFF]) + ini.data(using: .utf16BigEndian)!
        let bom8 = Data([0xEF, 0xBB, 0xBF]) + Data(ini.utf8)
        for data in [le, be, bom8, Data(ini.utf8)] {
            #expect(FirefoxImport.iniText(data) == ini)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ff-ini-\(UUID().uuidString)", isDirectory: true)
        let profile = root.appendingPathComponent("Profiles/abc.default-release", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: profile.appendingPathComponent("places.sqlite"))
        try le.write(to: root.appendingPathComponent("profiles.ini"))
        #expect(FirefoxImport.defaultProfile(root: root)?.standardizedFileURL.path == profile.standardizedFileURL.path)
    }

    @Test func decodesLZ4Blocks() {
        // "abc", then a 9-byte match 3 back (a run over what it writes), then "XYZ".
        let block: [UInt8] = [0x35, 0x61, 0x62, 0x63, 0x03, 0x00, 0x30, 0x58, 0x59, 0x5A]
        let header = Array("mozLz40\0".utf8) + [15, 0, 0, 0]
        #expect(FirefoxImport.mozLz4(Data(header + block)).map { String(decoding: $0, as: UTF8.self) } == "abcabcabcabcXYZ")
        // Literal and match lengths past 15 take extra bytes (255 means another follows).
        let long = String(repeating: "x", count: 300)
        #expect(FirefoxImport.mozLz4(Self.mozLz4(long)).map { String(decoding: $0, as: UTF8.self) } == long)
        let run: [UInt8] = [0x1F, 0x61, 0x01, 0x00, 0x05]  // "a", then 15 + 5 + 4 more
        #expect(FirefoxImport.mozLz4(Data(Array("mozLz40\0".utf8) + [25, 0, 0, 0] + run)) == Data(repeating: 0x61, count: 25))
    }

    @Test func refusesDamagedLZ4() {
        let header = Array("mozLz40\0".utf8)
        #expect(FirefoxImport.mozLz4(Data("not lz4 at all".utf8)) == nil)
        #expect(FirefoxImport.mozLz4(Data(header + [4, 0, 0, 0, 0x40, 0x61, 0x62])) == nil, "literals past the end")
        #expect(FirefoxImport.mozLz4(Data(header + [8, 0, 0, 0, 0x14, 0x61, 0x05, 0x00])) == nil, "an offset before the start")
        #expect(FirefoxImport.mozLz4(Data(header + [9, 0, 0, 0, 0x30, 0x61, 0x62, 0x63])) == nil, "shorter than it says")
        #expect(FirefoxImport.mozLz4(Data(header + [2, 0, 0, 0, 0x30, 0x61, 0x62, 0x63])) == nil, "longer than it says")
    }

    @Test func picksTheDefaultProfile() {
        let root = URL(fileURLWithPath: "/R/Mozilla/Firefox", isDirectory: true)
        let ini = """
            [Profile1]
            Name=old
            IsRelative=1
            Path=Profiles/old.default

            [Profile0]
            Name=default-release
            IsRelative=1
            Path=Profiles/abc.default-release
            Default=1

            [Install308046B0AF4A39CB]
            Default=Profiles/abc.default-release
            """
        let every: (URL) -> Bool = { _ in true }
        #expect(FirefoxImport.defaultProfile(ini: ini, root: root, hasPlaces: every)?.lastPathComponent == "abc.default-release")
        // The install's profile gone: the one marked Default=1, else the first with data.
        let noInstall = ini.replacingOccurrences(of: "Default=Profiles/abc.default-release", with: "Default=Profiles/gone")
        #expect(FirefoxImport.defaultProfile(ini: noInstall, root: root) { !$0.path.contains("gone") }?.lastPathComponent == "abc.default-release")
        #expect(FirefoxImport.defaultProfile(ini: noInstall, root: root) { $0.path.contains("old") }?.lastPathComponent == "old.default")
        #expect(FirefoxImport.defaultProfile(ini: ini, root: root) { _ in false } == nil)
        // An absolute Windows path is not under the root.
        let windows = "[Profile0]\nIsRelative=0\nPath=D:\\Firefox\\work\n"
        #expect(FirefoxImport.defaultProfile(ini: windows, root: root, hasPlaces: every)?.path.hasPrefix("/R") == false)
    }

    static let bookmarkRows: [[String: Any]] = [
        ["id": Int64(1), "type": Int64(2), "parent": Int64(0), "title": "", "guid": "root________"],
        ["id": Int64(2), "type": Int64(2), "parent": Int64(1), "title": "menu", "guid": "menu________"],
        ["id": Int64(3), "type": Int64(2), "parent": Int64(1), "title": "toolbar", "guid": "toolbar_____"],
        ["id": Int64(4), "type": Int64(2), "parent": Int64(1), "title": "unfiled", "guid": "unfiled_____"],
        ["id": Int64(10), "type": Int64(1), "parent": Int64(3), "title": "", "guid": "a", "url": "https://docs.example", "ptitle": "Docs",
         "dateAdded": Int64(1_700_000_000_000_000)],
        ["id": Int64(11), "type": Int64(2), "parent": Int64(3), "title": "Reading", "guid": "b"],
        ["id": Int64(12), "type": Int64(1), "parent": Int64(11), "title": "Paper", "guid": "c", "url": "https://paper.example"],
        ["id": Int64(13), "type": Int64(1), "parent": Int64(11), "title": "Prefs", "guid": "d", "url": "about:preferences"],
        ["id": Int64(14), "type": Int64(2), "parent": Int64(3), "title": "Empty", "guid": "e"],
        ["id": Int64(20), "type": Int64(1), "parent": Int64(2), "title": "Menu one", "guid": "f", "url": "https://menu.example"],
    ]

    @Test func readsBookmarksFromPlacesRows() {
        let items = FirefoxImport.bookmarks(rows: Self.bookmarkRows)
        #expect(items.map(\.pageTitle) == ["Docs", "Reading", "Bookmarks Menu"], "toolbar first, empty folders and the unsorted folder left out")
        #expect(items[0].customTitle == nil && items[0].createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(items[1].isFolder && items[1].children.map(\.url) == ["https://paper.example"], "only web pages")
        #expect(items[2].children.map(\.customTitle) == ["Menu one"])
    }

    static let session = """
        {"windows":[{"tabs":[
          {"index":2,"entries":[{"url":"https://a.example","title":"A"},{"url":"https://b.example","title":"B"}]},
          {"entries":[{"url":"about:newtab"}]},
          {"index":9,"entries":[{"url":"https://c.example","title":"C"}]}
        ]},{"tabs":[{"index":1,"entries":[{"url":"http://d.example","title":"D"}]}]}]}
        """

    @Test func readsOpenTabsFromTheSessionStore() throws {
        let session = try #require(try JSONSerialization.jsonObject(with: Data(Self.session.utf8)) as? [String: Any])
        let tabs = FirefoxImport.openTabs(session: session)
        #expect(tabs.map(\.url) == ["https://b.example", "https://c.example", "http://d.example"], "each tab's current page, every window")
        let plan = FirefoxImport.plan(browser: "Firefox", bookmarks: [], openTabs: tabs)
        #expect(plan.spaces.map(\.title) == ["Firefox"] && plan.spaces[0].emoji == "🦊" && plan.spaces[0].today.count == 3)
        #expect(FirefoxImport.plan(browser: "Firefox", bookmarks: [], openTabs: []).spaces.isEmpty)
    }

    @Test func buildsZensSidebar() throws {
        let zen = """
            {"spaces":[{"uuid":"w","name":"Work","icon":"💼","position":2000},
                       {"uuid":"h","name":"","icon":"chrome://browser/skin/zen-icons/selectable/star.svg","position":1000,
                        "theme":{"gradientColors":[{"c":[255,0,128]}],"opacity":0.1,"texture":2}}],
             "folders":[{"id":"f","name":"Projects"},{"id":"s","name":"split","parentId":"f","splitViewGroup":true}],
             "tabs":[
               {"zenEssential":true,"entries":[{"url":"https://mail.example","title":"Mail"}]},
               {"zenEssential":"true","entries":[{"url":"https://mail.example","title":"Mail again"}]},
               {"pinned":true,"zenWorkspace":"w","zenStaticLabel":"Board","index":2,
                "_zenPinnedInitialState":{"entry":{"url":"https://board.example","title":"Board home"}},
                "entries":[{"url":"https://board.example"},{"url":"https://board.example/card/1","title":"Card"}]},
               {"zenWorkspace":"w","groupId":"s","entries":[{"url":"https://spec.example","title":"Spec"}]},
               {"zenWorkspace":"h","entries":[{"url":"https://news.example","title":"News"}]},
               {"zenWorkspace":"h","zenIsGlance":true,"entries":[{"url":"https://glance.example"}]}
             ]}
            """
        let root = try #require(try JSONSerialization.jsonObject(with: Data(zen.utf8)) as? [String: Any])
        let sidebar = ZenImport.sidebar(zenSessions: root, sessionStore: nil) { Issue.record("Zen's own file has the spaces"); return [] }
        let plan = ZenImport.plan(sidebar: sidebar, bookmarks: [ImportedItem(pageTitle: "Docs", url: "https://docs.example")])
        #expect(plan.source == "Zen" && plan.spaces.map(\.title) == ["Space", "Work"], "in Zen's order, unnamed ones called Space")
        #expect(plan.spaces.map(\.emoji) == ["🗂️", "💼"], "an icon path is no emoji")
        #expect(plan.spaces[0].theme?.colors == ["#FF0080", "#FF0080"] && plan.spaces[0].theme?.intensity == 0.3 && plan.spaces[0].theme?.noise == 1)
        #expect(plan.spaces.allSatisfy { $0.favorites.map(\.pageTitle) == ["Mail"] }, "Essentials once, in every space")
        let work = plan.spaces[1]
        #expect(work.pinned.map(\.customTitle) == ["Board", "Projects"])
        #expect(work.pinned[0].url == "https://board.example" && work.pinned[0].pageTitle == "Board home", "a pinned tab keeps where it was pinned")
        #expect(work.pinned[1].children.map(\.url) == ["https://spec.example"], "a split flattens into its folder")
        #expect(plan.spaces[0].today.map(\.url) == ["https://news.example"], "Glance tabs stay behind")
        #expect(plan.spaces[0].pinned.last?.pageTitle == "Bookmarks" && plan.spaces[0].pinned.last?.children.count == 1)
    }

    @Test func readsOlderZensSpacesFromPlaces() throws {
        let store = """
            {"windows":[{"tabs":[
              {"pinned":true,"zenSyncId":"1","zenWorkspace":"w","entries":[{"url":"https://a.example","title":"A"}]},
              {"index":1,"entries":[{"url":"https://b.example","title":"B"}]}]},
             {"tabs":[{"pinned":true,"zenSyncId":"1","zenWorkspace":"w","entries":[{"url":"https://a.example","title":"A"}]}]}]}
            """
        let session = try #require(try JSONSerialization.jsonObject(with: Data(store.utf8)) as? [String: Any])
        let sidebar = ZenImport.sidebar(zenSessions: nil, sessionStore: session) {
            [["uuid": "w", "name": "Old", "icon": "🌿", "position": Int64(1), "theme_colors": "[{\"c\":[0,0,255]}]", "theme_opacity": 0.8]]
        }
        #expect(sidebar.tabs.count == 2, "a pinned tab every window holds comes once")
        let plan = ZenImport.plan(sidebar: sidebar, bookmarks: [])
        #expect(plan.spaces.map(\.title) == ["Old"] && plan.spaces[0].theme?.accent == "#0000FF")
        #expect(plan.spaces[0].pinned.map(\.url) == ["https://a.example"] && plan.spaces[0].today.map(\.url) == ["https://b.example"])
    }

    @Test func windowsFindsFirefoxAndZenUnderAppData() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let folders = WindowsImportSource.Folders(local: root.appendingPathComponent("Local", isDirectory: true),
                                                  roaming: root.appendingPathComponent("Roaming", isDirectory: true))
        let firefox = folders.roaming.appendingPathComponent("Mozilla/Firefox", isDirectory: true)
        let profile = firefox.appendingPathComponent("Profiles/abc.default-release", isDirectory: true)
        try fm.createDirectory(at: profile.appendingPathComponent("sessionstore-backups"), withIntermediateDirectories: true)
        try Data("[Profile0]\nIsRelative=1\nPath=Profiles/abc.default-release\nDefault=1\n".utf8).write(to: firefox.appendingPathComponent("profiles.ini"))
        try Data().write(to: profile.appendingPathComponent("places.sqlite"))
        try Self.mozLz4(Self.session).write(to: profile.appendingPathComponent("sessionstore-backups/recovery.jsonlz4"))
        // Zen's folder without a profile is no source.
        try fm.createDirectory(at: folders.roaming.appendingPathComponent("zen", isDirectory: true), withIntermediateDirectories: true)

        let available = WindowsImportSource.available(in: folders)
        #expect(available.map(\.id) == ["firefox"])
        let source = try #require(available.first)
        #expect(source.detail(profiles: []) == "Bookmarks and open tabs")
        #expect(WindowsImportSource.all.first { $0.id == "zen" }?.detail(profiles: []) == "Spaces, Essentials and pinned tabs")
        #expect(WindowsImportSource.all.first { $0.id == "edge" }?.detail(profiles: ["Default", "Work"]) == "2 profiles: Default, Work")
        #expect(source.userData(in: folders) == nil && source.profiles(in: folders).isEmpty, "no Chromium passwords or extensions")
        var asked: [String] = []
        let plan = try source.plan(in: folders) { file, query in
            asked.append(file.lastPathComponent)
            return query == FirefoxImport.bookmarksQuery ? Self.bookmarkRows : []
        }
        #expect(asked == ["places.sqlite"])
        #expect(plan.spaces.map(\.title) == ["Firefox"])
        #expect(plan.spaces[0].pinned.map(\.pageTitle) == ["Docs", "Reading", "Bookmarks Menu"])
        #expect(plan.spaces[0].today.map(\.url) == ["https://b.example", "https://c.example", "http://d.example"])
    }
}
