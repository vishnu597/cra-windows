import CraCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// SF Symbols names (what CraCore's rows carry) as Segoe Fluent Icons glyphs, the font
/// FontIcon draws with on Windows 11 (Segoe MDL2 Assets, with the same code points, on 10).
enum WinGlyph {
    static func code(_ symbol: String) -> String {
        known(symbol) ?? "\u{E721}"  // magnifyingglass
    }

    /// The glyph for an SF Symbols name this table knows, nil for any other.
    static func known(_ symbol: String) -> String? {
        switch symbol {
        case "globe": return "\u{E774}"
        case "clock": return "\u{E81C}"
        case "command": return "\u{E756}"
        case "folder": return "\u{E8B7}"
        case "arrow.right.square": return "\u{E8AB}"
        case "gear": return "\u{E713}"
        case "tab": return "\u{E7C3}"
        case "space": return "\u{E8A9}"
        // The site control center's (the Mac's SF Symbols, in Segoe Fluent Icons).
        case "square.and.arrow.up": return "\u{E72D}"
        case "link": return "\u{E71B}"
        case "camera": return "\u{E722}"
        case "text.viewfinder": return "\u{E9A6}"
        case "lock.fill": return "\u{E72E}"
        case "lock.open.fill": return "\u{E785}"
        case "ellipsis": return "\u{E712}"
        case "slider.horizontal.3": return "\u{E9E9}"
        case "sidebar.left": return "\u{E90C}"  // DockLeft
        case "hammer.fill": return "\u{E90F}"
        case "shield.fill": return "\u{EA18}"
        case "gearshape.fill": return "\u{E713}"
        case "trash": return "\u{E74D}"
        // The Developer Mode bar's.
        case "terminal": return "\u{E756}"  // CommandPrompt
        case "scope": return "\u{E8B0}"  // SelectAll: a dashed box, like Chrome's inspect icon
        case "square.split.2x1": return "\u{E89A}"  // TwoPage
        // The Peek's.
        case "xmark": return "\u{E711}"  // Cancel
        case "arrow.up.left.and.arrow.down.right": return "\u{E740}"  // FullScreen
        case "arrow.left": return "\u{E72B}"  // Back
        case "arrow.right": return "\u{E72A}"  // Forward
        case "arrow.clockwise": return "\u{E72C}"  // Refresh
        // The Library's rail (Fluent has no filled versions of these).
        case "arrow.down.circle", "arrow.down.circle.fill": return "\u{E896}"  // Download
        case "archivebox", "archivebox.fill": return "\u{E7B8}"  // Archive
        case "square.on.square", "square.on.square.fill": return "\u{E8A9}"  // ViewAll
        // Extensions (the Site Control Center's tiles, Manage Extensions).
        case "puzzlepiece.extension", "puzzlepiece.extension.fill": return "\u{EA86}"  // Puzzle
        case "plus": return "\u{E710}"  // Add
        // Arc's Create a Space page: its Profile and Choose a Theme rows, and the (i) on a row.
        case "face.smiling": return "\u{E76E}"  // Emoji2
        case "paintbrush.fill": return "\u{E771}"  // Personalize
        case "info.circle": return "\u{E946}"  // Info
        // A tab's speaker (TabSound).
        case "speaker.wave.3": return "\u{E995}"  // Volume3
        case "speaker.slash": return "\u{E74F}"  // Mute
        // The space icon picker's Icon tab (SpaceIcon.pickerSymbols): the ones Segoe has.
        case "star.fill": return "\u{E735}"  // FavoriteStarFill
        case "heart.fill": return "\u{EB52}"  // HeartFill
        case "flag.fill": return "\u{E7C1}"  // Flag
        case "bolt.fill": return "\u{E945}"  // LightningBolt
        case "bell.fill": return "\u{EA8F}"  // Ringer
        case "lightbulb.fill": return "\u{EA80}"  // Lightbulb
        case "square.grid.2x2.fill": return "\u{F0E2}"  // GridView
        case "folder.fill": return "\u{E8B7}"  // Folder
        case "calendar": return "\u{E787}"  // Calendar
        case "envelope.fill": return "\u{E715}"  // Mail
        case "checkmark.square.fill": return "\u{E73A}"  // CheckboxComposite
        case "doc.fill": return "\u{E8A5}"  // Document
        case "book.fill": return "\u{E82D}"  // Dictionary
        case "ellipsis.bubble.fill": return "\u{E8BD}"  // Message
        case "person.2.fill": return "\u{E716}"  // People
        case "apple.terminal.fill": return "\u{E756}"  // CommandPrompt
        case "wrench.and.screwdriver.fill": return "\u{E90F}"  // Repair
        case "moon.fill": return "\u{E708}"  // QuietHours
        case "sun.max.fill": return "\u{E706}"  // Brightness
        case "globe.americas.fill": return "\u{E774}"  // Globe
        case "cloud.fill", "cloud": return "\u{E753}"  // Cloud
        case "basket.fill", "cart.fill": return "\u{E7BF}"  // Shop
        case "airplane": return "\u{E709}"  // Airplane
        case "music.note": return "\u{E8D6}"  // Audio
        case "paintpalette.fill": return "\u{E790}"  // Color
        case "video.fill": return "\u{E714}"  // Video
        case "chevron.left.forwardslash.chevron.right": return "\u{E943}"  // Code
        case "hand.thumbsup.fill": return "\u{E8E1}"  // Like
        case "house.fill": return "\u{E80F}"  // Home
        case "briefcase.fill": return "\u{E821}"  // Work
        case "creditcard.fill": return "\u{E8C7}"  // PaymentCard
        case "key.fill": return "\u{E8D7}"  // Permissions
        case "wifi": return "\u{E701}"  // Wifi
        case "desktopcomputer", "tv.fill": return "\u{E7F4}"  // TVMonitor
        case "laptopcomputer": return "\u{E7F8}"  // DeviceLaptopNoPic
        case "iphone": return "\u{E8EA}"  // CellPhone
        case "headphones": return "\u{E7F6}"  // Headphone
        case "camera.fill": return "\u{E722}"  // Camera
        case "photo.fill": return "\u{E91B}"  // Photo
        case "mic.fill": return "\u{E720}"  // Microphone
        case "speaker.wave.2.fill": return "\u{E767}"  // Volume
        case "gamecontroller.fill": return "\u{E7FC}"  // Game
        case "car.fill": return "\u{E804}"  // Car
        case "bus.fill": return "\u{E806}"  // Bus
        case "figure.walk": return "\u{E805}"  // Walk
        case "location.fill": return "\u{E81D}"  // Location
        case "tag.fill": return "\u{E8EC}"  // Tag
        case "paperplane.fill": return "\u{E724}"  // Send
        case "printer.fill": return "\u{E749}"  // Print
        case "scissors": return "\u{E8C6}"  // Cut
        case "pencil": return "\u{E70F}"  // Edit
        case "puzzlepiece.fill": return "\u{EA86}"  // Puzzle
        case "clock.fill": return "\u{E823}"  // Recent
        case "magnifyingglass": return "\u{E721}"  // Search
        // The sidebar's + creation menu.
        case "plus.rectangle.on.rectangle": return "\u{E8A9}"  // ViewAll, as spaces show elsewhere
        case "plus.rectangle": return "\u{E7C3}"  // Page
        case "rectangle.split.2x1": return "\u{E89A}"  // TwoPage
        default: return nil
        }
    }

    /// The glyph for a row: its symbol, else a page for tabs and a grid for spaces.
    static func symbol(for s: Suggestion) -> String {
        if let symbol = s.symbol { return symbol }
        switch s.kind {
        case .switchToTab, .archived: return "tab"
        case .switchSpace: return "space"
        default: return s.url == nil ? "magnifyingglass" : "globe"
        }
    }
}

/// The command bar's request to the search engine's suggest endpoint (SearchSuggestions decides
/// what is kept and shown): the Mac's SearchSuggestLoader on FoundationNetworking.
enum WinSuggestLoader {
    /// No cookies: the request says nothing about who is typing beyond the text itself.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.httpAdditionalHeaders = ["Accept-Language": SearchSuggestions.acceptLanguage()]
        return URLSession(configuration: c)
    }()

    /// The answer's body, nil unless the engine answered 200.
    @Sendable static func load(_ url: URL) async -> Data? {
        await withCheckedContinuation { (done: CheckedContinuation<Data?, Never>) in
            session.dataTask(with: url) { data, response, _ in
                done.resume(returning: (response as? HTTPURLResponse)?.statusCode == 200 ? data : nil)
            }.resume()
        }
    }
}
