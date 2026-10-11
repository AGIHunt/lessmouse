import Foundation
import AppKit
import ApplicationServices.HIServices

/// The one place LessMouse talks to the accessibility API.
///
/// Why the accessibility API at all: it is the only thing on macOS that can
/// answer "what is the shortcut printed next to the command under the
/// cursor?" for *any* app, first-party or not, without a hand-written table
/// of menus that would be wrong the day after it was written. Every AppKit
/// app already exposes its menu bar here.
///
/// What this file is careful about:
///
/// - **It reads seven attributes and no more.** Position and size (where the
///   item is), role (whether it is the menu wrapper AppKit inserts, whose
///   children are the commands), enabled (whether the command can run at all),
///   and the shortcut's keycode, character, and modifier mask. The item's
///   *title* is never requested, so a filename or an account name sitting in a
///   menu has no path into LessMouse.
/// - **It never writes.** Read-only attribute queries; nothing is sent back
///   to the other app.
/// - **It never runs on the main actor.** The tracker calls it from a serial
///   queue of its own, because reading another app's menu means waiting for
///   that app — and an app that has stopped answering makes the accessibility
///   API wait with it.
public final class AXMenuAccessibility: MenuAccessibilityReading {
    public init() {}

    public var isAvailable: Bool {
        // A check, never a prompt: the user grants Accessibility from
        // Settings or not at all, and LessMouse does not ask for it.
        AXIsProcessTrusted()
    }

    public func menuBarItems(pid: pid_t) -> [MenuItemSnapshot]? {
        guard isAvailable else { return nil }
        return readMenuBar(pid: pid)
    }

    /// The read itself, with no trust gate.
    ///
    /// The gate above is about *other* apps: reading another process's UI is
    /// what Accessibility permission is for. A process reading its *own* UI
    /// needs no grant at all, so this entry point is what exercises the real
    /// reading path — attributes, shortcut resolution, layout translation — on
    /// a machine where the permission was never given. `MenuClickTracker` never
    /// reaches for it, because the app being read is never this one.
    ///
    /// Kept `internal` rather than deleted after verification: it is how the
    /// reading half is checked against real accessibility data instead of
    /// against a hand-built `AXUIElement` that cannot be built in a test.
    /// How long any single accessibility read will wait for the app being
    /// read, in seconds.
    ///
    /// The read already runs on the tracker's own serial queue, off the main
    /// actor, so a slow app only ever delayed the coach. What it delayed it
    /// *past* was the menu: a click queued behind a hung app arrived after
    /// the menu had closed, so the habit was lost and the coach looked
    /// broken for a reason no card could explain. Measured on macOS 27: a
    /// healthy app answers in ~0.1s, an app stopped with `kill -STOP` takes
    /// ~1.5s per element. A quarter of a second clears the healthy case with
    /// room to spare and bounds the hung one to a quarter second per click,
    /// which is short enough that the click after it still lands while the
    /// menu is on screen.
    ///
    /// Internal rather than private so a test can bound it; the hung-app
    /// behaviour itself is measured by the verification tool.
    static let messagingTimeout: Float = 0.25

