import CraCore
import Foundation
import UWP
import WinUI

/// The theme editor's intensity (Arc's wave slider) and grain (its dial), drawn by hand from the Mac's
/// shapes (SpaceStyleControls), since WinUI's Slider and Path aren't in the Swift/WinRT projection
/// Cra builds with. Every control is kept here.

/// A wave over a 15 pt track with a white thumb, both growing with the value: the wave from a flat
/// line to its full height, the thumb from 11.5 × 40.5 to 25.5 × 53 pt, a tenth larger under the
/// pointer or held. The wave is bright up to the thumb and faint after it.
@MainActor
final class ThemeWaveSlider {
    static let width = 224.0
    static let height = 50.0

    let root = Grid()
    private let track = Border()
    private let wave = WinUI.Image()
    private let canvas = Canvas()
    private let thumb = Border()
    private var hovered = false
    private var held = false
    private var light = false
    private(set) var value: Double
    private let onChange: @MainActor () -> Void

    init(value: Double, onChange: @escaping @MainActor () -> Void) {
        self.value = min(max(value, 0), 1)
        self.onChange = onChange
        root.width = Self.width
        root.height = Self.height
        root.background = UI.clear
        root.horizontalAlignment = .left
        track.height = 15
        track.cornerRadius = CornerRadius(topLeft: 7.5, topRight: 7.5, bottomRight: 7.5, bottomLeft: 7.5)
        track.verticalAlignment = .center
        wave.width = Self.width
        wave.height = Self.height
        wave.stretch = .fill
        thumb.background = UI.brush(255, 255, 255)
        for part: UIElement in [track, wave, canvas, thumb] { part.isHitTestVisible = false }
        canvas.children.append(thumb)
        for part: UIElement in [track, wave, canvas] { root.children.append(part) }
        root.pointerEntered.addHandler { [weak self] _, _ in self?.hover(true) }
        root.pointerExited.addHandler { [weak self] _, _ in self?.hover(false) }
        root.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(self.root),
                  (try? self.root.capturePointer(args.pointer)) == true else { return }
            args.handled = true
            self.held = true
            self.move(to: Double(point.position.x))
        }
        root.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.held, let args, let point = try? args.getCurrentPoint(self.root) else { return }
            args.handled = true
            self.move(to: Double(point.position.x))
        }
        root.pointerReleased.addHandler { [weak self] _, args in
            args?.handled = true
            self?.release()
        }
        root.pointerCaptureLost.addHandler { [weak self] _, _ in self?.release() }
        root.loaded.addHandler { [weak self] _, _ in self?.draw() }
        draw()
    }

    /// The card's ink: black on Light, white on Dark.
    func apply(light: Bool) {
        self.light = light
        let v: UInt8 = light ? 0 : 255
        track.background = UI.brush(v, v, v, alpha: 26)
        draw()
    }

    private func hover(_ on: Bool) {
        hovered = on
        layoutThumb()
    }

    private func release() {
        held = false
        layoutThumb()
    }

    private func move(to x: Double) {
        let v = SpaceStyleControls.sliderValue(x: x, width: Self.width)
        guard abs(v - value) > 0.001 else { return }
        value = v
        draw()
        onChange()
    }

    private func layoutThumb() {
        let size = SpaceStyleControls.thumbSize(value: value, held: hovered || held)
        let w = Double(size.width), h = Double(size.height)
        thumb.width = w
        thumb.height = h
        thumb.cornerRadius = CornerRadius(topLeft: w / 2, topRight: w / 2, bottomRight: w / 2, bottomLeft: w / 2)
        try? Canvas.setLeft(thumb, SpaceStyleControls.sliderX(value: value, width: Self.width) - w / 2)
        try? Canvas.setTop(thumb, (Self.height - h) / 2)
    }

    /// The wave at the screen's own scale: the Mac's lit stroke (0.36 black, 0.75 white) up to the
    /// thumb's centre, the faint one (0.12, 0.25) after it.
    private func draw() {
        layoutThumb()
        let scale = max(1, root.xamlRoot.map { $0.rasterizationScale } ?? 1)
        let mask = SpaceStyleControls.waveMask(width: Self.width, height: Self.height, value: value, scale: scale)
        let split = SpaceStyleControls.sliderX(value: value, width: Self.width) * scale
        let (lit, faint) = light ? (0.36, 0.12) : (0.75, 0.25)
        let ink = light ? 0.0 : 1.0
        var bgra = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let i = y * mask.width + x
                let cover = Double(mask.alpha[i])
                guard cover > 0 else { continue }
                let a = cover * (Double(x) + 0.5 < split ? lit : faint)
                let c = UInt8((a * ink).rounded())
                bgra[i * 4] = c
                bgra[i * 4 + 1] = c
                bgra[i * 4 + 2] = c
                bgra[i * 4 + 3] = UInt8(a.rounded())
            }
        }
        wave.source = Pixels(width: mask.width, height: mask.height, bgra: bgra).bitmap()
    }
}

/// The grain: a dark disc showing it, a ring of dots lit from twelve o'clock round to a white knob;
/// turning the knob sets the value.
@MainActor
final class ThemeGrainDial {
    static let side = 70.0

