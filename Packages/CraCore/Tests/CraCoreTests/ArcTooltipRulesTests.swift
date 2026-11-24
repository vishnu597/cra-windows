import CraCore
import Testing

/// Arc's hover tips as Windows follows them: timing, label split, placement, size and colours.
struct ArcTooltipRulesTests {
    @Test func tipWaitsForTheRestUnlessWarm() {
        #expect(ArcTooltipRules.delay(tipShowing: false, lastHiddenAt: nil, now: 10) == 1.6)
        #expect(ArcTooltipRules.delay(tipShowing: true, lastHiddenAt: nil, now: 10) == 0)
        // Moving from one tip to the next control shows its tip at once.
        #expect(ArcTooltipRules.delay(tipShowing: false, lastHiddenAt: 9.7, now: 10) == 0)
        #expect(ArcTooltipRules.delay(tipShowing: false, lastHiddenAt: 9.4, now: 10) == 1.6)
        #expect(ArcTooltipRules.delay(tipShowing: false, lastHiddenAt: nil, now: 10, idleDelay: 0) == 0)
    }

    @Test func labelSplitsIntoTextAndCaps() {
        #expect(ArcTooltipRules.split("Copy URL (⇧⌘C)") == ("Copy URL", ["⇧", "⌘", "C"]))
        #expect(ArcTooltipRules.split("Copy URL (Ctrl+Shift+C)") == ("Copy URL", ["Ctrl", "Shift", "C"]))
        #expect(ArcTooltipRules.split("Zoom In (Ctrl++)") == ("Zoom In", ["Ctrl", "+"]))
        #expect(ArcTooltipRules.split("Go Back (Alt+Left)") == ("Go Back", ["Alt", "Left"]))
        #expect(ArcTooltipRules.split("Exit the Library (Esc)") == ("Exit the Library", ["Esc"]))
        #expect(ArcTooltipRules.split("Reload (F5)") == ("Reload", ["F5"]))
        // Parentheses that aren't a shortcut stay in the text.
        #expect(ArcTooltipRules.split("Mute (2 tabs)") == ("Mute (2 tabs)", []))
        #expect(ArcTooltipRules.split("New Space") == ("New Space", []))
        #expect(ArcTooltipRules.split("A (Ctrl+Shift)") == ("A (Ctrl+Shift)", []))
    }

    @Test func tipHangsOffTheCornerAndStaysOnScreen() {
        let screen = (x: 0.0, y: 0.0, width: 1000.0, height: 800.0)
        let size = (width: 100.0, height: 28.0)
        let corner = ArcTooltipRules.origin(placement: .corner, centre: (200, 100), pointer: (0, 0), size: size, screen: screen)
        #expect(corner == (208, 107))
        let cursor = ArcTooltipRules.origin(placement: .cursor, centre: (200, 100), pointer: (150, 90), size: size, screen: screen)
        #expect(cursor == (163, 104))
        let above = ArcTooltipRules.origin(placement: .above, centre: (200, 100), pointer: (0, 0), size: size, screen: screen)
        #expect(above == (150, 100 - 19.75 - 28))
        let trailing = ArcTooltipRules.origin(placement: .trailing, centre: (200, 100), pointer: (0, 0), size: size, screen: screen)
        #expect(trailing == (219.5, 86))
        // At the right edge it slides in; at the bottom it goes above its control.
        let right = ArcTooltipRules.origin(placement: .corner, centre: (990, 100), pointer: (0, 0), size: size, screen: screen)
        #expect(right.x == 896)
        let bottom = ArcTooltipRules.origin(placement: .corner, centre: (200, 790), pointer: (0, 0), size: size, screen: screen)
        #expect(bottom.y == 790 - 7 - 28)
    }

    @Test func sizeFollowsArcsLabel() {
        let plain = ArcTooltipRules.Metrics.size(textWidth: 60, textHeight: 16, capWidths: [])
        #expect(plain == (80, 28))
        #expect(ArcTooltipRules.Metrics.cornerRadius(height: plain.height) == 14)
        let caps = ArcTooltipRules.Metrics.size(textWidth: 60, textHeight: 16, capWidths: [19, 19])
        #expect(caps == (10 + 60 + 6 + 19 + 3 + 19 + 10, 28))
        let wrapped = ArcTooltipRules.Metrics.size(textWidth: 400, textHeight: 32, capWidths: [])
        #expect(wrapped == (300, 44))
        #expect(ArcTooltipRules.Metrics.cornerRadius(height: wrapped.height) == 10)
        #expect(ArcTooltipRules.Metrics.capWidth(glyphWidth: 7, characters: 1) == 19)
        #expect(ArcTooltipRules.Metrics.capWidth(glyphWidth: 20, characters: 4) == 30)
    }

    @Test func coloursComeFromTheSpace() {
        let tones = TooltipTones(shadedDark: RGB(0.2, 0.3, 0.4))
        let colors = ArcTooltipRules.Colors(tones)
        #expect(colors.fill == tones.fill && colors.title == tones.title && colors.cap == tones.badge && colors.capGlyph == tones.ink)
        #expect(colors.capEdge == tones.badge.mixed(with: tones.ink, 0.5))
        #expect(colors.ring == tones.fill.mixed(with: .white, 0.1))
        #expect(ArcTooltipRules.Colors.little.fill == RGB(10 / 255, 13 / 255, 75 / 255))
    }

    /// A space icon's tip: sooner than a control's (Arc's ~0.62 s), with its profile in a pill between the
    /// name and the caps, as the Mac's ArcTooltipLabel lays it out.
    @Test func spaceIconTipsComeSoonerWithAProfilePill() {
        #expect(ArcTooltipRules.idleDelay(for: .above) == 0.55)
        #expect(ArcTooltipRules.idleDelay(for: .corner) == 1.6)
        #expect(ArcTooltipRules.idleDelay(for: .trailing) == 1.6)
        let M = ArcTooltipRules.Metrics.self
        // The pill: 6 + 14 avatar + 3 + the name + 6.
        #expect(M.pillWidth(nameWidth: 40.2) == 70)
        // "Work", the pill and Alt 1: 10 + text + 6 + pill + 6 + caps + 10.
        let caps = [M.capWidth(glyphWidth: 18, characters: 3), M.cap]
        let plain = M.size(textWidth: 30, textHeight: 16, capWidths: caps)
        let badged = M.size(textWidth: 30, textHeight: 16, capWidths: caps, pillWidth: 70)
        #expect(badged.width == plain.width + 6 + 70)
        #expect(badged.height == 28)
        // Without caps the pill ends 3 pt from the edge.
        let noKeys = M.size(textWidth: 30, textHeight: 16, capWidths: [], pillWidth: 70)
        #expect(noKeys.width == 10 + 30 + 6 + 70 + 3)
        #expect(M.pillX(textWidth: 30) == 46)
        // No pill is the same tip as before; a wrapped tip shows none.
        #expect(M.size(textWidth: 30, textHeight: 16, capWidths: caps, pillWidth: nil) == plain)
        let wrapped = M.size(textWidth: 400, textHeight: 45, capWidths: [])
        #expect(M.size(textWidth: 400, textHeight: 45, capWidths: [], pillWidth: 70) == wrapped)
    }
}
