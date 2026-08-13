import Foundation

/// Small formatting helpers shared by the views.
enum Fmt {
    /// 9 stays 9; 1_204 becomes "1.2k" — ledger numbers that don't widen rows.
    static func compactCount(_ value: Int) -> String {
        if value < 1_000 { return "\(value)" }
        if value < 10_000 {
            let units = Double(value) / 1_000
            return units.formatted(.number.precision(.fractionLength(1))) + "k"
        }
        return "\(value / 1_000)k"
    }

    /// "cmd+shift+right" → "⇧⌘→", using the whitelist's own symbols and the
    /// Mac display order (⌃⌥⇧⌘).
    static func signatureDisplay(_ storageKey: String) -> String {
        let tokens = storageKey.split(separator: "+").map(String.init)
        var symbols: [String] = []
        var keySymbol: String?
        for token in tokens {
            switch token {
            case "cmd": symbols.append("⌘")
            case "ctrl": symbols.append("⌃")
            case "opt": symbols.append("⌥")
            case "shift": symbols.append("⇧")
            default:
                keySymbol = KeyWhitelist.displayByToken[token] ?? token.uppercased()
            }
        }
        let ordered = ["⌃", "⌥", "⇧", "⌘"].filter { symbols.contains($0) }
        return (ordered + [keySymbol ?? ""]).joined()
    }
}