    /// Bound every read this element is asked for to `messagingTimeout`.
    ///
    /// Set per element rather than once on the application: an element
    /// obtained from a parent's attribute is a fresh object with the default
    /// timeout, so a timeout set only at the top would not survive the walk
    /// down to the commands — which is exactly where the slow read happens.
    private static func arm(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    func readMenuBar(pid: pid_t) -> [MenuItemSnapshot]? {
        let app = AXUIElementCreateApplication(pid)
        Self.arm(app)
        guard let bar = element(app, attribute: kAXMenuBarAttribute) else { return nil }
        let items = children(of: bar)
        // An app with an empty menu bar (a game, a full-screen kiosk) reads
        // the same as one we cannot read at all: nothing to coach.
        return items.isEmpty ? nil : items
    }

    // MARK: - Reading

    /// The attributes one menu element is read for. Deliberately a closed
    /// list: adding `AXTitle` here would break the privacy promise above.
    private enum Attribute: Int, CaseIterable {
        case role, position, size, keyCode, character, modifierMask, isEnabled

        var name: String {
            switch self {
            case .role: return kAXRoleAttribute
            case .position: return kAXPositionAttribute
            case .size: return kAXSizeAttribute
            case .keyCode: return kAXMenuItemCmdVirtualKeyAttribute
            case .character: return kAXMenuItemCmdCharAttribute
            case .modifierMask: return kAXMenuItemCmdModifiersAttribute
            case .isEnabled: return kAXEnabledAttribute
            }
        }
    }

    private func element(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        Self.arm(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// The menu items under `element`, flattened one level.
    ///
    /// AppKit hangs an `AXMenu` between a menu bar item and the commands in
    /// it, so a menu bar item's children are not yet the commands. Stepping
    /// through that one wrapper is what makes a menu bar item's menu look
    /// like a flat list of commands to the tracker.
    private func children(of element: AXUIElement) -> [MenuItemSnapshot] {
        Self.arm(element)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let childElements = elements(raw)
        else { return [] }

        var items: [MenuItemSnapshot] = []
        for child in childElements {
            let facts = Self.facts(of: child)
            if facts.role == kAXMenuRole {
                items.append(contentsOf: children(of: child))
                continue
            }
            guard let frame = facts.frame else { continue }
            items.append(MenuItemSnapshot(
                frame: frame,
                shortcut: facts.shortcut,
                isEnabled: facts.isEnabled,
                openMenu: { [weak self] in self?.children(of: child) ?? [] }
            ))
        }
        return items
    }

    /// One element, read in a single round trip. An attribute the element
    /// does not support comes back as an error `AXValue` in its slot rather
    /// than as a failed call, so errors are filtered per attribute instead of
    /// losing the whole read.
    private static func facts(of element: AXUIElement) -> Facts {
        arm(element)
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            element, Attribute.allCases.map(\.name) as CFArray, [], &values
        ) == .success, let values = values as? [AnyObject] else { return Facts() }

        var facts = Facts()
        // The answer array is parallel to the request; a slot the element
        // could not fill holds an error value rather than the thing asked for.
        for (index, value) in values.enumerated() {
            guard let attribute = Attribute(rawValue: index), !isError(value) else { continue }
            switch attribute {
            case .role: facts.role = value as? String
            case .position: facts.origin = point(value)
            case .size: facts.size = size(value)
            case .keyCode: facts.keyCode = integer(value)
            case .character: facts.character = value as? String
            case .modifierMask: facts.modifierMask = integer(value)
            case .isEnabled: facts.isEnabled = (value as? NSNumber)?.boolValue ?? true
            }
        }
        return facts
    }

    private struct Facts {
        var role: String?
        var origin: CGPoint?
        var size: CGSize?
        var keyCode: Int?
        var character: String?
        var modifierMask: Int?
        /// Optimistic when unreadable: the attribute answers for every element
        /// AppKit builds a menu out of, and a command wrongly thought disabled
        /// would silently stop being coached.
        var isEnabled = true

        var frame: CGRect? {
            guard let origin, let size else { return nil }
            return CGRect(origin: origin, size: size)
        }

        /// The shortcut this item prints beside its title, or nil when it has
        /// none — the ordinary case for a menu bar item like "Edit".
        ///
        /// The keycode attribute is tried first because it is exact, but it
        /// only answers for function and special keys: ⌘↑ arrives as 126 while
        /// ⌘S arrives as `kAXErrorNoValue`, because AppKit reports a virtual
        /// keycode only where the key equivalent is not a character. Every
        /// printable shortcut therefore has to come from the character, which
        /// is translated back to the keycode the keyboard half would report —
        /// see `KeyboardLayoutKeys` for why that translation is the layout's
        /// job and not a constant.
        ///
        /// Both paths end in the same test the keyboard half applies to every
        /// keystroke, so what the menu half can teach and what the keyboard
        /// half can record are the same set of gestures. Without that, the menu
        /// half has its own, looser idea of where typing ends, and two things
        /// go wrong at once: a menu whose character is a bare letter (⇧A,
        /// plain A) starts writing typing-shaped signatures into stats.json,
        /// which the privacy promise says never happens, and a shortcut whose
        /// modifiers are unreadable gets decoded into a different, real
        /// shortcut — which is how 🌐⌃C used to be taught as ⌃C, and
        /// celebrated the next time ⌃C was pressed in a terminal.
        var shortcut: MenuShortcut? {
            AXMenuAccessibility.shortcut(fromKeyCode: keyCode,
                                         character: character,
                                         modifierMask: modifierMask)
        }
    }

    /// What an item's raw accessibility readings describe, or nil when they
    /// describe nothing a card can teach.
    ///
    /// Pure, and taking the numbers an element reports rather than an element,
    /// so a test can drive the whole translation with the readings a real menu
    /// produces — the fn and bare-letter cases are ordinary readings, not
    /// exotic ones, and this is where they are decided.
    static func shortcut(fromKeyCode keyCode: Int?,
                         character: String?,
                         modifierMask: Int?) -> MenuShortcut? {
        // A mask the element did not report is a mask of zero: ⌘ alone.
        // Absence of the attribute is absence of a *value*, not absence of a
        // shortcut — zero is the value that names no modifier — and reading
        // it as "no shortcut" would silently drop a ⌘S from an app that
        // reports its key equivalent without its mask. Rare (measured on
        // real machines the mask is always there when the character is), and
        // cheap to honour.
        let mask = modifierMask ?? 0
        // Refused before anything is decoded, because the mask it produces is
        // indistinguishable from one that means something else.
        guard !carriesAnUnverifiableModifier(mask: mask) else { return nil }
        let modifiers = modifiers(mask: mask)
        if let keyCode, let key = KeyWhitelist.table[UInt16(keyCode)] {
            return teachable(key, modifiers: modifiers)
        }
        if let character,
           let answer = KeyboardLayoutKeys.key(forCharacter: character),
           let key = KeyWhitelist.table[answer.code] {
            // A menu that prints a shifted character — ⌘*, ⌘?, ⌘} — declares
            // ⌘ and stores the character: the shift is carried by the
            // character, because there is no way to press "*" without it.
            // Declared rather than inferred it away, this would name ⌘8
            // where the keyboard half names ⇧⌘8, and the two halves would
            // never meet on one string.
            var modifiers = modifiers
            if answer.needsShift { modifiers.insert(.shift) }
            return teachable(key, modifiers: modifiers)
        }
        // A keycode outside the table (JIS extras, media keys) cannot be
        // drawn as a keycap, so it cannot be taught.
        return nil
    }

    /// Whether this mask carries a modifier bit outside the four
    /// `AXMenuItemModifiers` documents — ⇧, ⌥, ⌃, NoCommand.
    ///
    /// Real menus report one. Measured against Finder and Chrome on macOS 27,
    /// both permissions granted:
    ///
    /// | menu command | printed | mask |
    /// |---|---|---|
    /// | 显示 › 进入全屏幕 | 🌐F | 24 |
    /// | 显示 › 进入全屏幕 | 🌐F | 20 |
    /// | 编辑 › 表情与符号 | 🌐E | 24 |
    /// | 窗口 › 居中 | 🌐⌃C | 28 |
    /// | 窗口 › 填充 | 🌐F | 28 |
    ///
    /// Bit 4 (16) is the globe (fn) key. It is not in the public SDK —
    /// `AXAttributeConstants.h` stops at NoCommand, and Carbon's
    /// `kMenu*Modifier` enum stops there too — so nothing in this file names
    /// it. What matters is what is left when it is read as absence, because
    /// the mask that remains is indistinguishable from one that means
    /// something else:
    ///
    /// - 28 is bit 4 | ⌃ | NoCommand. Drop bit 4 and what is left is ⌃C — a
    ///   real shortcut, and the one a terminal already uses for SIGINT.
    /// - 20 is bit 4 | ⌃. Drop bit 4 and ⌘ stays implicit, so what is left is
    ///   ⌃⌘F — also a real shortcut.
    /// - 16 alone drops to zero, which is ⌘ alone.
    ///
    /// 24 (bit 4 | NoCommand) is the one that survives being misread, and only
    /// by accident: it drops to NoCommand, a bare F with no ⌘, which
    /// `isRecordableGesture` refuses anyway. A mask that is wrong only where
    /// another check happens to catch it is not a mask that is being read.
    ///
    /// So the bit can be neither decoded nor dropped. A shortcut carrying it
    /// is one the keyboard half would never record, because the tap never
    /// reads `.maskSecondaryFn`, so adoption detection could never confirm
    /// it. The whole reading is refused instead.
    static func carriesAnUnverifiableModifier(mask: Int) -> Bool {
        let documented = AXMenuItemModifiers(rawValue: 0b1111)
        return !AXMenuItemModifiers(rawValue: UInt32(truncatingIfNeeded: mask))
            .isSubset(of: documented)
    }

    /// Whether this gesture is one the keyboard half would ever record — the
    /// same test it applies to every keystroke, applied here to every shortcut
    /// read out of a menu. A card can only teach a gesture the user's hand can
    /// produce *and* that LessMouse would count; anything else is a card that
    /// never flips to adopted, or one that flips for the wrong reason.
    private static func teachable(_ key: SafeKey, modifiers: ModifierSet) -> MenuShortcut? {
        let shortcut = MenuShortcut(modifiers: modifiers, key: key)
        return shortcut.isRecordableGesture ? shortcut : nil
    }

    /// `AXMenuItemCmdModifiers` is a bitmask in which ⌘ is *implicit*: zero
    /// means "⌘ alone", and `kAXMenuItemModifierNoCommand` is the only way to
    /// say "no ⌘ at all". Reading it the other way round would teach "⌘⌘S".
    ///
    /// Reads only the four bits the SDK documents. A mask carrying more is
    /// refused by the caller before this is reached — see
    /// `carriesAnUnverifiableModifier` for why dropping the extra bits here
    /// instead would teach the wrong shortcut rather than nothing.
    static func modifiers(mask: Int) -> ModifierSet {
        let flags = AXMenuItemModifiers(rawValue: UInt32(mask))
        var modifiers: ModifierSet = flags.contains(.noCommand) ? [] : [.command]
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    // MARK: - CoreFoundation → Swift

    /// The elements in an `AXChildren` array. Bridged element by element
    /// rather than as a whole, so one odd entry cannot drop the menu.
    private func elements(_ value: CFTypeRef?) -> [AXUIElement]? {
        guard let value, CFGetTypeID(value) == CFArrayGetTypeID(),
              let array = value as? [AnyObject] else { return nil }
        return array.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    private static func isError(_ value: AnyObject) -> Bool {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        return AXValueGetType(value as! AXValue) == .axError
    }

    private static func point(_ value: AnyObject) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    private static func size(_ value: AnyObject) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgSize else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }

    private static func integer(_ value: AnyObject) -> Int? {
        // CFNumber bridges to Int at every width macOS uses here.
        (value as? NSNumber)?.intValue ?? (value as? Int)
    }
}
