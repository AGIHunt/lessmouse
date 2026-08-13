import Foundation

/// A keycap as drawn in suggestion copy — the model rules carry lists of
/// these so the teaching UI never has to parse a signature back apart.
public enum KeyCap: Hashable, Codable, Sendable {
    public enum Modifier: String, Codable, Hashable, Sendable {
        case command = "⌘"
        case option = "⌥"
        case shift = "⇧"
        case control = "⌃"
    }

    case modifier(Modifier)
    /// Glyph or short label: "⌫", "←", "A", "F1", "space"…
    case key(String)

    public var label: String {
        switch self {
        case .modifier(let modifier): return modifier.rawValue
        case .key(let label): return label
        }
    }
}

extension KeyCap: ExpressibleByStringLiteral {
    /// `.key("⌫")` reads better as just `"⌫"` in the rule library.
    public init(stringLiteral value: String) {
        self = .key(value)
    }
}
