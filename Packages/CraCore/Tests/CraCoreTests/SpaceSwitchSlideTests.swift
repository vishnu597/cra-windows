import CraCore
import Foundation
import Testing

/// A space switch slides the new space in on Arc's spring while the colours cross-fade (the Mac's pager).
struct SpaceSwitchSlideTests {
    @Test func theNewSpaceComesInFromItsSideOfTheDock() {
        #expect(SpaceSwitchSlide.direction(from: 0, to: 2) == 1)
        #expect(SpaceSwitchSlide.direction(from: 3, to: 1) == -1)
        #expect(SpaceSwitchSlide.direction(from: 1, to: 1) == 0)
        #expect(SpaceSwitchSlide.direction(from: nil, to: 1) == 0)
        #expect(SpaceSwitchSlide.direction(from: 1, to: nil) == 0)
    }

    @Test func itSettlesOnArcsSpringInAboutAFifthOfASecond() {
        let start = SpaceSwitchSlide.frame(at: 0, width: 300)
        #expect(start.offset == 1 && start.blend == 0 && !start.done)
        // Critically damped: always moving toward its place, never past it.
        var last = 1.0
        for ms in stride(from: 16, through: 400, by: 16) {
            let f = SpaceSwitchSlide.frame(at: Double(ms) / 1000, width: 300)
            #expect(f.offset <= last && f.offset >= 0)
            #expect(abs(f.offset + f.blend - 1) < 1e-9)
            last = f.offset
        }
        // Half way well inside the first 0.2 s, at rest within a second.
        #expect(SpaceSwitchSlide.frame(at: 0.1, width: 300).offset < 0.5)
        #expect(SpaceSwitchSlide.frame(at: 1, width: 300).done)
        #expect(SpaceSwitchSlide.frame(at: 1, width: 300).offset == 0)
    }

    @Test func coloursCrossFadeStopByStop() {
        let old = [RGB(0, 0, 0), RGB(1, 1, 1)]
        let new = [RGB(1, 0, 0), RGB(0, 0, 1)]
        #expect(SpaceSwitchSlide.colors(old, new, blend: 0) == old)
        #expect(SpaceSwitchSlide.colors(old, new, blend: 1) == new)
        let mid = SpaceSwitchSlide.colors(old, new, blend: 0.5)
        #expect(mid == [RGB(0.5, 0, 0), RGB(0.5, 0.5, 1)])
        // A one-colour space against a gradient: its colour holds for every stop.
        #expect(SpaceSwitchSlide.colors([RGB(0, 0, 0)], new, blend: 0.5) == [RGB(0.5, 0, 0), RGB(0, 0, 0.5)])
        #expect(SpaceSwitchSlide.colors([], new, blend: 0.3) == new)
    }
}
