import CraCore
import Testing

/// The favorite tile's Tile Color menu and tone, shared by the Mac and Windows sidebars.
struct FavoriteTileColorsTests {
    @Test func presetsKeepTheMenuOrder() {
        #expect(FavoriteTileColors.presets.count == 12)
        #expect(FavoriteTileColors.presets.first == .init(name: "White", hex: "#FFFFFF"))
        #expect(FavoriteTileColors.presets.last == .init(name: "Pink", hex: "#FF375F"))
        #expect(Set(FavoriteTileColors.presets.map(\.hex)).count == 12)
    }

    @Test func defaultIsCheckedWithNoColour() {
        let choices = FavoriteTileColors.choices(current: nil)
        #expect(choices.first == .init(title: "Default", hex: nil, checked: true))
        #expect(choices.count == 13)
        #expect(choices.dropFirst().allSatisfy { !$0.checked })
    }

    @Test func aPresetIsCheckedWhateverItsCase() {
        let choices = FavoriteTileColors.choices(current: "#0a84ff")
        #expect(choices.filter(\.checked).map(\.title) == ["Blue"])
        #expect(!choices.contains { $0.title == "Custom" })
    }

    @Test func anotherColourAddsCustom() {
        let choices = FavoriteTileColors.choices(current: "#123456")
        #expect(choices.last == .init(title: "Custom", hex: "#123456", checked: true))
        #expect(choices.filter(\.checked).count == 1)
    }

    @Test func toneFollowsTheTileThenTheSpace() {
        #expect(FavoriteTileColors.isDark(tileColor: "#000000", spaceIsDark: false))
        #expect(!FavoriteTileColors.isDark(tileColor: "#FFFFFF", spaceIsDark: true))
        #expect(!FavoriteTileColors.isDark(tileColor: "#FFD60A", spaceIsDark: true))
        #expect(FavoriteTileColors.isDark(tileColor: nil, spaceIsDark: true))
        #expect(!FavoriteTileColors.isDark(tileColor: "nonsense", spaceIsDark: false))
    }

    @Test func shadeOnlyWhileOpenOrHovered() {
        #expect(FavoriteTileColors.shade(dark: true, selected: false, hovered: false) == nil)
        #expect(FavoriteTileColors.shade(dark: true, selected: true, hovered: false).map { $0.white && $0.alpha == 0.12 } == true)
        #expect(FavoriteTileColors.shade(dark: false, selected: false, hovered: true).map { !$0.white && $0.alpha == 0.07 } == true)
    }

    @Test func hexIsUppercaseSixDigits() {
        #expect(FavoriteTileColors.hex(red: 10, green: 132, blue: 255) == "#0A84FF")
        #expect(FavoriteTileColors.hex(red: 0, green: 0, blue: 0) == "#000000")
    }

    @Test func fillLaysTheShadeOverTheColour() {
        #expect(FavoriteTileColors.fill(tileColor: nil, selected: true, hovered: false) == nil)
        #expect(FavoriteTileColors.fill(tileColor: "#0a84ff", selected: false, hovered: false) == "#0A84FF")
        // Black, open: 12 % white → 31.
        #expect(FavoriteTileColors.fill(tileColor: "#000000", selected: true, hovered: false) == "#1F1F1F")
        // White, hovered: 7 % black → 237.
        #expect(FavoriteTileColors.fill(tileColor: "#FFFFFF", selected: false, hovered: true) == "#EDEDED")
    }

    /// Other Color… on Windows opens the colour dialog on the tile's colour and keeps the pick as hex.
    @Test func otherColorRoundTripsThroughTheDialog() {
        #expect(FavoriteTileColors.dialogRGB(tileColor: nil) == -1)
        #expect(FavoriteTileColors.dialogRGB(tileColor: "not a colour") == -1)
        #expect(FavoriteTileColors.dialogRGB(tileColor: "#FF8000") == 0xFF8000)
        #expect(FavoriteTileColors.dialogRGB(tileColor: "#0a1b2c") == 0x0A1B2C)
        #expect(FavoriteTileColors.hex(rgb: 0x0A1B2C) == "#0A1B2C")
        #expect(FavoriteTileColors.hex(rgb: UInt32(FavoriteTileColors.dialogRGB(tileColor: "#5E8C31"))) == "#5E8C31")
    }
}
