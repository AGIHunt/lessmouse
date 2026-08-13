import Foundation

/// The normalized, privacy-filtered form of a keystroke — the only thing the
/// store ever persists. `storageKey` is deliberately readable ("cmd+shift+right")
/// so stats.json can be audited by opening it, not by running a decoder.
public struct KeySignature: Hashable, Codable, Sendable {
    public let modifiers: ModifierSet
    public let key: SafeKey

    /// Stable, human-readable storage form: modifiers in fixed order, then the
    /// key token. Empty modifiers + navigation key → the bare token.
    public var storageKey: String {
        let tokens = modifiers.storageTokens
        return tokens.isEmpty ? key.token : (tokens + [key.token]).joined(separator: "+")
    }

    /// Display form for the ledger UI: "⌘⇧→".
    public var displaySymbols: String {
        modifiers.displaySymbols.joined() + key.displaySymbol
    }

    public init(modifiers: ModifierSet, key: SafeKey) {
        self.modifiers = modifiers
        self.key = key
    }
}

// MARK: - The privacy filter

/// The single choke point every keystroke passes through. Pure: no clock, no
/// disk, no app state — every input maps to the same output forever, which is
/// what the privacy regression tests pin down.
///
/// Three rules, in order:
///
/// 1. Autorepeat never becomes a signature (one long hold ≠ N presses).
/// 2. A key that is *not* navigation, held with *no* ⌘/⌥/⌃, is text — dropped.
///    This includes ⇧+letter: that is an uppercase letter being typed.
/// 3. Everything else — navigation keys (bare or modified) and genuine
///    combinations — becomes a signature.
public enum KeySignatureFilter {
    public static func signature(for event: KeyEvent) -> KeySignature? {
        // Rule 1.
        if event.isAutorepeat { return nil }

        let key = KeyWhitelist.namedKey(for: event.keyCode) ?? KeyWhitelist.rawKey(for: event.keyCode)

        // Rule 2. ⌘/⌥/⌃ turn a key into a command; ⇧ alone never does.
        if !event.modifiers.hasCommandModifier && !key.isNavigation {
            return nil
        }

        // Rule 3.
        return KeySignature(modifiers: event.modifiers, key: key)
    }
}
