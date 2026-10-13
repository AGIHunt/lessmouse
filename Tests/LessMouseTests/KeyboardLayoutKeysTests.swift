import Foundation
import Testing
@testable import LessMouseCore

/// The character half of a menu shortcut's key.
///
/// These are the tests that would have caught the bug that made almost every
/// menu command uncoachable: the keycode attribute a menu's shortcut is read
/// from answers for special keys only, so the printable majority has to come
/// from the character the menu prints — and a character is not a key.
///
/// The assertions are deliberately about *invariants* rather than absolute
/// keycodes, because the answers depend on the keyboard layout the machine
/// running the tests happens to use. On QWERTY "s" is keycode 1; on Dvorak it
/// is 41. Both are right, and a test pinned to either would fail on the other
/// machine while proving nothing about either.
@Suite(.serialized)
struct KeyboardLayoutKeysTests {
    /// Every character a menu can print beside ⌘ that has a key on a Latin
    /// keyboard. This is the set that was silently dropping out before.
    private static let printable: [Character] =
        Array("abcdefghijklmnopqrstuvwxyz") + Array("0123456789")
        + Array("/[]-.,;'\\`=")

    /// The characters a menu stores for a shortcut the user presses with ⇧
    /// held — ⌘*, ⌘?, ⌘}. The shift is carried by the character: a menu prints
    /// ⌘* and declares ⌘, because there is no way to press "*" without ⇧.
    private static let shiftedPunctuation: [Character] =
        Array("!@#$%^&*()_+{}|:\"<>~?")

    /// The private-use characters AppKit uses for function and special keys.
    /// A menu prints ⌘↑ as U+F700 and F3 as U+F706.
    private static let functionKeys: [Character] = [
        "\u{F700}", "\u{F701}", "\u{F702}", "\u{F703}",
        "\u{F704}", "\u{F705}", "\u{F706}", "\u{F707}",
        "\u{F728}",
    ]

    /// The signature the event tap writes for a key pressed with `modifiers`.
    private func viaKeyboard(keyCode: UInt16, modifiers: ModifierSet) -> String? {
        guard let key = KeyWhitelist.table[keyCode] else { return nil }
        return KeySignature(modifiers: modifiers, key: key).storageKey
    }

