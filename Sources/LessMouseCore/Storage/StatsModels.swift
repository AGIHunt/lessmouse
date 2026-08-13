import Foundation

/// stats.json, schema v1.
///
/// The whole store is one human-readable JSON file so the privacy promise is
/// checkable by opening the file — no database, no binary blobs. Shapes:
///
///     {
///       "version": 1,
///       "days": {
///         "2026-08-13": {
///           "apps": {
///             "com.apple.Terminal": {
///               "combos": { "cmd+c": 12, "backspace": 87 },
///               "patterns": { "backspace-burst": 4 }
///             }
///           }
///         }
///       }
///     }
///
/// The empty string keys an unknown/unnamed app. Suggestion states live in a
/// sibling file (suggestions.json) rather than in here: counts and coaching
/// state change on different rhythms, and splitting them keeps each file
/// obvious to read.
public struct StatsRoot: Codable, Equatable {
    public var version: Int
    public var days: [String: DayStats]

    public init(version: Int = 1, days: [String: DayStats] = [:]) {
        self.version = version
        self.days = days
    }
}

public struct DayStats: Codable, Equatable {
    public var apps: [String: AppStats]

    public init(apps: [String: AppStats] = [:]) {
        self.apps = apps
    }
}

public struct AppStats: Codable, Equatable {
    /// Signature storageKey → count ("cmd+c": 12, "backspace": 87).
    public var combos: [String: Int]
    /// Pattern id → times the burst fired today ("backspace-burst": 4).
    public var patterns: [String: Int]

    public init(combos: [String: Int] = [:], patterns: [String: Int] = [:]) {
        self.combos = combos
        self.patterns = patterns
    }
}

/// Flattened read model for "today" — what the popover header and the ledger
/// show. Aggregated across apps because neither screen is per-app yet.
public struct DaySnapshot: Equatable {
    public let dayKey: String
    public let combos: [String: Int]
    public let patterns: [String: Int]

    public var totalEvents: Int { combos.values.reduce(0, +) }
    public var totalPatterns: Int { patterns.values.reduce(0, +) }

    public init(dayKey: String, combos: [String: Int], patterns: [String: Int]) {
        self.dayKey = dayKey
        self.combos = combos
        self.patterns = patterns
    }

    public static let emptyDayKey = ""
}