    let root = Grid()
    private let canvas = Canvas()
    private var dots: [WinUI.Ellipse] = []
    private let disc = WinUI.Ellipse()
    private let grain = WinUI.Image()
    private let ring = WinUI.Ellipse()
    private let knob = Border()
    private let knobTurn = CompositeTransform()
    private var held = false
    private var light = false
    private(set) var value: Double
    private let onChange: @MainActor () -> Void

    init(value: Double, onChange: @escaping @MainActor () -> Void) {
        self.value = min(max(value, 0), 1)
        self.onChange = onChange
        root.width = Self.side
        root.height = Self.side
        root.background = UI.clear
        let c = Self.side / 2
        for i in 0..<SpaceStyleControls.dialDots {
            let dot = WinUI.Ellipse()
            let s = SpaceStyleControls.dialDotSide
            dot.width = s
            dot.height = s
            let p = SpaceStyleControls.dialDot(i)
            try? Canvas.setLeft(dot, c + p.x - s / 2)
            try? Canvas.setTop(dot, c + p.y - s / 2)
            dots.append(dot)
            canvas.children.append(dot)
        }
        let d = SpaceStyleControls.dialDisc
        for part: FrameworkElement in [disc, grain, ring] {
            part.width = d
            part.height = d
            try? Canvas.setLeft(part, c - d / 2)
            try? Canvas.setTop(part, c - d / 2)
            canvas.children.append(part)
        }
        disc.fill = UI.brush(0, 0, 0, alpha: 31)
        ring.strokeThickness = 1
        grain.stretch = .fill
        grain.source = Self.grainDisc(scale: 2)?.bitmap()
        let k = SpaceStyleControls.dialKnobSize
        knob.width = k.width
        knob.height = k.height
        knob.cornerRadius = CornerRadius(topLeft: k.width / 2, topRight: k.width / 2, bottomRight: k.width / 2, bottomLeft: k.width / 2)
        knob.background = UI.brush(255, 255, 255)
        knobTurn.centerX = k.width / 2
        knobTurn.centerY = k.height / 2
        knob.renderTransform = knobTurn
        canvas.children.append(knob)
        canvas.isHitTestVisible = false
        root.children.append(canvas)
        root.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(self.root) else { return }
            // The dial's round, as the Mac's contentShape(Circle()).
            let dx = Double(point.position.x) - c, dy = Double(point.position.y) - c
            guard dx * dx + dy * dy <= c * c, (try? self.root.capturePointer(args.pointer)) == true else { return }
            args.handled = true
            self.held = true
            self.turn(dx: dx, dy: dy)
        }
        root.pointerMoved.addHandler { [weak self] _, args in
            guard let self, self.held, let args, let point = try? args.getCurrentPoint(self.root) else { return }
            args.handled = true
            self.turn(dx: Double(point.position.x) - c, dy: Double(point.position.y) - c)
        }
        root.pointerReleased.addHandler { [weak self] _, args in
            args?.handled = true
            self?.held = false
        }
        root.pointerCaptureLost.addHandler { [weak self] _, _ in self?.held = false }
        layout()
    }

    /// The card's ink: black on Light, white on Dark.
    func apply(light: Bool) {
        self.light = light
        let v: UInt8 = light ? 0 : 255
        ring.stroke = UI.brush(v, v, v, alpha: 31)
        layout()
    }

    private func turn(dx: Double, dy: Double) {
        let v = SpaceStyleControls.dialValue(dx: dx, dy: dy)
        guard abs(v - value) > 0.001 else { return }
        value = v
        layout()
        onChange()
    }

    private func layout() {
        let v: UInt8 = light ? 0 : 255
        let on = UI.brush(v, v, v, alpha: 140), off = UI.brush(v, v, v, alpha: 46)
        for (i, dot) in dots.enumerated() { dot.fill = SpaceStyleControls.dialDotLit(i, value: value) ? on : off }
        grain.opacity = SpaceStyleControls.grainOpacity(value: value)
        let c = Self.side / 2, k = SpaceStyleControls.dialKnob(value: value), size = SpaceStyleControls.dialKnobSize
        try? Canvas.setLeft(knob, c + k.x - size.width / 2)
        try? Canvas.setTop(knob, c + k.y - size.height / 2)
        knobTurn.rotation = k.degrees
    }

    /// The dial's face: a grey grain, one random value a point as the Mac's texture, in the disc's
    /// round (antialiased), drawn once.
    private static func grainDisc(scale: Int) -> Pixels? {
        let points = Int(SpaceStyleControls.dialDisc.rounded(.up)), side = points * scale
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var values = [UInt8](repeating: 0, count: points * points)
        for i in values.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            values[i] = UInt8(truncatingIfNeeded: seed >> 56)
        }
        let r = Double(side) / 2
        var bgra = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) + 0.5 - r, dy = Double(y) + 0.5 - r
                let cover = min(max(r - (dx * dx + dy * dy).squareRoot() + 0.5, 0), 1)
                guard cover > 0 else { continue }
                let g = Double(values[(y / scale) * points + x / scale]) * cover
                let i = (y * side + x) * 4
                bgra[i] = UInt8(g.rounded())
                bgra[i + 1] = UInt8(g.rounded())
                bgra[i + 2] = UInt8(g.rounded())
                bgra[i + 3] = UInt8((cover * 255).rounded())
            }
        }
        return Pixels(width: side, height: side, bgra: bgra)
    }
}
