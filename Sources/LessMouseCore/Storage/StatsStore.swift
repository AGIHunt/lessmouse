import Foundation

/// Local aggregate-count store. One JSON file, written atomically, readable by
/// opening it — see StatsRoot for the schema and the reasoning.
///
/// Thread model: a private serial queue owns the in-memory tree; every write
/// is a dictionary bump (O(1)), every read hops the queue and returns a value
/// snapshot. Flushing is debounced — `flushIfDue()` on the pipeline's tick, a
/// hard `flush()` on quit and sleep — so a heavy typing minute costs zero disk.
public final class StatsStore {
    private let queue = DispatchQueue(label: "lm.statsstore", qos: .utility)
    private let directory: URL
    private let calendar: Calendar
    private let now: () -> Date

    private var root = StatsRoot()
    private var suggestionStates: [String: SuggestionState] = [:]
    private var dirty = false
    private var lastFlush: Date?

    private let flushInterval: TimeInterval = 30
    private let retentionDays = 60

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public init(directory: URL,
                calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.calendar = calendar
        self.now = now

        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        load()
    }

    public var storageURL: URL { directory.appendingPathComponent("stats.json") }
    public var suggestionsURL: URL { directory.appendingPathComponent("suggestions.json") }

    // MARK: - Loading / recovery

    private func load() {
        if let data = try? Data(contentsOf: storageURL) {
            do {
                root = try JSONDecoder().decode(StatsRoot.self, from: data)
            } catch {
                // A corrupt file must never take the app down with it —
                // archive the evidence and start over empty.
                archive(storageURL, prefix: "stats.corrupt")
                root = StatsRoot()
            }
        }
        if let data = try? Data(contentsOf: suggestionsURL) {
            do {
                suggestionStates = try JSONDecoder().decode([String: SuggestionState].self, from: data)
            } catch {
                archive(suggestionsURL, prefix: "suggestions.corrupt")
                suggestionStates = [:]
            }
        }
    }

