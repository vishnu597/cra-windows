import CraCore
import Foundation
import Testing

/// The user's own app icon made from any image, as the Mac makes it (#372): an opaque image fills
/// the rounded tile, a cut-out one has its visible part fitted to the square.
struct AppIconImageTests {
    /// A `w` × `h` image, every pixel `pixel(x, y)` (b, g, r, a; premultiplied).
    static func image(_ w: Int, _ h: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        var out: [UInt8] = []
        for y in 0..<h {
            for x in 0..<w {
                let p = pixel(x, y)
                out += [p.0, p.1, p.2, p.3]
            }
        }
        return out
    }

    static func at(_ pixels: [UInt8], _ side: Int, _ x: Int, _ y: Int) -> [UInt8] {
        let k = (y * side + x) * 4
        return Array(pixels[k..<k + 4])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/372")) func aPhotoFillsTheRoundedTile() {
        // 40 × 20, opaque red: cropped to the middle square, clipped to Cra's corners.
        let photo = Self.image(40, 20) { _, _ in (0, 0, 255, 255) }
        let shape = AppIconImage.shape(photo, width: 40, height: 20)
        #expect(!shape.cutOut)
        #expect(shape.visible == CGRect(x: 0, y: 0, width: 1, height: 1))
        let place = AppIconImage.placement(width: 40, height: 20, shape: shape, side: 64)
        #expect(place.frame == CGRect(x: -32, y: 0, width: 128, height: 64))
        #expect(place.cornerRadius == 14.3)
        let icon = AppIconImage.render(photo, width: 40, height: 20, side: 64)
        #expect(icon.count == 64 * 64 * 4)
        #expect(Self.at(icon, 64, 32, 32) == [0, 0, 255, 255])
        #expect(Self.at(icon, 64, 0, 0)[3] == 0, "outside the rounded corner")
        #expect(Self.at(icon, 64, 32, 0) == [0, 0, 255, 255], "the edge's middle is inside the tile")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/372")) func aCutOutLogoIsFittedByItsVisiblePart() throws {
        // 100 × 100, clear but for an opaque 20 × 40 bar from (40, 30): the bar's height fills the square.
        let logo = Self.image(100, 100) { x, y in (40..<60).contains(x) && (30..<70).contains(y) ? (255, 255, 255, 255) : (0, 0, 0, 0) }
        let shape = AppIconImage.shape(logo, width: 100, height: 100)
        #expect(shape.cutOut)
        let visible = try #require(shape.visible)
        #expect(abs(visible.minX - 0.40) < 0.01 && abs(visible.minY - 0.30) < 0.01)
        #expect(abs(visible.width - 0.20) < 0.01 && abs(visible.height - 0.40) < 0.01)
        let place = AppIconImage.placement(width: 100, height: 100, shape: shape, side: 40)
        #expect(place.cornerRadius == nil)
        // The bar comes out 20 × 40 in the middle of the 40 px square: x 10..<30, y 0..<40.
        #expect(abs(place.frame.width - 100) < 1.5)
        let icon = AppIconImage.render(logo, width: 100, height: 100, side: 40)
        #expect(Self.at(icon, 40, 20, 20)[3] == 255)
        #expect(Self.at(icon, 40, 20, 1)[3] == 255, "the bar reaches the top")
        #expect(Self.at(icon, 40, 3, 20)[3] == 0, "clear beside it")
    }

    @Test func aBigPictureShrinksSmoothly() {
        // Black and white columns, one pixel each: shrunk 8 times, every pixel is grey.
        let stripes = Self.image(256, 256) { x, _ in x % 2 == 0 ? (255, 255, 255, 255) : (0, 0, 0, 255) }
        let icon = AppIconImage.render(stripes, width: 256, height: 256, side: 32)
        let middle = Self.at(icon, 32, 16, 16)
        #expect(middle[3] == 255)
        #expect((120...135).contains(middle[0]))
    }

    @Test func nothingToDraw() {
        #expect(AppIconImage.shape([], width: 0, height: 0) == AppIconImage.Shape(cutOut: false, visible: nil))
        let clear = Self.image(8, 8) { _, _ in (0, 0, 0, 0) }
        #expect(AppIconImage.shape(clear, width: 8, height: 8).visible == nil)
        #expect(AppIconImage.render(clear, width: 8, height: 8, side: 4) == [UInt8](repeating: 0, count: 64))
        #expect(AppIconImage.render(clear, width: 8, height: 8, side: 0).isEmpty)
    }
}
