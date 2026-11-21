import CraCEFWin
import CraCore
import Foundation

/// The docked sidebar's edge as a drag strip (the Mac's ResizeHandleView): an unseen window over
/// the edge, 4 DIPs into the sidebar and 4 into the page (`SidebarResizeHandle.strip`), drawn by
/// CraResizeStrip.cpp, that reports the drag as DIPs from where it began (+ wider) and its
/// smoothed speed.
@MainActor
final class SidebarEdge {
    var onBegin: () -> Void = {}
    var onResize: (_ translation: Double, _ speed: Double) -> Void = { _, _ in }
    var onEnd: () -> Void = {}
    /// Pixels a DIP, for the drag's translation.
    var scale = 1.0
    private(set) var dragging = false

    private final class Box {
        weak var owner: SidebarEdge?
    }

    private let box: Unmanaged<Box>
    private var strip: UInt = 0
    private var startX: Int32 = 0, lastX: Int32 = 0
    private var lastTime = 0.0, speed = 0.0

    init(owner: UInt) {
        box = Unmanaged.passRetained(Box())
        box.takeUnretainedValue().owner = self
        let dragged: CraStripDragged = { context, phase, x, seconds in
            guard let context else { return }
            let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
            // In the strip's own window procedure, on the main thread.
            MainActor.assumeIsolated { box.owner?.dragged(phase: Int(phase), x: x, at: seconds) }
        }
        strip = cra_resize_strip_create(owner, box.toOpaque(), dragged)
    }

    /// The strip at `x, y` (screen pixels), `width` × `height`; 0 wide hides it. Held still while
    /// a drag is on, even when the drag hides the sidebar (#287: the drag isn't lost).
    func place(x: Int32, y: Int32, width: Int32, height: Int32) {
        guard strip != 0, !dragging else { return }
        cra_resize_strip_place(strip, x, y, width, height)
    }

    func close() {
        guard strip != 0 else { return }
        cra_resize_strip_destroy(strip)
        strip = 0
        box.release()
    }

    private func dragged(phase: Int, x: Int32, at seconds: Double) {
        switch phase {
        case 0:
            dragging = true
            (startX, lastX, lastTime, speed) = (x, x, seconds, 0)
            onBegin()
        case 1:
            guard dragging else { return }
            let dx = Double(x - lastX) / scale
            speed = SidebarResizeHandle.smoothedSpeed(speed, dx: dx, dt: seconds - lastTime)
            (lastX, lastTime) = (x, seconds)
            onResize(Double(x - startX) / scale, speed)
        default:
            guard dragging else { return }
            dragging = false
            onEnd()
        }
    }
}
