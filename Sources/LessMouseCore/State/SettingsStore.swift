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
        static let menuCoach = "lm.menuCoach"
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

    /// Whether menu commands chosen with the mouse are coached too — the half
    /// of the book that reads other apps' menus.
    ///
    /// Off by default. The permission it needs is checked, never requested, so
    /// without Accessibility the coach is simply dormant — but a default that
    /// watches every mouse press in the system asks every user to *decline* a
    /// feature they never asked for, and the ones who never granted
    /// Accessibility are watched for nothing at all. So the coach is something
    /// you turn on: Settings is where a user opts in, and while it is off the
    /// tap watches the keyboard alone and no accessibility call is made.
    @Published public var isMenuCoachEnabled: Bool {
        didSet {
            if isMenuCoachEnabled != oldValue {
                defaults.set(isMenuCoachEnabled, forKey: Key.menuCoach)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: Key.paused)
        self.excludedApps = Set(defaults.stringArray(forKey: Key.excludedApps) ?? [])
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        // A missing key means "never decided", which is off — the user turns
        // the coach on in Settings rather than finding it already listening.
        self.isMenuCoachEnabled = defaults.object(forKey: Key.menuCoach) == nil
            ? false
            : defaults.bool(forKey: Key.menuCoach)
    }

    public func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains(bundleID)
    }
}
