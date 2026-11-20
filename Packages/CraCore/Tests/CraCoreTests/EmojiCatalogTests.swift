import CraCore
import Testing

/// The space icon picker's emoji, shared by the Mac and Windows pickers.
struct EmojiCatalogTests {
    /// Arc's eight category tabs, in its order, none empty.
    @Test
    func eightCategoriesInArcsOrder() {
        #expect(EmojiCatalog.categories.map(\.id) == ["smileys", "nature", "food", "activities", "travel", "objects", "symbols", "flags"])
        #expect(EmojiCatalog.categories.allSatisfy { !$0.entries.isEmpty })
        #expect(EmojiCatalog.categories.first?.symbol == "face.smiling")
        #expect(EmojiCatalog.all.first == .init(emoji: "😀", name: "grinning face"))
    }

    /// Every word must be in the name; an empty query finds nothing.
    @Test
    func searchNeedsEveryWord() {
        #expect(EmojiCatalog.search("").isEmpty)
        #expect(EmojiCatalog.search("grinning sweat").map(\.emoji) == ["😅"])
        #expect(EmojiCatalog.search("GRINNING FACE").contains { $0.emoji == "😀" })
    }

    /// The grid opens on the current emoji's row: the first emoji of its 8-wide row.
    @Test
    func opensOnTheCurrentRow() {
        #expect(EmojiCatalog.rowStart(of: "😀") == "😀")
        let ninth = EmojiCatalog.all[9].emoji
        #expect(EmojiCatalog.rowStart(of: ninth) == EmojiCatalog.all[8].emoji)
        #expect(EmojiCatalog.rowStart(of: "not an emoji") == nil)
    }
}
