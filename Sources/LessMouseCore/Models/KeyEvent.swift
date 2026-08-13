import Foundation

/// The four modifiers that change what a key *means*. Caps lock (alphaShift)
/// and fn (secondaryFn) are stripped before a `KeyEvent` is built: the former
/// is a keyboard layout state, the latter rides along on synthesized keys
/// (fn+← *is* Home, and the Home keycode already says so). The numeric-pad
/// flag arrives on arrow keys and carries no meaning we record.
public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let control = ModifierSet(rawValue: 1 << 2)
    public static let shift = ModifierSet(rawValue: 1 << 3)

    /// Any of the three modifiers that turn a keystroke from "text" into
    /// "command". ⌘C, ⌥⌫ and ⌃A are combinations; ⇧A is just an uppercase A.
    public var hasCommandModifier: Bool {
        contains(.command) || contains(.option) || contains(.control)
    }

    /// Stable storage order — ⌘ first (it reads as the primary verb:
    /// "cmd+shift+s"), then ⌃, ⌥, ⇧. The same stroke always writes the same
    /// string.
    public var storageTokens: [String] {
        var tokens: [String] = []
        if contains(.command) { tokens.append("cmd") }
        if contains(.control) { tokens.append("ctrl") }
        if contains(.option) { tokens.append("opt") }
        if contains(.shift) { tokens.append("shift") }
        return tokens
    }

    /// Display order follows the Mac menu convention (⌃⌥⇧⌘ — the system
    /// prints Shift-Command-N as "⇧⌘N").
    public var displaySymbols: [String] {
        var symbols: [String] = []
        if contains(.control) { symbols.append("⌃") }
        if contains(.option) { symbols.append("⌥") }
        if contains(.shift) { symbols.append("⇧") }
        if contains(.command) { symbols.append("⌘") }
        return symbols
    }
}

/// One keystroke, already stripped of layout noise. This is the value the
/// whole pipeline works on — the CGEventTap layer converts to it and is never
/// seen again, which is what makes everything downstream unit-testable.
public struct KeyEvent: Equatable, Sendable {
    /// Monotonic clock seconds, injected so tests can virtualize time.
    public let timestamp: TimeInterval
    /// Carbon virtual keycode — a keyboard *position*, layout-independent.
    public let keyCode: UInt16
    public let modifiers: ModifierSet
    /// Held-down autorepeat. Counting repeats as presses would let one long
    /// hold impersonate a burst, so they never become events at all.
    public let isAutorepeat: Bool
    /// Frontmost app bundle id at press time, nil if unknown.
    public let application: String?

    public init(timestamp: TimeInterval,
                keyCode: UInt16,
                modifiers: ModifierSet,
                isAutorepeat: Bool = false,
                application: String? = nil) {
        self.timestamp = timestamp
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isAutorepeat = isAutorepeat
        self.application = application
    }
}
