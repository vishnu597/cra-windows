import CraCore
import Foundation
import Testing

/// Music notes over a playing favorite on Windows (#303), where no Core Animation emitter runs
/// them: `MusicNotesEmitter` does what CAEmitterLayer does with MusicNotes' values.
struct WindowsMusicNotesTests {
    /// A fixed draw for each random number: the middle of every range.
    private let middle = { 0.5 }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/303")) func notesAreBornAtArcsRates() {
        var e = MusicNotesEmitter()
        for _ in 0..<100 { e.step(0.1, random: middle) }  // 10 s, notes live 2
        // 1.4 + 1 a second, over the last 2 s.
        #expect((2...3).contains(e.notes.filter { $0.shape == .single }.count))
        #expect((1...2).contains(e.notes.filter { $0.shape == .beamed }.count))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/303")) func aNoteRisesGrowsAndFades() throws {
        var e = MusicNotesEmitter()
        e.step(0.1, random: middle)  // the first single after 1 / 1.4 s
        for _ in 0..<7 { e.step(0.1, random: middle) }
        let note = try #require(e.notes.first)
        #expect(note.vx.magnitude < 0.001 && note.vy == -20, "straight up at 20 DIPs a second")
        e.emitting = false
        for _ in 0..<10 { e.step(0.1, random: middle) }
        let risen = try #require(e.notes.first)
        #expect(risen.y < note.y - 19 && risen.y > note.y - 21)
        #expect(risen.scale > note.scale + 0.99 && risen.alpha < note.alpha - 0.49)
        for _ in 0..<20 { e.step(0.1, random: middle) }
        #expect(e.notes.isEmpty && !e.isActive, "gone after their 2 s, and none come once it stops")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/303")) func notesStayInTheirCone() {
        var e = MusicNotesEmitter()
        let draws = [0.0, 0.999, 0.3, 0.7]
        var i = 0
        let random = { () -> Double in i += 1; return draws[i % draws.count] }
        for _ in 0..<40 { e.step(0.1, random: random) }
        #expect(!e.notes.isEmpty)
        for n in e.notes {
            #expect(n.vy < 0, "they rise")
            #expect(abs(atan2(n.vx, -n.vy)) <= Double.pi / 6 + 0.0001, "within 30° of straight up")
            #expect(n.scale >= 0 && n.alpha <= 1)
        }
        var stalled = MusicNotesEmitter()
        stalled.step(5, random: middle)
        #expect(stalled.notes.count <= 1, "a stalled frame counts as 0.1 s")
    }
}
