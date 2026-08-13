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
                         daysObserved: Int = 1) -> EngineContext {
        EngineContext(dayKey: dayKey,
                      patternHitsToday: patternHits,
                      comboCountsToday: combos,
                      comboCountsAllTime: allTime,
                      daysObserved: daysObserved)
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

    @Test func unusedAfterDaysWaitsForAWeekOfData() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        var changes = engine.evaluate(
            context(allTime: ["cmd+grave": 0], daysObserved: 6), states: &states)
        #expect(changes.isEmpty)

        changes = engine.evaluate(
            context(allTime: ["cmd+grave": 0], daysObserved: 7), states: &states)
        #expect(changes == [.becameUnread("same-app-windows")])

        // A user who has ever used ⌘` never gets this card.
        states = [:]
        changes = engine.evaluate(
            context(allTime: ["cmd+grave": 1], daysObserved: 30), states: &states)
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
