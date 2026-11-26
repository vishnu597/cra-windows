import CraCore
import Foundation
import Testing

/// The wave slider and grain dial as a hand-drawn platform (Windows) draws them: the Mac's shapes.
struct SpaceStyleControlsDrawingTests {
    private func alpha(_ m: (width: Int, height: Int, alpha: [UInt8]), _ x: Double, _ y: Double, scale: Double) -> UInt8 {
        m.alpha[Int(y * scale) * m.width + Int(x * scale)]
    }

    /// At nothing the wave is a flat line through the middle, 5 pt wide, with round ends.
    @Test
    func aFlatWaveAtNothing() {
        let m = SpaceStyleControls.waveMask(width: 224, height: 50, value: 0, scale: 2)
        #expect(m.width == 448 && m.height == 100)
        #expect(alpha(m, 100, 25, scale: 2) == 255)
        #expect(alpha(m, 100, 29, scale: 2) == 0)
        #expect(alpha(m, 100, 21, scale: 2) == 0)
        // The round cap reaches 2.5 pt past the travel's end, no further.
        #expect(alpha(m, 9, 25, scale: 2) == 255)
        #expect(alpha(m, 6.5, 25, scale: 2) == 0)
    }

    /// At full the first crest is the wave's full height above the middle, a quarter period in.
    @Test
    func theWaveRisesWithTheValue() {
        let w = 224.0, inset = Double(SpaceStyleControls.trackInset)
        let crest = inset + (w - 2 * inset) / 28
        let top = SpaceStyleControls.waveY(x: crest, width: w, height: 50, value: 1)
        #expect(abs(top - (25 - 14.25)) < 1e-9)
        let m = SpaceStyleControls.waveMask(width: w, height: 50, value: 1, scale: 2)
        #expect(alpha(m, crest, top, scale: 2) == 255)
        #expect(alpha(m, crest, 25, scale: 2) == 0)
        #expect(abs(SpaceStyleControls.waveY(x: crest, width: w, height: 50, value: 0.5) - (25 - 14.25 / 2)) < 1e-9)
    }

    /// The thumb's travel and a pointer's value are the Mac's: 10.5 pt inside each end, held to 0…1.
    @Test
    func theThumbTravelsInsideTheEnds() {
        #expect(SpaceStyleControls.sliderX(value: 0, width: 224) == 10.5)
        #expect(SpaceStyleControls.sliderX(value: 1, width: 224) == 213.5)
        #expect(SpaceStyleControls.sliderValue(x: 112, width: 224) == 0.5)
        #expect(SpaceStyleControls.sliderValue(x: -20, width: 224) == 0)
        #expect(SpaceStyleControls.sliderValue(x: 400, width: 224) == 1)
    }

    /// The dial turns from twelve o'clock clockwise; its dots light up to the knob.
    @Test
    func theDialTurnsClockwiseFromTwelve() {
        #expect(abs(SpaceStyleControls.dialValue(dx: 0, dy: -10)) < 1e-12)
        #expect(abs(SpaceStyleControls.dialValue(dx: 10, dy: 0) - 0.25) < 1e-12)
        #expect(abs(SpaceStyleControls.dialValue(dx: 0, dy: 10) - 0.5) < 1e-12)
        #expect(abs(SpaceStyleControls.dialValue(dx: -10, dy: 0) - 0.75) < 1e-12)
        let top = SpaceStyleControls.dialKnob(value: 0)
        #expect(abs(top.x) < 1e-9 && abs(top.y + 31) < 1e-9 && top.degrees == 0)
        let right = SpaceStyleControls.dialKnob(value: 0.25)
        #expect(abs(right.x - 31) < 1e-9 && abs(right.y) < 1e-9 && right.degrees == 90)
        let dot = SpaceStyleControls.dialDot(6)
        #expect(abs(dot.x - 34) < 1e-9 && abs(dot.y) < 1e-9)
        let lit = (0..<SpaceStyleControls.dialDots).filter { SpaceStyleControls.dialDotLit($0, value: 0.5) }
        #expect(lit == Array(0...12))
        #expect(SpaceStyleControls.grainOpacity(value: 1) == 0.75)
    }
}
