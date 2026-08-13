import Foundation
import CoreGraphics
import Carbon.HIToolbox
import Testing
@testable import LessMouseCore

/// The privacy regression suite.
///
/// LessMouse's one unbreakable promise is "never record what you type". That
/// promise lives entirely in KeySignatureFilter (plus the secure-input check
/// here), and these tests pin it down from three angles: individual cases,
/// synthesized real CGEvents through the full production path, and an
/// exhaustive sweep of every keycode × modifier combination the keyboard can
/// send. If someone later widens the filter, the sweep fails before review
/// closes.
@Suite(.serialized)
struct CGEventNormalizerTests {
    // MARK: - Filter unit cases

    private func event(_ keyCode: Int,
                       _ modifiers: ModifierSet = [],
                       autorepeat: Bool = false,
                       app: String? = "com.apple.Terminal") -> KeyEvent {
        KeyEvent(timestamp: 100, keyCode: UInt16(keyCode), modifiers: modifiers,
                 isAutorepeat: autorepeat, application: app)
    }

    @Test func bareLetterIsDropped() {
        #expect(KeySignatureFilter.signature(for: event(kVK_ANSI_E)) == nil)
    }

    @Test func shiftLetterIsDropped() {
        // ⇧E is someone typing an uppercase E — text, not a command.
        #expect(KeySignatureFilter.signature(for: event(kVK_ANSI_E, .shift)) == nil)
    }

    @Test func bareBackspaceIsCounted() {
        let signature = KeySignatureFilter.signature(for: event(kVK_Delete))
        #expect(signature?.storageKey == "backspace")
    }

    @Test func shiftArrowIsCounted() {
        // ⇧← is a selection gesture — pure navigation, no characters.
        let signature = KeySignatureFilter.signature(for: event(kVK_LeftArrow, .shift))
        #expect(signature?.storageKey == "shift+left")
    }

    @Test func commandComboIsCounted() {
        let signature = KeySignatureFilter.signature(for: event(kVK_ANSI_C, .command))
        #expect(signature?.storageKey == "cmd+c")
    }

    @Test func controlLetterIsCounted() {
        // ⌃A and friends are Emacs-style commands, not text — the education
        // card for them needs these counts.
        let signature = KeySignatureFilter.signature(for: event(kVK_ANSI_A, .control))
        #expect(signature?.storageKey == "ctrl+a")
    }

    @Test func optionDeleteIsCounted() {
        let signature = KeySignatureFilter.signature(for: event(kVK_Delete, .option))
        #expect(signature?.storageKey == "opt+backspace")
    }

    @Test func commandShiftComboIsCounted() {
        let signature = KeySignatureFilter.signature(for: event(kVK_ANSI_S, [.command, .shift]))
        #expect(signature?.storageKey == "cmd+shift+s")
    }

    @Test func autorepeatNeverBecomesASignature() {
        #expect(KeySignatureFilter.signature(for: event(kVK_Delete, autorepeat: true)) == nil)
        #expect(KeySignatureFilter.signature(for: event(kVK_ANSI_C, .command, autorepeat: true)) == nil)
    }

    @Test func modifierTokenOrderIsStable() {
        // Same stroke, same string, always: cmd < ctrl < opt < shift, then key.
        let signature = KeySignatureFilter.signature(
            for: event(kVK_RightArrow, [.command, .option, .shift, .control]))
        #expect(signature?.storageKey == "cmd+ctrl+opt+shift+right")
    }

    // MARK: - Full production path with synthesized CGEvents

    /// Builds a genuine CGEvent and runs it through the same conversion the
    /// event tap uses — flags parsing and autorepeat field included.
    private func synthesizedSignature(virtualKey: CGKeyCode,
                                      flags: CGEventFlags = [],
                                      autorepeat: Bool = false) -> String? {
        guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true) else {
            Issue.record("could not synthesize CGEvent for key \(virtualKey)")
            return nil
        }
        cgEvent.flags = flags
        if autorepeat {
            cgEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        guard let keyEvent = CGEventNormalizer.keyEvent(from: cgEvent, timestamp: 1, application: nil) else {
            return nil
        }
        return KeySignatureFilter.signature(for: keyEvent)?.storageKey
    }

    @Test func synthesizedBareLetterProducesNothing() {
        #expect(synthesizedSignature(virtualKey: CGKeyCode(kVK_ANSI_A)) == nil)
    }