    @Test func everyPrintableCharacterNamesAKeyTheKeyboardHalfKnows() {
        for character in Self.printable {
            guard let answer = KeyboardLayoutKeys.key(forCharacter: String(character)) else {
                Issue.record("no key produces \(character) in this layout")
                continue
            }
            #expect(KeyWhitelist.table[answer.code] != nil,
                    "\(character) maps to keycode \(answer.code), which has no keycap — it could never be drawn on a card")
        }
    }

    /// The whole point of translating through the layout: the key the menu
    /// names and the key the event tap reports are the same key, so a taught
    /// shortcut and a pressed shortcut are the same string.
    @Test func theNamedKeyIsOneTheKeyboardHalfWouldReport() {
        for character in Self.printable {
            guard let answer = KeyboardLayoutKeys.key(forCharacter: String(character)),
                  let key = KeyWhitelist.table[answer.code] else { continue }
            // The tap's signature for that keycode, and the menu's signature
            // for that character, are built from the same SafeKey.
            let viaTap = viaKeyboard(keyCode: answer.code, modifiers: [.command])
            let viaMenu = MenuShortcut(modifiers: [.command], key: key).signature
            #expect(viaTap == viaMenu)
        }
    }

    /// Menus report letters uppercased — "S" beside ⌘S — so the lookup folds,
    /// and a menu that stored the lowercase form finds the same key.
    @Test func menusReportLettersUppercasedAndTheLookupFoldsThem() {
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            let upper = KeyboardLayoutKeys.key(forCharacter: String(letter).uppercased())
            let lower = KeyboardLayoutKeys.key(forCharacter: String(letter))
            #expect(upper?.code == lower?.code, "\(letter) and its uppercase must name the same key")
            #expect(upper?.needsShift == lower?.needsShift,
                    "\(letter) and its uppercase must agree on whether ⇧ is needed")
        }
    }

    /// A menu stores the shifted form of a punctuation key — ">" rather than
    /// "." with ⇧. Finding its key is what makes ⇧⌘. coachable.
    @Test func aShiftedPunctuationCharacterStillFindsItsKey() {
        for shifted in Self.shiftedPunctuation {
            guard let answer = KeyboardLayoutKeys.key(forCharacter: String(shifted)) else {
                // Some layouts have no key for this one at all, which is
                // honest: such a shortcut cannot be taught as a keycap.
                continue
            }
            #expect(KeyWhitelist.table[answer.code] != nil,
                    "\(shifted) maps to keycode \(answer.code), which has no keycap")
        }
    }

    /// The shift a shifted character carries has to reach the signature. A menu
    /// that prints ⌘* declares ⌘ and stores "*", so without this the menu half
    /// would name ⌘8 where the keyboard half names ⇧⌘8 — two strings for one
    /// shortcut, and adoption detection would never fire for any of them.
    @Test func aShiftedCharacterClaimsTheShiftItCannotBePressedWithout() {
        for shifted in Self.shiftedPunctuation {
            guard let answer = KeyboardLayoutKeys.key(forCharacter: String(shifted)),
                  let key = KeyWhitelist.table[answer.code] else { continue }

            // What the menu half builds, exactly as `AXMenuAccessibility` does:
            // the modifiers the menu declared (⌘ alone), plus the shift the
            // character turns out to need.
            var modifiers: ModifierSet = [.command]
            if answer.needsShift { modifiers.insert(.shift) }
            let viaMenu = MenuShortcut(modifiers: modifiers, key: key).signature

            // What the keyboard half writes when the user actually presses it.
            let viaTap = viaKeyboard(keyCode: answer.code, modifiers: modifiers)

            #expect(viaMenu == viaTap,
                    "\(shifted): the menu half names \(viaMenu) and the keyboard half \(viaTap ?? "nil")")
            // And the shift must actually be there, not merely consistent.
            if answer.needsShift {
                #expect(modifiers.contains(.shift),
                        "\(shifted) lives on keycode \(answer.code) only under ⇧, so the signature must say so")
            }
        }
    }

    /// An unshifted character must not pick up a shift it does not need. ⌘S is
    /// pressed without ⇧, so a menu printing it must name `cmd+s` and not
    /// `cmd+shift+s` — the failure mode of trusting the character's case.
    @Test func anUnshiftedCharacterDoesNotInheritAShift() {
        for character in Self.printable {
            guard let answer = KeyboardLayoutKeys.key(forCharacter: String(character)),
                  let key = KeyWhitelist.table[answer.code] else { continue }
            // Every character here is pressable without ⇧ on a Latin keyboard,
            // so none of them may claim one.
            #expect(answer.needsShift == false,
                    "\(character) is pressable without ⇧, so it must not claim one")
            let viaMenu = MenuShortcut(modifiers: [.command], key: key).signature
            #expect(viaMenu == viaKeyboard(keyCode: answer.code, modifiers: [.command]))
        }
    }

    /// Function and special keys are named by the virtual-key attribute, so the
    /// layout map must never claim them. F3's character landing on the right
    /// arrow's keycode is the failure this rules out.
    @Test func functionKeyCharactersAreNeverClaimedByTheLayout() {
        for character in Self.functionKeys {
            #expect(KeyboardLayoutKeys.key(forCharacter: String(character)) == nil,
                    "\(String(describing: character)) is a function key and must not resolve through the layout")
        }
    }

    /// A character no key produces — a glyph reachable only through a dead
    /// key — has no keycap and so cannot be taught. Nil, not a wrong answer.
    @Test func aCharacterNoKeyProducesHasNoAnswer() {
        #expect(KeyboardLayoutKeys.key(forCharacter: "") == nil)
        #expect(KeyboardLayoutKeys.key(forCharacter: "🎉") == nil)
        #expect(KeyboardLayoutKeys.key(forCharacter: "€") == nil)
    }

    /// A character reachable only through ⌥ or ⌃ has no keycap either: pressing
    /// it means a modifier the menu never declared, so no stroke could produce
    /// the signature we would build. "å" is ⌥A on a US layout, and there is no
    /// ⌘å to teach — the key that makes it needs ⌥ held.
    ///
    /// The layout a machine happens to use decides whether a given glyph is
    /// ⌥-only (it has its own key on a Swedish layout), so this asserts the
    /// invariant rather than one character's answer: whatever the map answers,
    /// the menu half and the keyboard half must agree on it.
    @Test func everyAnswerIsOneBothHalvesAgreeOn() {
        var characters: [Character] = []
        for code in UInt32(0x20)...UInt32(0x7E) {
            characters.append(Character(Unicode.Scalar(code)!))
        }
        // Latin-1 supplement and punctuation, where the ⌥-only glyphs live.
        for code in UInt32(0xA0)...UInt32(0xBF) {
            characters.append(Character(Unicode.Scalar(code)!))
        }

        for character in characters {
            guard let answer = KeyboardLayoutKeys.key(forCharacter: String(character)),
                  let key = KeyWhitelist.table[answer.code] else { continue }

            var modifiers: ModifierSet = [.command]
            if answer.needsShift { modifiers.insert(.shift) }
            let viaMenu = MenuShortcut(modifiers: modifiers, key: key).signature
            let viaTap = viaKeyboard(keyCode: answer.code, modifiers: modifiers)

            #expect(viaMenu == viaTap,
                    "\(character): the menu half names \(viaMenu) and the keyboard half \(viaTap ?? "nil")")
        }
    }

    /// The map is built once per layout and cached, because it is consulted on
    /// every menu click. Repeated lookups must agree, and must not get slower.
    @Test func theMapIsStableAcrossCalls() {
        let first = Self.printable.map { KeyboardLayoutKeys.key(forCharacter: String($0)) }
        let second = Self.printable.map { KeyboardLayoutKeys.key(forCharacter: String($0)) }
        #expect(first.map { $0?.code } == second.map { $0?.code })
        #expect(first.map { $0?.needsShift } == second.map { $0?.needsShift })
    }
}
