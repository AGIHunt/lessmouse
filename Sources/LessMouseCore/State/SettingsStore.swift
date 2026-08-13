import Foundation
import Combine

/// User preferences, persisted in UserDefaults — the app's state is all local,
/// and preferences about *this Mac's* UI belong closer still.
///
/// Language is deliberately not here: `Loc.override` owns it, because the
/// localization machinery needs to read it from anywhere without reaching
/// through an object.
@MainActor
public final class SettingsStore: ObservableObject {
    private enum Key {
        static let paused = "lm.paused"
        static let excludedApps = "lm.excludedApps"
        static let launchAtLogin = "lm.launchAtLogin"
    }

    private let defaults: UserDefaults

    @Published public var isPaused: Bool {
        didSet {
            if isPaused != oldValue { defaults.set(isPaused, forKey: Key.paused) }
        }
    }

    /// Bundle ids never counted, even with modifiers — password managers and
    /// anything else the user names. Changes take effect on the next event.
    @Published public var excludedApps: Set<String> {
        didSet {
            if excludedApps != oldValue {
                defaults.set(Array(excludedApps).sorted(), forKey: Key.excludedApps)
            }
        }
    }

    /// The *preference*; the actual SMAppService registration is LoginItemService's
    /// job, and only succeeds when running from a real .app bundle.
    @Published public var launchAtLogin: Bool {
        didSet {
            if launchAtLogin != oldValue { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: Key.paused)
        self.excludedApps = Set(defaults.stringArray(forKey: Key.excludedApps) ?? [])
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }

    public func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains(bundleID)
    }
}