    @Test func synthesizedCommandC() {
        #expect(synthesizedSignature(virtualKey: CGKeyCode(kVK_ANSI_C), flags: .maskCommand) == "cmd+c")
    }

    @Test func capsLockDoesNotForkTheSignature() {
        // Caps lock down, ⌘C pressed: still one signature, not "cmd+c" and
        // "caps+cmd+c".
        #expect(synthesizedSignature(virtualKey: CGKeyCode(kVK_ANSI_C),
                                     flags: [.maskCommand, .maskAlphaShift]) == "cmd+c")
    }

    @Test func fnRidingOnArrowKeysIsStripped() {
        // Arrows arrive with the fn/numeric-pad flags set; the keycode alone
        // must decide.
        #expect(synthesizedSignature(virtualKey: CGKeyCode(kVK_LeftArrow),
                                     flags: [.maskSecondaryFn, .maskNumericPad]) == "left")
    }

    @Test func synthesizedAutorepeatIsDropped() {
        #expect(synthesizedSignature(virtualKey: CGKeyCode(kVK_Delete), autorepeat: true) == nil)
    }

    // MARK: - The exhaustive sweep

    /// Every signature reachable without ⌘/⌥/⌃ must name a navigation key —
    /// this is the "no keystroke log" invariant, stated once over the whole
    /// input space instead of case by case.
    @Test func bareSignaturesAreNavigationOnly() {
        let navigationTokens: Set<String> = [
            "backspace", "delete", "left", "right", "up", "down",
            "home", "end", "pageup", "pagedown", "esc", "tab",
            "f1", "f2", "f3", "f4", "f5", "f6",
            "f7", "f8", "f9", "f10", "f11", "f12",
        ]

        let bareModifiers: [ModifierSet] = [[], .shift]
        for keyCode in 0...127 {
            for modifiers in bareModifiers {
                let signature = KeySignatureFilter.signature(
                    for: event(keyCode, modifiers))
                if let signature {
                    #expect(navigationTokens.contains(signature.key.token),
                            "bare \(signature.storageKey) is not a navigation key")
                }
            }
        }
    }

    /// And every *combination* signature must name its key through the table
    /// — tokens stay readable, so stats.json stays auditable.
    @Test func combinationSignaturesUseTableTokens() {
        let spotChecks: [(Int, ModifierSet, String)] = [
            (kVK_ANSI_Slash, .command, "cmd+slash"),
            (kVK_ANSI_1, .command, "cmd+1"),
            (kVK_ANSI_Grave, .command, "cmd+grave"),
            (kVK_ANSI_LeftBracket, .option, "opt+bracketLeft"),
        ]
        for (keyCode, modifiers, expected) in spotChecks {
            #expect(KeySignatureFilter.signature(for: event(keyCode, modifiers))?.storageKey == expected)
        }

        // Whatever the keycode, a combination signature always carries a
        // non-empty, whitespace-free token.
        let comboModifiers: [ModifierSet] = [.command, .option, .control,
                                             [.command, .shift], [.option, .shift]]
        for keyCode in 0...127 {
            for modifiers in comboModifiers {
                guard let signature = KeySignatureFilter.signature(
                    for: event(keyCode, modifiers)) else { continue }
                #expect(!signature.key.token.isEmpty)
                #expect(!signature.key.token.contains { $0.isWhitespace })
            }
        }
    }
}

/// Signature display/storage forms used by the ledger UI.
@Suite struct KeySignatureTests {
    private func key(_ token: String, navigation: Bool = false, symbol: String? = nil) -> SafeKey {
        // Tests build SafeKeys directly because the whitelist keeps its
        // initializer internal to the module — which is fine here, the
        // display forms are what is under test, not the table.
        SafeKey(token: token, isNavigation: navigation, displaySymbol: symbol)
    }

    @Test func displaySymbolsFollowMacConvention() {
        let signature = KeySignature(modifiers: [.command, .shift],
                                     key: key("right", navigation: true, symbol: "→"))
        // The system prints Shift-Command-N as "⇧⌘N" — shift before command.
        #expect(signature.displaySymbols == "⇧⌘→")
        #expect(signature.storageKey == "cmd+shift+right")
    }

    @Test func bareNavigationHasNoModifierPrefix() {
        let signature = KeySignature(modifiers: [], key: key("backspace", navigation: true, symbol: "⌫"))
        #expect(signature.storageKey == "backspace")
        #expect(signature.displaySymbols == "⌫")
    }
}
