import Foundation
import CoreGraphics

/// A menu command's keyboard shortcut, exactly as the app itself reports it.
///
/// The whole point of reading the menu instead of keeping a hand-written
/// table is that every app — first-party or not — already knows the answer.
/// The key arrives either as a virtual keycode straight from
/// `AXMenuItemCmdVirtualKey` or, for every printable character, as the
/// character itself translated back into one — so a menu's "⌘S" and a pressed
/// ⌘S produce byte-identical signatures either way. That identity is what
/// lets adoption detection work unchanged: the mouse half and the keyboard
/// half of the pipeline meet in one string.
public struct MenuShortcut: Hashable, Sendable {
    public let modifiers: ModifierSet
    public let key: SafeKey

    public init(modifiers: ModifierSet, key: SafeKey) {
        self.modifiers = modifiers
        self.key = key
    }

    /// The signature the keyboard path would have written for the same
    /// stroke ("cmd+s").
    public var signature: String {
        KeySignature(modifiers: modifiers, key: key).storageKey
    }

    /// "⌘S" — the signature as the menu itself prints it, for sentences that
    /// name the shortcut in passing.
    public var displayLabel: String {
        KeySignature(modifiers: modifiers, key: key).displaySymbols
    }

    /// The keycaps to draw, in the Mac display order (⌃⌥⇧⌘).
    public var keyCaps: [KeyCap] {
        var caps: [KeyCap] = []
        if modifiers.contains(.control) { caps.append(.modifier(.control)) }
        if modifiers.contains(.option) { caps.append(.modifier(.option)) }
        if modifiers.contains(.shift) { caps.append(.modifier(.shift)) }
        if modifiers.contains(.command) { caps.append(.modifier(.command)) }
        caps.append(.key(key.displaySymbol))
        return caps
    }

    /// Whether this is a gesture the keyboard half would ever record.
    ///
    /// `KeySignatureFilter.isCommand` is the one definition of where typing
    /// ends and commands begin; a shortcut that fails it is something a hand
    /// cannot produce as a command (a bare letter, ⇧+letter). Coaching one
    /// would write a card that can never be adopted, or one that celebrates
    /// for a keystroke meant as text.
    ///
    /// It is not the only gate. A shortcut whose modifiers carry a bit the
    /// SDK does not document — the globe (fn) key, measured on real system
    /// menus — is refused before it ever becomes a `MenuShortcut`, because
    /// the keyboard half's tap never reads `.maskSecondaryFn` and so could
    /// never confirm it.
    public var isRecordableGesture: Bool {
        KeySignatureFilter.isCommand(key, modifiers: modifiers)
    }

    /// The inverse of `signature` — nil when the stored form names a key the
    /// whitelist cannot draw as a keycap (an unmapped keycode), because a
    /// card that cannot show what to press is not a card.
    public init?(signature: String) {
        var modifiers: ModifierSet = []
        var token: String?
        for part in signature.split(separator: "+") {
            switch String(part) {
            case "cmd": modifiers.insert(.command)
            case "ctrl": modifiers.insert(.control)
            case "opt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default: token = String(part)
            }
        }
        guard let token,
              let key = KeyWhitelist.table.values.first(where: { $0.token == token })
        else { return nil }
        self.init(modifiers: modifiers, key: key)
    }
}

/// One left mouse press, reduced to what the tracker needs: where it happened
/// and which app was in front.
///
/// The point is a screen coordinate, used to hit-test a menu and then dropped
/// — nothing about *where* the user clicks is ever stored. What survives a
/// click is at most a signature string.
public struct MenuClick: Equatable, Sendable {
    /// Global display coordinates, top-left origin — the space both a
    /// `CGEvent` and an accessibility position report.
    public let point: CGPoint
    /// Frontmost app bundle id at press time, nil if unknown.
    public let application: String?
    /// Frontmost app's process id — the handle menus are read through.
    public let pid: pid_t?

    public init(point: CGPoint, application: String?, pid: pid_t?) {
        self.point = point
        self.application = application
        self.pid = pid
    }
}

/// One element of a menu, reduced to the facts LessMouse may keep: where it
/// sits on screen, whether it can run, and the shortcut printed beside it.
///
/// The title is deliberately **not** in here. Menu bars carry the user's data
/// — open filenames, window names, account names, document titles — and none
/// of it is needed to name a shortcut. Reading only position, shortcut and
/// enabled attributes keeps that boundary structural rather than a promise:
/// there is no field for the title to leak into.
public struct MenuItemSnapshot {
    /// Global display coordinates (top-left origin), the same space a
    /// `CGEvent` reports.
    public let frame: CGRect
    public let shortcut: MenuShortcut?
    /// Whether the command can run. A greyed-out item does nothing when
    /// clicked — it does not even close the menu — so it was never used, and
    /// counting it would teach a shortcut the user cannot press.
    public let isEnabled: Bool
    /// The items inside this element's menu, read on demand.
    ///
    /// A closure rather than an array because reading a menu's contents costs
    /// an accessibility round trip per item, and a menu bar has a dozen menus
    /// in it. The tracker only ever opens the one menu the user opened.
    public let openMenu: (() -> [MenuItemSnapshot])?

    public init(frame: CGRect,
                shortcut: MenuShortcut? = nil,
                isEnabled: Bool = true,
                openMenu: (() -> [MenuItemSnapshot])? = nil) {
        self.frame = frame
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.openMenu = openMenu
    }
}

/// The one door into another app's menus.
///
/// Implemented over the accessibility API (`AXMenuAccessibility`); everything
/// above it works on the snapshots, which is what makes the interesting half
/// of the menu coach unit-testable without a menu bar.
public protocol MenuAccessibilityReading: AnyObject {
    /// Whether this process may read another app's UI at all.
    ///
    /// False on a machine where the user never granted Accessibility. The
    /// feature stays dormant in that case — LessMouse never asks for it on
    /// its own; the user opts in from Settings.
    var isAvailable: Bool { get }

    /// The app's menu bar items, left to right, or nil when the app exposes
    /// no menu bar to the accessibility API.
    ///
    /// Slow by nature: the app being read has to answer, and one that has
    /// stopped answering (`kill -STOP`, a hung modal) makes this wait for it.
    /// Callers must therefore be off the main actor — see `MenuClickTracker`.
    func menuBarItems(pid: pid_t) -> [MenuItemSnapshot]?
}
