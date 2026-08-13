import Foundation
import Testing
@testable import LessMouseCore

/// The sliding-window state machine, with a virtual clock (timestamps are
/// just numbers — no sleeping in tests).
@Suite struct PatternDetectorTests {
    private func detector() -> PatternDetector {
        PatternDetector(specs: PatternLibrary.defaults)
    }

    @Test func fiveBackspacesInTwoSecondsFireOnce() {
        let detector = detector()
        for t in [0.0, 0.3, 0.7, 1.2, 1.8] {
            let hits = detector.feed(signature: "backspace", at: t)
            if t == 1.8 {
                #expect(hits.map(\.id) == ["backspace-burst"])
            } else {
                #expect(hits.isEmpty)
            }
        }
        // The sixth backspace starts a new window — one burst, not two.
        let extra = detector.feed(signature: "backspace", at: 1.9)
        #expect(extra.isEmpty)
    }

    @Test func slowBackspacesNeverFire() {
        let detector = detector()
        for t in stride(from: 0.0, through: 4.0, by: 1.0) {
            #expect(detector.feed(signature: "backspace", at: t).isEmpty)
        }
    }

    @Test func exactlyAtTheWindowEdgeStillFires() {
        // Inclusive boundary: the 5th press exactly 2.0s after the 1st is
        // still a burst.
        let detector = detector()
        for t in [0.0, 0.5, 1.0, 1.5] {
            _ = detector.feed(signature: "backspace", at: t)
        }
        let hits = detector.feed(signature: "backspace", at: 2.0)
        #expect(hits.map(\.id) == ["backspace-burst"])
    }

    @Test func leftAndRightMixInOneFamily() {
        let detector = detector()
        _ = detector.feed(signature: "left", at: 0)
        _ = detector.feed(signature: "right", at: 0.2)
        _ = detector.feed(signature: "right", at: 0.4)
        let hits = detector.feed(signature: "left", at: 0.6)
        #expect(hits.map(\.id) == ["harrow-burst"])
    }

    @Test func shiftArrowsAreTheirOwnFamily() {
        let subject = detector()
        // The 4th shift+arrow fires the selection burst…
        var hits: [PatternSpec] = []
        for t in [0.0, 0.2, 0.4, 0.6] {
            hits = subject.feed(signature: "shift+left", at: t)
        }
        #expect(hits.map(\.id) == ["shift-arrow-burst"])

        // …and a plain-arrow run does not feed the selection family.
        let plain = detector()
        for t in [0.0, 0.2, 0.4] {
            _ = plain.feed(signature: "left", at: t)
        }
        #expect(plain.feed(signature: "right", at: 0.6).map(\.id) == ["harrow-burst"])
    }

    @Test func verticalArrowsNeedTheirHigherBar() {
        let detector = detector()
        for i in 0..<11 {
            #expect(detector.feed(signature: "up", at: Double(i) * 0.1).isEmpty)
        }
        let hits = detector.feed(signature: "down", at: 1.1)
        #expect(hits.map(\.id) == ["varrow-burst"])
    }

    @Test func unrelatedSignaturesAreIgnored() {
        let detector = detector()
        for i in 0..<20 {
            #expect(detector.feed(signature: "cmd+c", at: Double(i) * 0.05).isEmpty)
        }
    }

    @Test func resetAllEndsWindowsInProgress() {
        let detector = detector()
        for t in [0.0, 0.3, 0.6] {
            _ = detector.feed(signature: "backspace", at: t)
        }
        detector.resetAll()
        // Only four fresh presses after a reset — one short of a burst.
        for t in [1.0, 1.1, 1.2, 1.3] {
            #expect(detector.feed(signature: "backspace", at: t).isEmpty)
        }
        #expect(detector.feed(signature: "backspace", at: 1.4).map(\.id) == ["backspace-burst"])
    }
}
