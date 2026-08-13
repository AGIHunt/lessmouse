import Foundation

/// Localization façade.
///
/// Strings live in `Resources/{en,zh-Hans}.lproj/Localizable.strings`.
///
/// Language follows the system preference by default and can be overridden in
/// Settings. A manual switch is worth having even though macOS convention says
/// otherwise: this app ships exactly two languages and its whole window is a
/// menu bar popover, so "quit, open System Settings, find the app, set a
/// language, relaunch" is a lot of ceremony for a toggle.
public enum Loc {
    private static let overrideKey = "lm.language"

    /// The languages that actually ship, in menu order. Read from the bundle
    /// rather than hard-coded, so adding an `.lproj` is all it takes to offer
    /// one more.
    public static var available: [String] {
        Bundle.module.localizations
            .filter { $0 != "Base" }
            .sorted()
    }

    /// Explicit language choice, or nil to follow the system.
    public static var override: String? {
        get { UserDefaults.standard.string(forKey: overrideKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: overrideKey)
            }
            cachedBundle = nil
        }
    }

    /// The override as the popover needs it for re-identification: a stable
    /// string even when following the system.
    public static var language: String? { override }

    /// Bundle that actually matches the chosen language.
    ///
    /// A SwiftPM executable has no Info.plist, so Foundation's localization
    /// negotiation never runs and `Bundle.module` always resolves to the
    /// development language — the app would ship English-only on Chinese
    /// systems. Do the negotiation by hand: match the preferred languages
    /// against the .lproj folders that are actually bundled and load that one.
    ///
    /// Cached rather than a `let`, because the answer changes when someone
    /// picks a language; `override`'s setter clears it.
    static var bundle: Bundle {
        if let cachedBundle { return cachedBundle }
        let resolved = resolve()
        cachedBundle = resolved
        return resolved
    }

    private static var cachedBundle: Bundle?

    private static func resolve() -> Bundle {
        // An explicit choice wins outright; otherwise fall back to Apple's own
        // negotiation against the system's ordered preference list.
        let preferences = override.map { [$0] } ?? Locale.preferredLanguages
        let preferred = Bundle.preferredLocalizations(
            from: Bundle.module.localizations,
            forPreferences: preferences
        )
        if let best = preferred.first,
           let path = Bundle.module.path(forResource: best, ofType: "lproj"),
           let matched = Bundle(path: path) {
            return matched
        }
        return .module
    }

    /// Endonym for a language code — a language is always listed in itself,
    /// never translated into the language you are trying to leave.
    public static func displayName(_ code: String) -> String {
        Locale(identifier: code).localizedString(forIdentifier: code)?
            .capitalized(with: Locale(identifier: code))
            ?? code
    }

    public static func t(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key), bundle: bundle)
    }

    /// Localized `printf` template, e.g. `"stats.todayEvents" = "今日 %ld 次按键";`.
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }
}
