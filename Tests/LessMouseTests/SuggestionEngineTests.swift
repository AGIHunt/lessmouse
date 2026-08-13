import Foundation
import Testing
@testable import LessMouseCore

/// The coaching state machine: thresholds, cooldowns, adoption, and the two
/// terminal states that nothing ever overrides.
@Suite struct SuggestionEngineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func engine(now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }) -> SuggestionEngine {
        SuggestionEngine(rules: RuleLibrary.all, calendar: calendar, now: now)
    }

    private func context(dayKey: String = "2027-01-15",
                         patternHits: [String: Int] = [:],
                         combos: [String: Int] = [:],
                         allTime: [String: Int] = [:],
                         appSwitches: Int = 0,
                         browserDays: Int = 0,
                         multiAppDays: Int = 0) -> EngineContext {
        EngineContext(dayKey: dayKey,
                      patternHitsToday: patternHits,
                      comboCountsToday: combos,
                      comboCountsAllTime: allTime,
                      appSwitchesToday: appSwitches,
                      browserActiveDays: browserDays,
                      multiAppActiveDays: multiAppDays)
    }

    // MARK: - Triggering

    @Test func burstThresholdCreatesUnreadCard() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        // Two bursts today: below the line of 3.
        var changes = engine.evaluate(context(patternHits: ["backspace-burst": 2]), states: &states)
        #expect(changes.isEmpty)
        #expect(states["delete-by-word"] == nil)

        // Three bursts: card.
        changes = engine.evaluate(context(patternHits: ["backspace-burst": 3]), states: &states)
        #expect(changes == [.becameUnread("delete-by-word")])
        #expect(states["delete-by-word"]?.status == .unread)
    }

    @Test func comboUsageTriggerFiresHomeEnd() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        // Home + End combined below the line of 3.
        var changes = engine.evaluate(context(combos: ["home": 1, "end": 1]), states: &states)
        #expect(changes.isEmpty)

        // Combined usage reaches 3 — the card appears.
        changes = engine.evaluate(context(combos: ["home": 2, "end": 1]), states: &states)
        #expect(changes == [.becameUnread("home-end-mac")])
        #expect(states["home-end-mac"]?.status == .unread)
    }

    @Test func browserUseWithoutCtrlTabFiresAfterThreeDays() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        // Two days of browsing, ⌃⇥ never pressed: not yet.
        var changes = engine.evaluate(
            context(allTime: ["ctrl+tab": 0], browserDays: 2), states: &states)
        #expect(changes.isEmpty)

        // Third day: the card.
        changes = engine.evaluate(
            context(allTime: ["ctrl+tab": 0], browserDays: 3), states: &states)
        #expect(changes == [.becameUnread("tab-switching")])

        // Anyone who ever pressed ⌃⇥ never sees it.
        states = [:]
        changes = engine.evaluate(
            context(allTime: ["ctrl+tab": 1], browserDays: 30), states: &states)
        #expect(changes.isEmpty)
    }

    @Test func multiAppUseWithoutCmdGraveFiresSameAppWindows() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        var changes = engine.evaluate(
            context(allTime: ["cmd+grave": 0], multiAppDays: 2), states: &states)
        #expect(changes.isEmpty)

        changes = engine.evaluate(
            context(allTime: ["cmd+grave": 0], multiAppDays: 3), states: &states)
        #expect(changes == [.becameUnread("same-app-windows")])

        states = [:]
        changes = engine.evaluate(
            context(allTime: ["cmd+grave": 1], multiAppDays: 30), states: &states)
        #expect(changes.isEmpty)
    }

    @Test func heavyMouseSwitchingFiresAppSwitching() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        // 14 switches: below the volume gate.
        #expect(engine.evaluate(context(combos: ["cmd+tab": 0], appSwitches: 14),
                                states: &states).isEmpty)

        // 20 switches, ⌘Tab used once: a mouse switcher — card.
        var changes = engine.evaluate(context(combos: ["cmd+tab": 1], appSwitches: 20),
                                      states: &states)
        #expect(changes == [.becameUnread("app-switching")])

        // 20 switches, ⌘Tab used 10 of them: knows the shortcut, no card.
        states = [:]
        changes = engine.evaluate(context(combos: ["cmd+tab": 10], appSwitches: 20),
                                  states: &states)
        #expect(changes.isEmpty)
    }

    // MARK: - Terminal states

    @Test func dismissedIsForever() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        _ = engine.evaluate(context(patternHits: ["backspace-burst": 3]), states: &states)
        engine.dismiss("delete-by-word", states: &states)
        #expect(states["delete-by-word"]?.status == .dismissed)

        // Even a fresh trigger on a later day never revives it.
        let changes = engine.evaluate(context(dayKey: "2027-01-20",
                                              patternHits: ["backspace-burst": 9]),
                                      states: &states)
        #expect(!changes.contains(.becameUnread("delete-by-word")))
        #expect(states["delete-by-word"]?.status == .dismissed)
    }

    @Test func markReadAndCooldown() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        _ = engine.evaluate(context(patternHits: ["backspace-burst": 3]), states: &states)
        engine.markRead("delete-by-word", states: &states)
        #expect(states["delete-by-word"]?.status == .read)

        // Next day, still triggered: cooldown (3 days) holds it down.
        var changes = engine.evaluate(context(dayKey: "2027-01-16",
                                              patternHits: ["backspace-burst": 5]),
                                      states: &states)
        #expect(changes.isEmpty)

        // Day 4: it may nag again.
        changes = engine.evaluate(context(dayKey: "2027-01-19",
                                          patternHits: ["backspace-burst": 5]),
                                  states: &states)
        #expect(changes == [.promotedAgain("delete-by-word")])
        #expect(states["delete-by-word"]?.status == .unread)
    }

    // MARK: - Adoption

    @Test func adoptionCrossesTheBaselineOnce() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        _ = engine.evaluate(context(patternHits: ["backspace-burst": 3]), states: &states)

        // Baseline was captured at generation: opt+backspace at 0 today.
        #expect(states["delete-by-word"]?.adoptionBaseline["opt+backspace"] == 0)

        let adopted = engine.onComboObserved(signature: "opt+backspace",
                                             todayCount: 1, states: &states)
        #expect(adopted == "delete-by-word")
        #expect(states["delete-by-word"]?.status == .adopted)

        // Second use: already adopted, nothing new to celebrate.
        let again = engine.onComboObserved(signature: "cmd+backspace",
                                           todayCount: 1, states: &states)
        #expect(again == nil)
    }

    @Test func useBeforeCoachingIsNotAdoption() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        // ⌥⌫ already used 4 times today when the card appears.
        _ = engine.evaluate(context(patternHits: ["backspace-burst": 3],
                                    combos: ["opt+backspace": 4]), states: &states)
        #expect(states["delete-by-word"]?.adoptionBaseline["opt+backspace"] == 4)

        let early = engine.onComboObserved(signature: "opt+backspace",
                                           todayCount: 5, states: &states)
        #expect(early == "delete-by-word",
                "exceeding the baseline by using it more still counts — the shortcut is spreading")
    }

    @Test func adoptionOnlyCountsForLiveCards() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        // No card has ever been generated: using ⌥⌫ is just good behavior.
        let adopted = engine.onComboObserved(signature: "opt+backspace",
                                             todayCount: 3, states: &states)
        #expect(adopted == nil)
    }
}
