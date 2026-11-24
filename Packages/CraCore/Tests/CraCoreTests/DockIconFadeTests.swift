import CraCore
import Testing

/// The dock's unlit icons as the Mac draws them: 45 % opacity, 20 % saturation.
struct DockIconFadeTests {
    @Test func unlitIconsAreFaintAndNearlyGrey() {
        #expect(DockIconFade.look(lit: true) == (1, 1))
        #expect(DockIconFade.look(lit: false) == (0.45, 0.2))
    }

    @Test func desaturationMovesEachPixelTowardItsLuma() {
        // Pure red, opaque (BGRA), and a half-transparent premultiplied blue.
        let pixels: [UInt8] = [0, 0, 255, 255, 128, 0, 0, 128]
        let grey = DockIconFade.desaturate(bgra: pixels, saturation: 0)
        let luma = UInt8((0.2125 * 255).rounded())
        #expect(Array(grey[0..<4]) == [luma, luma, luma, 255])
        #expect(grey[7] == 128)
        #expect(grey[4] == grey[5] && grey[5] == grey[6])
        // At 0.2 the colour keeps a fifth of its distance from grey.
        let faded = DockIconFade.desaturate(bgra: pixels, saturation: 0.2)
        let l = 0.2125 * 255
        #expect(faded[2] == UInt8((l + (255 - l) * 0.2).rounded()))
        #expect(faded[0] == UInt8((l * 0.8).rounded()))
        // Full saturation leaves the pixels as they were.
        #expect(DockIconFade.desaturate(bgra: pixels, saturation: 1) == pixels)
    }
}
