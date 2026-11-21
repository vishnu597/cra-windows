import CraCore
import Testing

/// The sidebar edge's drag strip as Windows hit-tests and times it.
struct SidebarResizeHandleTests {
    @Test func stripStraddlesTheEdge() {
        let strip = SidebarResizeHandle.strip(sidebarWidth: 328)
        #expect(strip.x == 324 && strip.width == 8)
    }

    @Test func speedIsSmoothed() {
        // 10 pt in 0.1 s is 100 pt/s; from rest it reads half that.
        #expect(SidebarResizeHandle.smoothedSpeed(0, dx: 10, dt: 0.1) == 50)
        #expect(SidebarResizeHandle.smoothedSpeed(50, dx: 10, dt: 0.1) == 75)
        // Two events at the same time keep the last reading.
        #expect(SidebarResizeHandle.smoothedSpeed(40, dx: 10, dt: 0) == 40)
        // A slow drag stays under SidebarResize's 50 pt/s, so it snaps.
        var speed = 0.0
        for _ in 0..<10 { speed = SidebarResizeHandle.smoothedSpeed(speed, dx: 1, dt: 0.05) }
        #expect(speed < SidebarResize.snapMaxSpeed)
    }

    @Test func savedWidthIsHeldInArcsRange() {
        #expect(SidebarResizeHandle.restored(328) == 328)
        #expect(SidebarResizeHandle.restored(100) == SidebarWidth.minimum)
        #expect(SidebarResizeHandle.restored(900) == SidebarWidth.maximum)
        #expect(SidebarResizeHandle.restored(.nan) == WindowPrefs().sidebarWidth)
    }
}
