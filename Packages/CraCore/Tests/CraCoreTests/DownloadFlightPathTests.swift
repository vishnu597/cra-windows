import CraCore
import Foundation
import Testing

/// Arc's download flight (the Mac's DownloadFlight) as Windows draws it.
struct DownloadFlightPathTests {
    @Test func throwsFromThePointerOntoTheButton() {
        let start = CGPoint(x: 600, y: 300), end = CGPoint(x: 30, y: 900)
        let path = DownloadFlightPath(start: start, end: end)
        let first = path.point(at: 0), last = path.point(at: path.duration)
        #expect(abs(first.x - start.x) < 0.001 && abs(first.y - start.y) < 0.001)
        #expect(abs(last.x - end.x) < 0.001 && abs(last.y - end.y) < 0.001)
        let apex = path.point(at: path.apexTime)
        #expect(abs(apex.y - (start.y - 90)) < 0.001, "rises 90 above the higher end")
        // The fall from the top of a 1084 pt window, as measured on Arc: a little over a second.
        let tall = DownloadFlightPath(start: CGPoint(x: 500, y: 0), end: CGPoint(x: 20, y: 1084))
        #expect(tall.duration > 1.0 && tall.duration < 1.3)
    }

    @Test func growsToTheApexThenShrinksAndTurns() {
        let path = DownloadFlightPath(start: CGPoint(x: 600, y: 300), end: CGPoint(x: 30, y: 900))
        let launch = path.frame(at: 0), apex = path.frame(at: path.apexTime), arrival = path.frame(at: path.duration)
        #expect(launch.diameter == 32)
        #expect(launch.opacity == 0, "fades in over the climb")
        #expect(abs(launch.angle + Double.pi / 4) < 1e-9, "↘ at launch")
        #expect(abs(apex.diameter - 48) < 1e-9)
        #expect(abs(apex.opacity - 1) < 1e-9)
        #expect(abs(arrival.diameter - 10) < 1e-9)
        #expect(path.frame(at: path.duration / 2).angle == 0, "↓ from halfway")
        #expect(path.frame(at: path.duration + 5) == arrival, "clamped to the flight")
    }
}
