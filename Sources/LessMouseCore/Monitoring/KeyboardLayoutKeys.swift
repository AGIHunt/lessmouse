import Foundation
import Carbon.HIToolbox

/// The hardware key a menu's printed character lives on, in the keyboard
/// layout the user is actually typing in — and whether pressing it needs ⇧.
///
/// Why this exists: `AXMenuItemCmdVirtualKey` — the attribute that names a menu
/// shortcut's keycode outright — answers for function and special keys only.
/// Ask it for ⌘↑ and it says 126; ask it for ⌘S and it says `kAXErrorNoValue`.
/// So the printable majority of every menu's shortcuts arrive as
/// `AXMenuItemCmdChar` instead: the character, never the key.
///
/// A character is not a keycode, and treating one as the other would break the
/// one promise the two halves of the menu coach rest on. On Dvorak the key that
/// produces "s" is the one QWERTY labels ";", so a menu printing ⌘S is asking
/// for keycode 41 there, not 1 — and the keyboard half of the pipeline, which
/// records keycodes because `KeyWhitelist` is keyed by them, would write
/// `cmd+semicolon` when the user pressed it. Translating the character through
/// the layout in use is what makes the menu half name the *same* key, so a
/// taught shortcut and a pressed shortcut are the same string for everyone and
/// not only for QWERTY.
///
/// The shift bit is the same story one level down. A menu that prints ⌘*
/// declares ⌘ and stores "*": the shift lives in the character, because "*" is
/// not a key you can press without it. Answering "keycode 28" alone would name
/// ⌘8, while the user's hand actually wrote ⇧⌘8 and the keyboard half recorded
/// `cmd+shift+8` — two different strings for one shortcut, and adoption
/// detection would never fire. So the answer carries both facts.
///
/// The map is built once per layout and cached: 128 keycodes is a fraction of a
/// millisecond, and the layout changes only when the user changes it.
///
/// **Threading.** The Text Input Sources API (`TISCopyCurrentKeyboardLayoutInputSource`
/// and friends) is main-thread-only on current macOS: called from elsewhere it
/// can trip a libdispatch main-queue assertion and take the process down. The
/// menu coach reads menus on a background queue, so the map is built on the
/// main thread — at `prepare()`, and again whenever the selected input source
/// changes — and the background lookup only ever reads the stored result.
enum KeyboardLayoutKeys {
    /// What a menu's printed character resolves to: the key it lives on, and
    /// whether that key has to be pressed with ⇧ to produce it.
    struct Answer {
        let code: UInt16
        let needsShift: Bool
    }

    /// The key that produces `character` in the current layout, or nil when no
    /// key does — a glyph only reachable through a dead key, say, which cannot
    /// be taught as a keycap anyway.
    static func key(forCharacter character: String) -> Answer? {
        // Menus report letters uppercased ("S" beside ⌘S), so the map is folded
        // and the lookup folds too.
        guard let folded = character.lowercased().first else { return nil }
        return map()[folded]
    }

    // MARK: - The map

    private static let lock = NSLock()
    private static var cached: [Character: Answer]?
    nonisolated(unsafe) private static var observer: NSObjectProtocol?

