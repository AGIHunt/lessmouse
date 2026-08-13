import Foundation
import Carbon.HIToolbox

/// A key LessMouse is willing to name. Two kinds exist, and the difference is
/// the privacy policy in miniature:
///
/// - **Navigation keys** (`isNavigation`): backspace, arrows, Home/End, …
///   Carrying no character of their own, they may be counted *bare* — a bare
///   backspace count says "text was deleted", never "what text".
/// - **Named keys**: letters, digits, punctuation. Counted **only** as part of
///   a ⌘/⌥/⌃ combination — "cmd+c: 12" is a shortcut, while a bare "e: 143"
///   would be a keystroke log, which this app does not keep.
public struct SafeKey: Hashable, Codable, Sendable {
    /// Storage token — what appears in stats.json, so it doubles as the
    /// human-audit format: "backspace", "c", "f3", "left".
    public let token: String
    /// Recordable with no ⌘/⌥/⌃ held (see above).
    public let isNavigation: Bool
    /// Glyph/label for rendering: "⌫", "C", "F3", "←".
    public let displaySymbol: String

    init(token: String, isNavigation: Bool = false, displaySymbol: String? = nil) {
        self.token = token
        self.isNavigation = isNavigation
        self.displaySymbol = displaySymbol ?? token.uppercased()
    }
}

/// Virtual keycode → SafeKey. Built once from the Carbon `kVK_*` constants —
/// no magic numbers, and every layout maps to the same virtual codes, so the
/// table is complete for anything a keyboard can send.
///
/// Unmapped codes (JIS extras, exotic media keys) still produce a SafeKey
/// with an opaque token (`k103`) but ONLY ever inside a combination — the
/// bare-text rule below keeps them from ever recording content.
public enum KeyWhitelist {
    private static let letters: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d",
        kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h",
        kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p",
        kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
        kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
    ]

    private static let digits: [Int: String] = [
        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_ANSI_0: "0",
    ]

    /// Punctuation: storage token paired with its display glyph.
    private static let punctuation: [Int: (token: String, symbol: String)] = [
        kVK_ANSI_Minus: ("minus", "−"), kVK_ANSI_Equal: ("equal", "="),
        kVK_ANSI_Comma: ("comma", ","), kVK_ANSI_Period: ("period", "."),
        kVK_ANSI_Slash: ("slash", "/"), kVK_ANSI_Backslash: ("backslash", "\\"),
        kVK_ANSI_Semicolon: ("semicolon", ";"), kVK_ANSI_Quote: ("quote", "'"),
        kVK_ANSI_LeftBracket: ("bracketLeft", "["), kVK_ANSI_RightBracket: ("bracketRight", "]"),
        kVK_ANSI_Grave: ("grave", "`"),
    ]

    private static let navigation: [Int: SafeKey] = [
        kVK_Delete: SafeKey(token: "backspace", isNavigation: true, displaySymbol: "⌫"),
        kVK_ForwardDelete: SafeKey(token: "delete", isNavigation: true, displaySymbol: "⌦"),
        kVK_LeftArrow: SafeKey(token: "left", isNavigation: true, displaySymbol: "←"),
        kVK_RightArrow: SafeKey(token: "right", isNavigation: true, displaySymbol: "→"),
        kVK_UpArrow: SafeKey(token: "up", isNavigation: true, displaySymbol: "↑"),
        kVK_DownArrow: SafeKey(token: "down", isNavigation: true, displaySymbol: "↓"),
        kVK_Home: SafeKey(token: "home", isNavigation: true, displaySymbol: "↖"),
        kVK_End: SafeKey(token: "end", isNavigation: true, displaySymbol: "↘"),
        kVK_PageUp: SafeKey(token: "pageup", isNavigation: true, displaySymbol: "⇞"),
        kVK_PageDown: SafeKey(token: "pagedown", isNavigation: true, displaySymbol: "⇟"),
        kVK_Escape: SafeKey(token: "esc", isNavigation: true, displaySymbol: "esc"),
        kVK_Tab: SafeKey(token: "tab", isNavigation: true, displaySymbol: "⇥"),
        kVK_F1: SafeKey(token: "f1", isNavigation: true, displaySymbol: "F1"),
        kVK_F2: SafeKey(token: "f2", isNavigation: true, displaySymbol: "F2"),
        kVK_F3: SafeKey(token: "f3", isNavigation: true, displaySymbol: "F3"),
        kVK_F4: SafeKey(token: "f4", isNavigation: true, displaySymbol: "F4"),
        kVK_F5: SafeKey(token: "f5", isNavigation: true, displaySymbol: "F5"),
        kVK_F6: SafeKey(token: "f6", isNavigation: true, displaySymbol: "F6"),
        kVK_F7: SafeKey(token: "f7", isNavigation: true, displaySymbol: "F7"),
        kVK_F8: SafeKey(token: "f8", isNavigation: true, displaySymbol: "F8"),
        kVK_F9: SafeKey(token: "f9", isNavigation: true, displaySymbol: "F9"),
        kVK_F10: SafeKey(token: "f10", isNavigation: true, displaySymbol: "F10"),
        kVK_F11: SafeKey(token: "f11", isNavigation: true, displaySymbol: "F11"),
        kVK_F12: SafeKey(token: "f12", isNavigation: true, displaySymbol: "F12"),
    ]

    /// The complete table, keyed by the Carbon constants as imported (Int).
    /// Lookup is a dictionary hit — no per-event allocation.
    private static let rawTable: [Int: SafeKey] = {
        var map = navigation
        for (code, letter) in letters {
            map[code] = SafeKey(token: letter, displaySymbol: letter.uppercased())
        }
        for (code, digit) in digits {
            map[code] = SafeKey(token: digit, displaySymbol: digit)
        }
        for (code, entry) in punctuation {
            map[code] = SafeKey(token: entry.token, displaySymbol: entry.symbol)
        }
        return map
    }()

    /// UInt16-keyed view of the table — the shape the hot path wants.
    public static let table: [UInt16: SafeKey] = {
        var map: [UInt16: SafeKey] = [:]
        for (code, key) in rawTable where (0...Int(UInt16.max)).contains(code) {
            map[UInt16(code)] = key
        }
        return map
    }()

    /// Named key for a keycode, if the table has one.
    public static func namedKey(for keyCode: UInt16) -> SafeKey? {
        table[keyCode]
    }

    /// token → display symbol, for turning stored signatures ("cmd+c") back
    /// into glyphs ("⌘C") on the stats page.
    public static let displayByToken: [String: String] = {
        var map: [String: String] = [:]
        for key in table.values {
            map[key.token] = key.displaySymbol
        }
        return map
    }()

    /// Opaque-but-honest fallback for a keycode outside the table (JIS yen,
    /// media keys…). Only ever reachable inside a ⌘/⌥/⌃ combination.
    public static func rawKey(for keyCode: UInt16) -> SafeKey {
        SafeKey(token: "k\(keyCode)", displaySymbol: "k\(keyCode)")
    }
}
