import Foundation
import Testing
@testable import LessMouseCore

/// StatsStore behaviour, on a temp directory with an injected clock and a
/// fixed calendar so day boundaries are exact.
@Suite(.serialized)
struct StatsStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A virtual clock the test can advance.
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
        func advance(days: Int, hours: Double = 0) {
            date = date.addingTimeInterval(Double(days) * 86_400 + hours * 3_600)
        }
    }

    private func makeStore(directory: URL, clock: Clock) -> StatsStore {
        StatsStore(directory: directory, calendar: calendar, now: { clock.date })
    }

    private func tempDirectory() -> URL {
        // The store creates its directory if missing; hand it a unique path.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-tests-\(UUID().uuidString)")
    }

    @Test func incrementAndSnapshot() {
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000)) // 2027-01-15 UTC
        let store = makeStore(directory: tempDirectory(), clock: clock)

        store.incrementCombo("cmd+c", app: "com.apple.Terminal")
        store.incrementCombo("cmd+c", app: "com.apple.Terminal")
        store.incrementCombo("backspace", app: nil)
        store.recordPatternHit("backspace-burst", app: nil)

        // Writes are queued; a flush also drains them, so read after flush.
        store.flush()

        let snapshot = store.todaySnapshot()
        #expect(snapshot.combos["cmd+c"] == 2)
        #expect(snapshot.combos["backspace"] == 1)
        #expect(snapshot.patterns["backspace-burst"] == 1)
        #expect(snapshot.totalEvents == 3)
    }

    @Test func roundtripPersistsAcrossInstances() throws {
        let directory = tempDirectory()
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))

        let first = makeStore(directory: directory, clock: clock)
        first.incrementCombo("opt+backspace", app: "com.apple.Safari")
        first.flush()

        // If the write silently failed, say so here rather than as a
        // confusing "second store read zero" two lines down.
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains("stats.json"), "flush() did not write stats.json: \(files)")

        let second = makeStore(directory: directory, clock: clock)
        #expect(second.comboCount("opt+backspace") == 1)
        #expect(second.daysObserved() == 1)
    }

    @Test func dayRolloverStartsAFreshDay() {
        let directory = tempDirectory()
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(directory: directory, clock: clock)

        store.incrementCombo("cmd+c", app: nil)
        store.flush()
        #expect(store.todaySnapshot().totalEvents == 1)

        clock.advance(days: 1, hours: 1)
        store.flush()
        #expect(store.todaySnapshot().totalEvents == 0,
                "the new day must start empty")
        #expect(store.comboCount("cmd+c", dayLimit: nil) == 1,
                "yesterday's count is still in history")
        #expect(store.daysObserved() == 1,
                "history still knows about exactly one observed day")
    }

    @Test func topCombosSortAndLimit() {
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(directory: tempDirectory(), clock: clock)

        for _ in 0..<7 { store.incrementCombo("cmd+c", app: nil) }
        for _ in 0..<3 { store.incrementCombo("backspace", app: nil) }
        store.incrementCombo("opt+left", app: nil)
        store.flush()

        let top = store.topCombos(dayLimit: 1, limit: 2)
        #expect(top.map(\.signature) == ["cmd+c", "backspace"])
        #expect(top.first?.count == 7)
    }

    @Test func pruneDropsOldDays() {
        let directory = tempDirectory()
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(directory: directory, clock: clock)

        store.incrementCombo("cmd+c", app: nil)
        clock.advance(days: 90)
        store.incrementCombo("cmd+v", app: nil)
        store.flush()
        store.prune()
        store.flush()

        #expect(store.comboCount("cmd+c", dayLimit: nil) == 0,
                "a 90-day-old count is past the 60-day retention")
        #expect(store.comboCount("cmd+v", dayLimit: nil) == 1)
    }

    @Test func corruptFileArchivesInsteadOfCrashing() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("this is not json".utf8)
            .write(to: directory.appendingPathComponent("stats.json"))

        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(directory: directory, clock: clock)

        #expect(store.todaySnapshot().totalEvents == 0)
        let archived = try #require(
            FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix("stats.corrupt-") },
            "the corrupt file should have been archived, not silently dropped")
        _ = archived
    }

    @Test func eraseAllClearsAndArchives() throws {
        let directory = tempDirectory()
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(directory: directory, clock: clock)

        store.incrementCombo("cmd+c", app: nil)
        store.flush()
        #expect(store.comboCount("cmd+c") == 1)
        #expect(FileManager.default.fileExists(atPath: store.storageURL.path),
                "flush() did not write stats.json before eraseAll")

        store.eraseAll()
        #expect(store.comboCount("cmd+c") == 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("stats.erased-") },
                "erase archives the old file for a moment of regret")
    }

    @Test func dayKeyIsPOSIXStable() {
        let date = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 UTC
        #expect(StatsStore.dayKey(for: date, calendar: calendar) == "2027-01-15")
    }
}
