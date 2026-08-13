import Foundation

/// What wakes a rule up. Three shapes cover the v1 book:
/// a burst pattern crossing its daily line, a plain usage total
/// (Home/End pressed N times today), and "enough days observed, and a
/// shortcut never once used" (⌘`).
public enum RuleTrigger: Hashable {
    case patternBursts(id: String, dailyMinimum: Int)
    case comboUsage(signatures: [String], dailyMinimum: Int)
    case comboUnusedAfterDays(signature: String, days: Int)
}

/// One coaching card: when it appears, what it teaches, how adoption is
/// recognized. Pure data — copy lives in Localizable.strings so a new
/// language is zero code.
public struct SuggestionRule: Identifiable {
    public let id: String
    public let trigger: RuleTrigger
    /// Counting any of these after the card appeared = adopted.
    public let watchForAdoption: [String]
    public let titleKey: String
    public let bodyKey: String
    /// Inbox subtitle; takes one %ld (today's trigger count).
    public let summaryKey: String
    /// Alternative shortcuts to teach, each an ordered cap list.
    public let keyCaps: [[KeyCap]]
    /// SF Symbol for the card's glyph wherever it appears.
    public let symbol: String
    /// Read-but-not-adopted cards wait this many days before nagging again.
    public let cooldownDays: Int

    public init(id: String,
                trigger: RuleTrigger,
                watchForAdoption: [String],
                titleKey: String,
                bodyKey: String,
                summaryKey: String,
                keyCaps: [[KeyCap]],
                symbol: String,
                cooldownDays: Int) {
        self.id = id
        self.trigger = trigger
        self.watchForAdoption = watchForAdoption
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.summaryKey = summaryKey
        self.keyCaps = keyCaps
        self.symbol = symbol
        self.cooldownDays = cooldownDays
    }

    /// "⌥⌫" — the first taught shortcut, for compact references like the
    /// celebration banner.
    public var primaryShortcutLabel: String {
        keyCaps.first.map { $0.map(\.label).joined() } ?? ""
    }
}

/// A card's life. dormant means "never met its threshold"; dismissed is
/// terminal — the engine never revives it.
public enum SuggestionStatus: String, Codable, Sendable {
    case dormant
    case unread
    case read
    case adopted
    case dismissed
}

public struct SuggestionState: Codable, Equatable, Identifiable {
    public var id: String { ruleID }
    public let ruleID: String
    public var status: SuggestionStatus
    public var generatedAt: Date?
    /// Today's count of each watched signature when the card was generated —
    /// adoption means exceeding the baseline, so a shortcut already in use
    /// before coaching doesn't count as coached.
    public var adoptionBaseline: [String: Int]
    public var lastNotifiedDayKey: String?
    public var celebrated: Bool

    public init(ruleID: String,
                status: SuggestionStatus = .dormant,
                generatedAt: Date? = nil,
                adoptionBaseline: [String: Int] = [:],
                lastNotifiedDayKey: String? = nil,
                celebrated: Bool = false) {
        self.ruleID = ruleID
        self.status = status
        self.generatedAt = generatedAt
        self.adoptionBaseline = adoptionBaseline
        self.lastNotifiedDayKey = lastNotifiedDayKey
        self.celebrated = celebrated
    }
}

/// What evaluate() tells the UI happened, so the menu bar dot and the
/// celebration banner react to causes instead of diffing state.
public enum SuggestionChange: Equatable {
    case becameUnread(String)
    case promotedAgain(String)
    case adopted(String)
}

/// The snapshot the engine evaluates against — everything it may look at,
/// nothing else. Built by AppState from the store.
public struct EngineContext: Equatable {
    public var dayKey: String
    public var patternHitsToday: [String: Int]
    public var comboCountsToday: [String: Int]
    public var comboCountsAllTime: [String: Int]
    public var daysObserved: Int

    public init(dayKey: String,
                patternHitsToday: [String: Int] = [:],
                comboCountsToday: [String: Int] = [:],
                comboCountsAllTime: [String: Int] = [:],
                daysObserved: Int = 0) {
        self.dayKey = dayKey
        self.patternHitsToday = patternHitsToday
        self.comboCountsToday = comboCountsToday
        self.comboCountsAllTime = comboCountsAllTime
        self.daysObserved = daysObserved
    }
}
