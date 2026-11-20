import CraCore
import Foundation

/// Pause All Media (GitHub #438; CraCore's MediaPause decides which pages and what to say): the
/// command bar's command, as PauseAllMedia.swift on the Mac. Stock CEF has no Cra.pauseMedia and
/// doesn't say whether a page makes sound, so each page's own script pauses its players and says
/// what it paused (MediaPauseProbe); frames from other sites are paused too, unheard.
@MainActor
enum PauseAllMedia {
    /// A loaded page and how to reach it.
    struct Target {
        let page: MediaPause.Page
        let web: WebPage
        let title: String
        /// Brings the page on screen (the toast's Show).
        let show: () -> Void
    }

    /// Pauses every target, then reports the targets (indices into `targets`) it paused and the
    /// ones that kept playing, in the order given.
    static func run(_ targets: [Target], clock: WinScheduler, done: @escaping (MediaPause.Report<Int>) -> Void) {
        guard !targets.isEmpty else { return done(.init()) }
        var outcomes = [MediaPause.Outcome?](repeating: nil, count: targets.count)
        var left = targets.count
        var timeouts: [ScheduledWork] = []
        for (i, target) in targets.enumerated() {
            var answered = false
            let finish = { (answer: MediaPause.EngineAnswer?) in
                guard !answered else { return }
                answered = true
                outcomes[i] = MediaPause.outcome(answer: answer, playingBefore: false, playingAfter: false)
                left -= 1
                guard left == 0 else { return }
                timeouts.forEach { $0.cancel() }
                timeouts = []
                var report = MediaPause.Report<Int>()
                for (i, o) in outcomes.enumerated() { report.add(i, o ?? .quiet) }
                done(report)
            }
            target.web.executeJavaScriptInSubframes(MediaPauseProbe.subframeScript)
            target.web.sendDevToolsMethod("Runtime.evaluate", params: MediaPauseProbe.evaluateParams) { reply, error in
                let answer = MediaPauseProbe.answer(fromReply: reply)
                print("Cra: pause media \(target.title): \(answer.map { "paused \($0.paused), resisted \($0.resisted)" } ?? "no answer (\(error ?? "?"))")")
                finish(answer)
            }
            // The script answers within a second; a page that's gone, or hung, may not at all.
            timeouts.append(clock.after(3) { finish(nil) })
        }
    }
}
