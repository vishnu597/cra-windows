#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The user's own app icon (Settings ▸ General ▸ App icon, "Your own", GitHub #372), made from any
/// image the way the Mac's AppIconManager.iconPNG makes it: an opaque image (a photo, a logo on a
/// background) fills Cra's rounded tile; one with transparent corners (a finished app icon, a
/// cut-out logo) is scaled so its visible part fits the square, bigger or smaller than it came.
/// The Mac draws onto Apple's Dock grid; Windows' title bar, taskbar and Alt+Tab icons run edge
/// to edge, so there the square is the whole icon.
///
/// Pixels are 4 bytes each, rows from the top, alpha last and premultiplied (BGRA or RGBA alike).
public enum AppIconImage {
    /// Where Windows keeps the picked image's own bytes, in Cra's data folder.
    public static let fileName = "AppIcon.image"

    /// AppIcon.icns's tile: 14.3-unit corners on 64.
    public static let cornerRatio = 14.3 / 64

    /// Whether the image's corners are transparent, and its more-than-half-opaque part as
    /// fractions of its size (origin top left), nil when nothing is. Read on a 256 grid, as the Mac does.
    public struct Shape: Equatable {
        public let cutOut: Bool
        public let visible: CGRect?

        public init(cutOut: Bool, visible: CGRect?) {
            self.cutOut = cutOut
            self.visible = visible
        }
    }

    public static func shape(_ pixels: [UInt8], width: Int, height: Int) -> Shape {
        guard width > 0, height > 0, pixels.count >= width * height * 4 else { return Shape(cutOut: false, visible: nil) }
        let px = 256
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            let sx = min(width - 1, x * width / px), sy = min(height - 1, y * height / px)
            return pixels[(sy * width + sx) * 4 + 3]
        }
        let cutOut = [(1, 1), (px - 2, 1), (1, px - 2), (px - 2, px - 2)].allSatisfy { alpha($0.0, $0.1) < 26 }
        var minX = px, minY = px, maxX = -1, maxY = -1
        for y in 0..<px {
            for x in 0..<px where alpha(x, y) > 127 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return Shape(cutOut: cutOut, visible: nil) }
        let n = CGFloat(px)
        return Shape(cutOut: cutOut, visible: CGRect(x: CGFloat(minX) / n, y: CGFloat(minY) / n,
                                                     width: CGFloat(maxX - minX + 1) / n, height: CGFloat(maxY - minY + 1) / n))
    }

    /// Where the whole image goes on a `side` pixel square, and the tile's corner radius when it
    /// is clipped to Cra's rounded tile (an opaque image), nil when it isn't (a cut-out one).
    public static func placement(width: Int, height: Int, shape: Shape, side: Int) -> (frame: CGRect, cornerRadius: CGFloat?) {
        let w = CGFloat(width), h = CGFloat(height), s = CGFloat(side)
        if shape.cutOut, let visible = shape.visible {
            let content = CGSize(width: visible.width * w, height: visible.height * h)
            let scale = min(s / content.width, s / content.height)
            let target = CGRect(x: (s - content.width * scale) / 2, y: (s - content.height * scale) / 2,
                                width: content.width * scale, height: content.height * scale)
            return (CGRect(x: target.minX - visible.minX * w * scale, y: target.minY - visible.minY * h * scale,
                           width: w * scale, height: h * scale), nil)
        }
        let scale = max(s / w, s / h)
        return (CGRect(x: (s - w * scale) / 2, y: (s - h * scale) / 2, width: w * scale, height: h * scale), s * CGFloat(cornerRatio))
    }

    /// The icon at `side` × `side`: the image drawn where `placement` puts it, each pixel the
    /// average of up to 16 × 16 samples so a big picture shrinks smoothly, outside the tile clear.
    public static func render(_ pixels: [UInt8], width: Int, height: Int, side: Int) -> [UInt8] {
        guard side > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: side * side * 4)
        guard width > 0, height > 0, pixels.count >= width * height * 4 else { return out }
        let place = placement(width: width, height: height, shape: shape(pixels, width: width, height: height), side: side)
        let frame = place.frame, s = Double(side)
        let scale = Double(frame.width) / Double(width)
        let n = max(1, min(16, Int((1 / scale).rounded(.up))))
        let r = place.cornerRadius.map { Double($0) }
        func insideTile(_ x: Double, _ y: Double) -> Bool {
            guard let r else { return true }
            let cx = min(max(x, r), s - r), cy = min(max(y, r), s - r)
            return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r
        }
        let samples = Double(n * n)
        for y in 0..<side {
            for x in 0..<side {
                var sum = (0.0, 0.0, 0.0, 0.0)
                for j in 0..<n {
                    for i in 0..<n {
                        let px = Double(x) + (Double(i) + 0.5) / Double(n), py = Double(y) + (Double(j) + 0.5) / Double(n)
                        guard insideTile(px, py) else { continue }
                        let u = (px - Double(frame.minX)) / scale, v = (py - Double(frame.minY)) / scale
                        guard u >= 0, v >= 0, u < Double(width), v < Double(height) else { continue }
                        let k = (Int(v) * width + Int(u)) * 4
                        sum.0 += Double(pixels[k]); sum.1 += Double(pixels[k + 1])
                        sum.2 += Double(pixels[k + 2]); sum.3 += Double(pixels[k + 3])
                    }
                }
                let o = (y * side + x) * 4
                out[o] = UInt8((sum.0 / samples).rounded()); out[o + 1] = UInt8((sum.1 / samples).rounded())
                out[o + 2] = UInt8((sum.2 / samples).rounded()); out[o + 3] = UInt8((sum.3 / samples).rounded())
            }
        }
        return out
    }
}
