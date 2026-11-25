import CraCore
import Foundation
import UWP
import WinAppSDK
import WindowsFoundation
import WinUI

/// Arc's music notes rising from a favorite that plays music (#303, the Mac's MusicNotesView):
/// a click-through canvas over the tile's icon, drawn from `MusicNotesEmitter` at 30 frames a
/// second while notes are in the air. Notes are ♪ and ♫ in the tile's ink (white 80 % on a
/// dark tile, black 30 % on a light one), and drift over the tiles round it.
@MainActor
final class FavoriteMusicNotes {
    /// Zero-sized, at the emitter: the notes are drawn round it, unclipped.
    let canvas = Canvas()
    var dark = false
    var emitting: Bool {
        get { emitter.emitting }
        set {
            emitter.emitting = newValue
            if newValue { start() }
        }
    }
    var isActive: Bool { emitter.isActive }

    private var emitter = MusicNotesEmitter()
    private var views: [TextBlock] = []
    private var transforms: [CompositeTransform] = []
    private var timer: WinAppSDK.DispatcherQueueTimer?
    private var lastTick = Date()

    init() {
        canvas.width = 0
        canvas.height = 0
        canvas.isHitTestVisible = false
        canvas.horizontalAlignment = .center
        canvas.verticalAlignment = .center
        // The emitter's centre on the top edge of the icon (MusicNotes.lift).
        canvas.margin = Thickness(left: 0, top: 0, right: 0, bottom: 2 * Double(MusicNotes.lift))
    }

    private func start() {
        guard timer == nil, let queue = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil,
              let timer = try? queue.createTimer() else { return }
        timer.interval = TimeSpan(duration: 33 * 10_000)
        timer.isRepeating = true
        timer.tick.addHandler { [weak self] _, _ in self?.tick() }
        lastTick = Date()
        try? timer.start()
        self.timer = timer
    }

    /// Stops the frames (the tile left the grid).
    func stop() {
        try? timer?.stop()
        timer = nil
        emitter = MusicNotesEmitter()
        draw()
    }

    private func tick() {
        let now = Date()
        emitter.step(now.timeIntervalSince(lastTick)) { Double.random(in: 0..<1) }
        lastTick = now
        draw()
        if !emitter.isActive {
            try? timer?.stop()
            timer = nil
        }
    }

    private func draw() {
        let notes = emitter.notes
        while views.count < notes.count {
            let t = TextBlock()
            t.fontFamily = FontFamily("Segoe UI Symbol")
            t.fontSize = Double(MusicNotes.spritePixels)
            // Centred on its point: a 12 DIP square round the glyph.
            t.width = Double(MusicNotes.spritePixels)
            t.height = Double(MusicNotes.spritePixels) * 1.4
            t.textAlignment = .center
            let transform = CompositeTransform()
            transform.centerX = Double(MusicNotes.spritePixels) / 2
            transform.centerY = Double(MusicNotes.spritePixels) * 0.7
            t.renderTransform = transform
            canvas.children.append(t)
            views.append(t)
            transforms.append(transform)
        }
        let ink = MusicNotes.ink(dark: dark)
        let level = UInt8(Double(ink.white) * 255)
        let brush = UI.brush(level, level, level)
        for (i, view) in views.enumerated() {
            guard i < notes.count else {
                view.visibility = .collapsed
                continue
            }
            let n = notes[i]
            view.visibility = .visible
            view.text = n.shape == .single ? "\u{266A}" : "\u{266B}"
            view.foreground = brush
            view.opacity = max(0, min(1, n.alpha)) * Double(ink.alpha)
            let t = transforms[i]
            t.translateX = n.x - Double(MusicNotes.spritePixels) / 2
            t.translateY = n.y - Double(MusicNotes.spritePixels) * 0.7
            t.scaleX = n.scale
            t.scaleY = n.scale
        }
    }
}