    private func archive(_ url: URL, prefix: String) {
        let target = directory.appendingPathComponent(
            "\(prefix)-\(Int(now().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: target)
    }

    // MARK: - Writes

    /// Count one signature for today, attributed to the frontmost app (empty
    /// string when unknown).
    ///
    /// The day is stamped on the calling thread at call time, not when the
    /// queued block runs — a keystroke at 23:59:59 must never land on
    /// tomorrow's page because the queue drained late.
    public func incrementCombo(_ signature: String, app: String?) {
        let key = app ?? ""
        let dayKey = Self.dayKey(for: now(), calendar: calendar)
        queue.async { [self] in
            root.days[dayKey, default: DayStats()]
                .apps[key, default: AppStats()]
                .combos[signature, default: 0] += 1
            dirty = true
        }
    }

    /// Count one detected burst of `patternID` for today (same day-stamping
    /// rule as above).
    public func recordPatternHit(_ patternID: String, app: String?) {
        let key = app ?? ""
        let dayKey = Self.dayKey(for: now(), calendar: calendar)
        queue.async { [self] in
            root.days[dayKey, default: DayStats()]
                .apps[key, default: AppStats()]
                .patterns[patternID, default: 0] += 1
            dirty = true
        }
    }

    /// Count one "this app came to the front" event for today — the raw
    /// material of the behavior-vs-keyboard triggers.
    public func recordAppActivation(_ bundleID: String?) {
        let key = bundleID ?? ""
        let dayKey = Self.dayKey(for: now(), calendar: calendar)
        queue.async { [self] in
            root.days[dayKey, default: DayStats()]
                .apps[key, default: AppStats()]
                .activations += 1
            dirty = true
        }
    }

    // MARK: - Reads

    /// Today's flattened counts, or an empty snapshot if nothing yet.
    public func todaySnapshot() -> DaySnapshot {
        snapshot(dayKey: todayKey())
    }

    /// The key today's counts file under. A date-components read, no queue
    /// hop — cheap enough for the event path, which asks on every stroke to
    /// notice the day rolling over.
    public func todayKey() -> String {
        Self.dayKey(for: now(), calendar: calendar)
    }

    /// A specific day's flattened counts (empty if absent).
    public func snapshot(dayKey: String) -> DaySnapshot {
        queue.sync { [self] in
            guard let day = root.days[dayKey] else {
                return DaySnapshot(dayKey: dayKey, combos: [:], patterns: [:])
            }
            var combos: [String: Int] = [:]
            var patterns: [String: Int] = [:]
            for app in day.apps.values {
                for (signature, count) in app.combos {
                    combos[signature, default: 0] += count
                }
                for (pattern, count) in app.patterns {
                    patterns[pattern, default: 0] += count
                }
            }
            return DaySnapshot(dayKey: dayKey, combos: combos, patterns: patterns)
        }
    }

    /// Most-used signatures across the last `dayLimit` days (nil = all time),
    /// already sorted descending and cut to `limit`.
    public func topCombos(dayLimit: Int?, limit: Int) -> [(signature: String, count: Int)] {
        let totals = comboTotals(dayLimit: dayLimit)
        return totals.sorted { lhs, rhs in
            (lhs.value, rhs.key) > (rhs.value, lhs.key)
        }.prefix(limit).map { (signature: $0.key, count: $0.value) }
    }

    /// Total count of one signature across `dayLimit` days (nil = all time).
    public func comboCount(_ signature: String, dayLimit: Int? = nil) -> Int {
        comboTotals(dayLimit: dayLimit)[signature] ?? 0
    }

    private func comboTotals(dayLimit: Int?) -> [String: Int] {
        queue.sync { [self] in
            var cutoff: String?
            if let dayLimit,
               let date = calendar.date(byAdding: .day, value: -(dayLimit - 1), to: now()) {
                cutoff = Self.dayKey(for: date, calendar: calendar)
            }
            var totals: [String: Int] = [:]
            for (dayKey, day) in root.days {
                if let cutoff, dayKey < cutoff { continue }
                for app in day.apps.values {
                    for (signature, count) in app.combos {
                        totals[signature, default: 0] += count
                    }
                }
            }
            return totals
        }
    }

    /// How many distinct days hold any data at all.
    public func daysObserved() -> Int {
        queue.sync { [self] in
            root.days.values.filter { day in
                day.apps.values.contains { !$0.combos.isEmpty || !$0.patterns.isEmpty }
            }.count
        }
    }

    /// Copy of every day on record — the trigger math for "days with
    /// browser activity" and "days with multiple apps in front" walks this.
    /// 60 days of retention makes the walk trivially cheap.
    public func daySummaries() -> [String: DayStats] {
        queue.sync { [self] in root.days }
    }

    /// Today's activation counts: total switches and distinct apps fronted.
    public func todayActivationSummary() -> (total: Int, distinctApps: Int) {
        let dayKey = Self.dayKey(for: now(), calendar: calendar)
        return queue.sync { [self] in
            let apps = root.days[dayKey]?.apps ?? [:]
            let activated = apps.values.map(\.activations).reduce(0, +)
            let distinct = apps.values.count { $0.activations > 0 }
            return (activated, distinct)
        }
    }

    // MARK: - Housekeeping

    /// Drop days older than the retention window (day rollover calls this).
    public func prune() {
        queue.async { [self] in
            guard let cutoffDate = calendar.date(byAdding: .day,
                                                 value: -retentionDays,
                                                 to: now()) else { return }
            let cutoff = Self.dayKey(for: cutoffDate, calendar: calendar)
            let before = root.days.count
            root.days = root.days.filter { $0.key >= cutoff }
            if root.days.count != before { dirty = true }
        }
    }

    /// Write to disk if anything changed and the debounce window has passed.
    public func flushIfDue() {
        let due: Bool = queue.sync {
            guard dirty else { return false }
            if let lastFlush, now().timeIntervalSince(lastFlush) < flushInterval {
                return false
            }
            return true
        }
        if due { flush() }
    }

    /// Unconditional write. Atomic, with file protection, so a crash mid-write
    /// can never leave a half file.
    public func flush() {
        let data: Data? = queue.sync { [self] in
            lastFlush = now()
            guard dirty else { return nil }
            return try? Self.encoder.encode(root)
        }
        guard let data else { return }
        do {
            try data.write(to: storageURL,
                           options: [.atomic, .completeFileProtection])
            queue.async { [self] in dirty = false }
        } catch {
            // Losing today's counts to a full disk is bad; losing the app is
            // worse. The dirty flag stays set and the next tick tries again.
        }
    }

    /// Erase everything. The old file is archived (not deleted) so "erase" is
    /// reversible for a few seconds of regret, then the store starts clean.
    public func eraseAll() {
        queue.sync { [self] in
            archive(storageURL, prefix: "stats.erased")
            archive(suggestionsURL, prefix: "suggestions.erased")
            root = StatsRoot()
            suggestionStates = [:]
            dirty = false
            lastFlush = nil
        }
    }

    // MARK: - Suggestion states (suggestions.json)

    /// Coaching states, loaded once at init. Small file, written eagerly —
    /// a lost card state is a re-nag the user already acted on.
    public func loadSuggestionStates() -> [String: SuggestionState] {
        queue.sync { [self] in suggestionStates }
    }

    public func saveSuggestionStates(_ states: [String: SuggestionState]) {
        let data = queue.sync { () -> Data? in
            suggestionStates = states
            return try? Self.encoder.encode(states)
        }
        guard let data else { return }
        try? data.write(to: suggestionsURL,
                        options: [.atomic, .completeFileProtection])
    }

    /// "2026-08-13" — local calendar, POSIX formatter so the key never varies
    /// with the user's locale settings.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
