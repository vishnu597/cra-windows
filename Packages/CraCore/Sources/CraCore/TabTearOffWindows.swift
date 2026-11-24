import Foundation

extension TabTearOff {
    /// `frame(size:droppedAt:visible:)` on Windows, in physical pixels with y down: `width` ×
    /// `height` centred on where the pointer let go, kept `inset` points (× `scale`) inside the
    /// monitor's work area, and shrunk to fit it.
    public static func frame(width: Double, height: Double, droppedAtX x: Double, y: Double, workArea a: WindowFrame,
                             scale: Double) -> WindowFrame {
        let i = Double(inset) * max(scale, 1)
        let room = WindowFrame(x: a.x + i, y: a.y + i, width: a.width - 2 * i, height: a.height - 2 * i)
        guard room.width > 0, room.height > 0 else { return WindowFrame(x: x, y: y, width: width, height: height) }
        let w = min(width, room.width), h = min(height, room.height)
        let left = min(max(x - w / 2, room.x), room.x + room.width - w)
        let top = min(max(y - h / 2, room.y), room.y + room.height - h)
        return WindowFrame(x: left.rounded(), y: top.rounded(), width: w.rounded(), height: h.rounded())
    }
}
