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
///               "patterns": { "backspace-burst": 4 },
///               "menuCommands": { "cmd+s": 3 },
///               "activations": 2
///             }
///           }
///         }
///       }
///     }
///
/// `menuCommands` counts *mouse* clicks on menu commands that print a
/// shortcut ("cmd+s: 3" = three clicks on a Save menu item). It holds the
/// same currency as `combos` — a signature string — which is what lets the
/// two halves of the coaching book meet: clicking the menu is the habit,
/// pressing the shortcut is the cure.
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
    /// Signature → times a menu command bearing that shortcut was chosen
    /// with the mouse ("cmd+s": 3). Same currency as `combos`, so "clicked
    /// the menu 3 times, pressed the key 0 times" is one comparison.
    public var menuCommands: [String: Int]
    /// Times this app came to the front today — the "behavior" side of the
    /// behavior-vs-keyboard trigger math (e.g. app switching without ⌘Tab).
    public var activations: Int

    public init(combos: [String: Int] = [:], patterns: [String: Int] = [:],
                menuCommands: [String: Int] = [:],
                activations: Int = 0) {
        self.combos = combos
        self.patterns = patterns
        self.menuCommands = menuCommands
        self.activations = activations
    }

    private enum CodingKeys: String, CodingKey {
        case combos, patterns, menuCommands, activations
    }

    /// Hand-rolled so files written before `menuCommands` (or before
    /// `activations`) existed still decode — the field simply reads as zero.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combos = try container.decodeIfPresent([String: Int].self, forKey: .combos) ?? [:]
        patterns = try container.decodeIfPresent([String: Int].self, forKey: .patterns) ?? [:]
        menuCommands = try container.decodeIfPresent([String: Int].self, forKey: .menuCommands) ?? [:]
        activations = try container.decodeIfPresent(Int.self, forKey: .activations) ?? 0
    }
}

/// Flattened read model for "today" — what the popover header and the ledger
/// show. Aggregated across apps because neither screen is per-app yet.
public struct DaySnapshot: Equatable {
    public let dayKey: String
    public var combos: [String: Int]
    public var patterns: [String: Int]
    /// Mouse clicks on menu commands that have a shortcut, by signature.
    public var menuCommands: [String: Int]

    public var totalEvents: Int { combos.values.reduce(0, +) }
    public var totalPatterns: Int { patterns.values.reduce(0, +) }
    public var totalMenuCommands: Int { menuCommands.values.reduce(0, +) }

    public init(dayKey: String, combos: [String: Int], patterns: [String: Int],
                menuCommands: [String: Int] = [:]) {
        self.dayKey = dayKey
        self.combos = combos
        self.patterns = patterns
        self.menuCommands = menuCommands
    }

    public static let emptyDayKey = ""
}
