import Foundation

/// How the space dock draws an icon that isn't lit (the Mac's SpaceCellView): at 45 % opacity
/// and desaturated to 20 % (Core Image's CIColorControls, inputSaturation 0.2), the colours
/// coming back while the space is open, hovered or pressed. Windows has no layer filters, so it
/// applies the same desaturation to the icon's pixels (`desaturate(bgra:saturation:)`).
public enum DockIconFade {
    public static let alpha = 0.45
    public static let saturation = 0.2

    /// The opacity and saturation of a cell's icon.
    public static func look(lit: Bool) -> (alpha: Double, saturation: Double) {
        lit ? (1, 1) : (alpha, saturation)
    }

    /// Core Image's colour-controls saturation: each pixel moved from its luma (Rec. 709 weights,
    /// as CIColorControls uses) toward its colour by `saturation` (0 grey, 1 unchanged). Works on
    /// premultiplied or straight BGRA alike, since luma is a weighted sum; alpha stays.
    public static func desaturate(bgra: [UInt8], saturation: Double) -> [UInt8] {
        let s = max(0, min(1, saturation))
        guard s < 1 else { return bgra }
        var out = bgra
        var i = 0
        while i + 3 < out.count {
            let b = Double(out[i]), g = Double(out[i + 1]), r = Double(out[i + 2])
            let luma = 0.2125 * r + 0.7154 * g + 0.0721 * b
            func mix(_ c: Double) -> UInt8 { UInt8(max(0, min(255, (luma + (c - luma) * s).rounded()))) }
            out[i] = mix(b)
            out[i + 1] = mix(g)
            out[i + 2] = mix(r)
            i += 4
        }
        return out
    }
}
