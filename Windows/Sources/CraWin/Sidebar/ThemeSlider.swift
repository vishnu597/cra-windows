import CraCore
import Foundation
import UWP
import WinUI

/// The theme editor's intensity and grain sliders, 0 to 1: a track filled up to a round knob that
/// a press or a drag moves. Made by hand, as the colour pad is, since WinUI's Slider isn't in the
/// Swift/WinRT projection Cra builds with. Every control is kept here.
@MainActor
final class ThemeSlider {
    static let knobSide = 16.0
    static let trackHeight = 4.0

    let root = Grid()
    private let canvas = Canvas()
    private let track = Border()
    private let filled = Border()
    private let knob = WinUI.Ellipse()  // not GDI's Ellipse
    private var held = false
    private(set) var value: Double
    private let onChange: @MainActor () -> Void

    init(value: Double, onChange: @escaping @MainActor () -> Void) {
        self.value = min(max(value, 0), 1)
        self.onChange = onChange
        root.height = Self.knobSide + 8
        root.background = UI.clear
        for bar in [track, filled] {
            bar.height = Self.trackHeight
            bar.cornerRadius = CornerRadius(topLeft: 2, topRight: 2, bottomRight: 2, bottomLeft: 2)
            bar.verticalAlignment = .center
            bar.isHitTestVisible = false
        }
        track.horizontalAlignment = .stretch
        track.margin = Thickness(left: Self.knobSide / 2, top: 0, right: Self.knobSide / 2, bottom: 0)
        filled.horizontalAlignment = .left
        filled.margin = Thickness(left: Self.knobSide / 2, top: 0, right: 0, bottom: 0)
        knob.width = Self.knobSide
        knob.height = Self.knobSide
        knob.fill = UI.brush(255, 255, 255)
        knob.stroke = UI.brush(0, 0, 0, alpha: 40)
        knob.strokeThickness = 1
        knob.isHitTestVisible = false
        canvas.isHitTestVisible = false
        canvas.children.append(knob)
        for part: UIElement in [track, filled, canvas] { root.children.append(part) }
        root.sizeChanged.addHandler { [weak self] _, _ in self?.layout() }
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
            self?.held = false
        }
        root.pointerCaptureLost.addHandler { [weak self] _, _ in self?.held = false }
    }

    /// The track's tint and the fill up to the knob.
    func apply(track: Brush, fill: Brush) {
        self.track.background = track
        filled.background = fill
    }

    /// The room the knob's centre travels.
    private var span: Double { max(1, root.actualWidth - Self.knobSide) }

    private func move(to x: Double) {
        let v = min(max((x - Self.knobSide / 2) / span, 0), 1)
        guard abs(v - value) > 0.001 else { return }
        value = v
        layout()
        onChange()
    }

    private func layout() {
        let left = value * span
        try? Canvas.setLeft(knob, left)
        try? Canvas.setTop(knob, (root.actualHeight - Self.knobSide) / 2)
        filled.width = left
    }
}
