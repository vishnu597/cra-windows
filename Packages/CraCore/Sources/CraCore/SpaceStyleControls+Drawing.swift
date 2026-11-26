import Foundation

/// The geometry of the theme editor's wave slider and grain dial, for a platform that draws them by
/// hand (Windows: WinUI's Slider and Path shapes aren't in the Swift/WinRT projection Cra builds with).
/// The Mac draws the same shapes in SwiftUI (SpaceStyleEditor's WaveSlider and GrainDial); these are
/// its formulas, in points.
extension SpaceStyleControls {
    // MARK: The slider

    /// The wave runs seven periods across the travel (14π), from the left end's centre to the right's.
    public static let waveHalfTurns = 14.0

    /// The wave's height at `x` in a `width` × `height` slider: a sine about the middle, `amp` high,
    /// starting at the travel's left end going up.
    public static func waveY(x: Double, width: Double, height: Double, value: Double) -> Double {
        let inset = Double(trackInset), span = max(1, width - 2 * inset)
        let amp = Double(waveAmplitude(value: value))
        return height / 2 - amp * sin((x - inset) / span * .pi * waveHalfTurns)
    }

    /// The thumb's centre for `value`, and the value a pointer at `x` picks (held to 0…1).
    public static func sliderX(value: Double, width: Double) -> Double {
        let inset = Double(trackInset)
        return inset + (width - 2 * inset) * min(max(value, 0), 1)
    }

    public static func sliderValue(x: Double, width: Double) -> Double {
        let inset = Double(trackInset)
        return min(max((x - inset) / max(1, width - 2 * inset), 0), 1)
    }

    /// The wave's stroke as coverage, one byte a pixel, top-down, `scale` pixels a point: the Mac's
    /// path (a point a point from end to end) stroked `waveLine` wide with round caps and joins,
    /// antialiased.
    public static func waveMask(width: Double, height: Double, value: Double, scale: Double)
        -> (width: Int, height: Int, alpha: [UInt8]) {
        let inset = Double(trackInset)
        let pw = max(1, Int((width * scale).rounded(.up))), ph = max(1, Int((height * scale).rounded(.up)))
        var xs: [Double] = []
        var x = inset
        while x <= width - inset + 1e-9 { xs.append(x); x += 1 }
        let ys = xs.map { waveY(x: $0, width: width, height: height, value: value) }
        let r = Double(waveLine) / 2
        var alpha = [UInt8](repeating: 0, count: pw * ph)
        guard !xs.isEmpty else { return (pw, ph, alpha) }
        for py in 0..<ph {
            let cy = (Double(py) + 0.5) / scale
            for px in 0..<pw {
                let cx = (Double(px) + 0.5) / scale
                // Only the segments within a line's width of the pixel can reach it.
                let lo = max(0, Int((cx - r - inset).rounded(.down)) - 1)
                let hi = min(xs.count - 1, Int((cx + r - inset).rounded(.up)) + 1)
                guard lo <= hi else { continue }
                var best = Double.infinity
                for i in lo...hi {
                    let j = min(i + 1, xs.count - 1)
                    best = min(best, distance(cx, cy, xs[i], ys[i], xs[j], ys[j]))
                }
                let c = min(max((r - best) * scale + 0.5, 0), 1)
                alpha[py * pw + px] = UInt8((c * 255).rounded())
            }
        }
        return (pw, ph, alpha)
    }

    private static func distance(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy
        let t = len > 0 ? min(max(((px - ax) * dx + (py - ay) * dy) / len, 0), 1) : 0
        let qx = ax + t * dx - px, qy = ay + t * dy - py
        return (qx * qx + qy * qy).squareRoot()
    }

    // MARK: The dial

    /// 24 dots on a 34 pt ring round a 41 pt disc, the knob 4.5 × 12 pt on a 31 pt ring.
    public static let dialDots = 24
    public static let dialDotRing = 34.0
    public static let dialDotSide = 3.5
    public static let dialDisc = 41.0
    public static let dialKnobRing = 31.0
    public static let dialKnobSize = (width: 4.5, height: 12.0)

    /// Dot `index`'s centre from the dial's, from twelve o'clock clockwise (y down).
    public static func dialDot(_ index: Int) -> (x: Double, y: Double) {
        let a = Double(index) / Double(dialDots) * 2 * .pi - .pi / 2
        return (dialDotRing * cos(a), dialDotRing * sin(a))
    }

    /// Whether dot `index` is lit: it lies between twelve o'clock and the knob.
    public static func dialDotLit(_ index: Int, value: Double) -> Bool {
        Double(index) / Double(dialDots) <= value
    }

    /// The knob's centre from the dial's, and its turn in degrees (0 upright at twelve o'clock).
    public static func dialKnob(value: Double) -> (x: Double, y: Double, degrees: Double) {
        let a = value * 2 * .pi - .pi / 2
        return (dialKnobRing * cos(a), dialKnobRing * sin(a), value * 360)
    }

    /// The value a pointer `dx`, `dy` from the dial's centre turns it to: its angle from twelve
    /// o'clock, clockwise, as a share of a turn.
    public static func dialValue(dx: Double, dy: Double) -> Double {
        var a = atan2(dy, dx) + .pi / 2
        if a < 0 { a += 2 * .pi }
        return a / (2 * .pi)
    }

    /// The dial's face: the grain texture at `0.15 + 0.6 × value` over the disc (NoiseDisc).
    public static func grainOpacity(value: Double) -> Double {
        0.15 + 0.6 * min(max(value, 0), 1)
    }
}

// MARK: The pad

extension SpaceStyleControls {
    /// The pad's dots: 1 pt across, every 4 pt from 4 pt in, at the card's ink × 0.12.
    public static let padDotPitch = 4.0
    public static let padDotSide = 1.0
    public static let padDotOpacity = 0.12

    /// The dots' centres along one side of a `side` pt pad (4, 8, … short of the far edge).
    public static func padDotCentres(side: Double) -> [Double] {
        Array(stride(from: padDotPitch, to: side, by: padDotPitch))
    }

    /// Arc's ColorPillButtonStyle, which the swatches and the pad's knobs share (#189):
    /// 8% larger under the pointer, 8% smaller while pressed; pressed wins.
    public static let pillHovered = 1.08
    public static let pillPressed = 0.92

    public static func pillScale(hovered: Bool, pressed: Bool) -> Double {
        pressed ? pillPressed : hovered ? pillHovered : 1
    }

    /// A knob's shadow (black at 0.25, 3 pt soft, 1 pt down): its opacity at `distance` pt from the
    /// centre of a knob `radius` pt round.
    public static let knobShadowOpacity = 0.25
    public static let knobShadowBlur = 3.0

    public static func knobShadow(distance: Double, radius: Double) -> Double {
        let t = min(max((radius + knobShadowBlur - distance) / (2 * knobShadowBlur), 0), 1)
        return knobShadowOpacity * t * t * (3 - 2 * t)
    }
}
