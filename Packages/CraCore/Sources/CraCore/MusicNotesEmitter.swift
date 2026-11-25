import Foundation

/// The music notes' particles where there is no Core Animation emitter (Windows): what the
/// Mac's CAEmitterLayer does with `MusicNotes`' values, stepped by the app's frame timer.
/// Notes are born inside a circle of `emitterRadius` round the emitter, rise at `velocity`
/// (± `velocityRange`) within `emissionRange` of straight up, grow from `scale` (± `scaleRange`)
/// by `scaleSpeed` a second and fade by `alphaSpeed` a second from 1 (− `alphaRange`), for
/// `lifetime` seconds. Coordinates are DIPs from the emitter, y down.
public struct MusicNotesEmitter: Equatable, Sendable {
    public struct Note: Equatable, Sendable {
        public var shape: MusicNotes.Shape
        public var x: Double
        public var y: Double
        public var vx: Double
        public var vy: Double
        public var scale: Double
        public var alpha: Double
        public var age: Double
    }

    public private(set) var notes: [Note] = []
    /// Births owed to each shape, carried between steps.
    private var owed: [Double] = MusicNotes.Shape.allCases.map { _ in 0 }
    /// Off: no new notes; the ones in the air finish rising.
    public var emitting = true

    public init() {}

    /// Notes in the air or still to come: the frame timer keeps running.
    public var isActive: Bool { emitting || !notes.isEmpty }

    /// Moves the notes `dt` seconds on (at most 0.1, so a stalled frame doesn't jump), and
    /// emits the ones due. `random` returns 0..<1.
    public mutating func step(_ dt: Double, random: () -> Double) {
        let dt = max(0, min(dt, 0.1))
        let lifetime = Double(MusicNotes.lifetime)
        for i in notes.indices {
            notes[i].age += dt
            notes[i].x += notes[i].vx * dt
            notes[i].y += notes[i].vy * dt
            notes[i].scale += Double(MusicNotes.scaleSpeed) * dt
            notes[i].alpha += Double(MusicNotes.alphaSpeed) * dt
        }
        notes.removeAll { $0.age >= lifetime || $0.alpha <= 0 }
        guard emitting else { return }
        for (s, shape) in MusicNotes.Shape.allCases.enumerated() {
            owed[s] += Double(MusicNotes.birthRate(shape)) * dt
            while owed[s] >= 1 {
                owed[s] -= 1
                notes.append(Self.born(shape, random: random))
            }
        }
    }

    static func born(_ shape: MusicNotes.Shape, random: () -> Double) -> Note {
        func spread() -> Double { random() * 2 - 1 }
        let at = random() * 2 * Double.pi, r = Double(MusicNotes.emitterRadius) * random().squareRoot()
        let speed = Double(MusicNotes.velocity) + spread() * Double(MusicNotes.velocityRange)
        // Core Animation's angles turn from +x towards +y up; the field's y goes down.
        let angle = Double(MusicNotes.emissionLongitude) + spread() * Double(MusicNotes.emissionRange) / 2
        return Note(shape: shape, x: r * cos(at), y: r * sin(at), vx: speed * cos(angle), vy: -speed * sin(angle),
                    scale: abs(Double(MusicNotes.scale) + spread() * Double(MusicNotes.scaleRange)),
                    alpha: min(1, 1 - abs(spread()) * Double(MusicNotes.alphaRange)), age: 0)
    }
}