    /// Build the map now and keep it current. Main thread; call once at launch.
    @MainActor
    static func prepare() {
        rebuild()
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { rebuild() }
        }
    }

    /// Re-read the current layout. Main thread only — this is the one place
    /// the TIS API is called.
    @MainActor
    static func rebuild() {
        // Can be nil mid-switch or at the login window; keep the old map then.
        guard let unmanaged = TISCopyCurrentKeyboardLayoutInputSource() else { return }
        let built = build(source: unmanaged.takeRetainedValue())
        lock.lock()
        cached = built
        lock.unlock()
    }

    /// The stored map, from any thread. Before `prepare()` has run (tests,
    /// tools) it is built on demand — on the main thread, hopping there if
    /// needed, never on the caller's.
    private static func map() -> [Character: Answer] {
        lock.lock()
        let current = cached
        lock.unlock()
        if let current { return current }
        if Thread.isMainThread {
            MainActor.assumeIsolated { rebuild() }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { rebuild() } }
        }
        lock.lock()
        defer { lock.unlock() }
        return cached ?? [:]
    }

    private static func build(source: TISInputSource) -> [Character: Answer] {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            // An input source with no Unicode layout data (some IMEs) has no
            // character-to-key answer to give. Empty means "not coachable",
            // which the caller already handles.
            return [:]
        }
        let data = unsafeBitCast(raw, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return [:] }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = LMGetKbdType()

        let shift = shiftLikeStates(layout: layout, keyboardType: keyboardType)

        // Several keys can produce the same character, and which one a menu
        // means is the one the user would press. Ranked rather than ordered,
        // because the two preferences pull in opposite directions: "0" must
        // come from the key that prints it unmodified rather than from a key
        // that prints § and happens to produce "0" under some other modifier,
        // while "*" must come from ⇧8 on the main keyboard rather than from the
        // keypad's *, which the whitelist leaves out and so could never be
        // drawn on a card.
        var map: [Character: Answer] = [:]
        var ranks: [Character: Preference] = [:]

        for code: UInt16 in 0..<128 {
            for state in modifierStates {
                // The raw form, not the folded one: ⇧ shows up as "a" → "A",
                // and folding here would erase the very difference ⇧
                // detection looks for.
                guard let produced = rawCharacter(layout, code: code,
                                                  modifiers: state,
                                                  keyboardType: keyboardType) else { continue }
                // A function or special key arrives from a menu as a
                // private-use character (⌘↑ is U+F700, F3 is U+F706), and those
                // keys are named outright by the virtual-key attribute. Letting
                // the layout claim one would send an F-key down this path and
                // land on whatever key happens to produce that character — F3
                // came out as the right arrow that way.
                guard !produced.unicodeScalars.contains(where: { isPrivateUse($0) }) else { continue }
                // A character reachable only through ⌥ or ⌃ has no keycap:
                // pressing it means holding a modifier the menu never declared,
                // so no stroke could ever produce the signature we would build.
                // Leaving it out is honest — the caller already reads "no key"
                // as "not coachable" — and the alternative is a signature that
                // is wrong rather than absent.
                guard state == 0 || shift.contains(state) else { continue }

                // Folded, because menus report letters uppercased ("S" beside
                // ⌘S) and the lookup folds to match.
                guard let folded = produced.lowercased().first else { continue }

                let answer = Answer(code: code, needsShift: state != 0)
                let preference = Preference(code: code, state: state)
                if let held = ranks[folded], held <= preference { continue }
                map[folded] = answer
                ranks[folded] = preference
            }
        }
        return map
    }

    /// How much a key is the right answer for a character, smallest first.
    private struct Preference: Comparable {
        /// The main keyboard before the keypad.
        var keypad: Int
        /// Unmodified before shifted, so a key's own character claims it.
        var shifted: Int
        /// The lower keycode, for a character two keys produce identically.
        var code: UInt16

        init(code: UInt16, state: UInt32) {
            self.keypad = KeyboardLayoutKeys.isKeypad(code) ? 1 : 0
            self.shifted = state == 0 ? 0 : 1
            self.code = code
        }

        static func < (lhs: Preference, rhs: Preference) -> Bool {
            (lhs.keypad, lhs.shifted, lhs.code) < (rhs.keypad, rhs.shifted, rhs.code)
        }
    }

    /// Every modifier state tried: none, then each single bit.
    ///
    /// Which bit a layout uses for ⇧ is the layout's business — and it is *not*
    /// the value Carbon's `shiftKey` constant holds, so naming a bit here would
    /// be a guess that silently stops working. Trying every single-bit state
    /// instead needs no such guess, and it is what lets a menu that stored ">"
    /// rather than "." with ⇧ still find its key.
    private static let modifierStates: [UInt32] = {
        var states: [UInt32] = [0]
        for bit in 0..<8 { states.append(UInt32(1) << bit) }
        return states
    }()

    /// The single-bit states that behave as ⇧ on this layout.
    ///
    /// Identified rather than assumed, because which bit ⇧ is belongs to the
    /// layout and is not the value Carbon's `shiftKey` holds — measured, the
    /// layout answers 2 where Carbon's constant is 512. Two conditions, since
    /// either alone is fooled: ⇧ uppercases a letter, but so does caps lock;
    /// ⇧ moves a digit or punctuation key, but so does ⌥. Only ⇧ does both.
    private static func shiftLikeStates(layout: UnsafePointer<UCKeyboardLayout>,
                                        keyboardType: UInt8) -> Set<UInt32> {
        var found: Set<UInt32> = []
        for state in modifierStates where state != 0 {
            var uppercasesALetter = false
            var movesAKeyThatIsNotALetter = false

            for code: UInt16 in 0..<128 {
                // The raw strings, unfolded: ⇧ is exactly the difference that
                // folding would erase.
                guard let plain = rawCharacter(layout, code: code, modifiers: 0,
                                               keyboardType: keyboardType),
                      let other = rawCharacter(layout, code: code, modifiers: state,
                                               keyboardType: keyboardType),
                      let a = plain.first?.asciiValue, let b = other.first?.asciiValue,
                      a != b
                else { continue }

                let isLetter = (65...90).contains(a) || (97...122).contains(a)
                if isLetter {
                    // "a" → "A" is ⇧. "a" → "å" is ⌥, and å has no ASCII value
                    // so it never reaches this comparison at all.
                    if (97...122).contains(a), a &- 32 == b { uppercasesALetter = true }
                } else {
                    // "8" → "*" is ⇧. Caps lock leaves digits alone, which is
                    // what tells the two apart.
                    movesAKeyThatIsNotALetter = true
                }
            }

            if uppercasesALetter && movesAKeyThatIsNotALetter { found.insert(state) }
        }
        return found
    }

    /// The keypad's block of keycodes, 65 (`.`) through 81 (`=`.
    private static func isKeypad(_ code: UInt16) -> Bool {
        (65...81).contains(code)
    }

    /// The Unicode private-use areas, where AppKit puts the characters that
    /// stand for function and special keys.
    private static func isPrivateUse(_ scalar: Unicode.Scalar) -> Bool {
        (0xE000...0xF8FF).contains(scalar.value) || (0xF0000...0xFFFFD).contains(scalar.value)
    }

    /// What the layout prints for a key under a modifier state, exactly as it
    /// prints it — case and all. Callers that fold do so themselves, because
    /// the case is sometimes the answer.
    private static func rawCharacter(_ layout: UnsafePointer<UCKeyboardLayout>,
                                     code: UInt16,
                                     modifiers: UInt32,
                                     keyboardType: UInt8) -> String? {
        var characters = [UniChar](repeating: 0, count: 4)
        var produced = 0
        var deadKeyState: UInt32 = 0
        let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay),
                                    modifiers, UInt32(keyboardType),
                                    UInt32(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeyState, 4, &produced, &characters)
        guard status == noErr, produced > 0 else { return nil }
        return String(utf16CodeUnits: &characters, count: produced)
    }
}
