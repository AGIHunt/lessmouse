import Foundation
import Testing
@testable import LessMouseCore

/// The line between what a menu may teach and what only the keyboard may count.
///
/// Both halves of LessMouse exist to name one gesture in one string, and the
/// privacy promise says a bare letter — alone or with ⇧ — is typing, never a
/// shortcut. The menu half reads other people's menus, where "no modifiers at
/// all" is an ordinary thing to find: a bare letter, a shifted character with
/// no command modifier, and — measured against Finder and Chrome — a modifier
/// bit the public SDK does not document at all. So the menu half has to apply
/// the *keyboard* half's test, and these are the tests that it does.
@Suite(.serialized)
struct MenuGestureTests {
    /// `AXMenuItemCmdModifiers`: ⌘ is implicit in zero, and the only way to say
    /// "no command" is the explicit bit. Exactly as a real menu reports it.
    private let command = 0
    private let shift = 1 << 0, option = 1 << 1, control = 1 << 2, noCommand = 1 << 3

    /// Carbon virtual keycodes, named the way the code reads them.
    private let vkA = 0x00, vkS = 0x01, vkC = 0x08, vkF = 0x03
    private let vkEsc = 0x35, vkLeft = 0x7B, vkF1 = 0x7A

    private func shortcut(keyCode: Int? = nil,
                          character: String? = nil,
                          modifierMask: Int?) -> MenuShortcut? {
        AXMenuAccessibility.shortcut(fromKeyCode: keyCode,
                                     character: character,
                                     modifierMask: modifierMask)
    }

    // MARK: - What a menu may not teach

    /// The two cases the user's retest found, exactly as they arrive: a mask
    /// that says "no ⌘", because that is all there is left after the globe key
    /// is dropped.
    @Test func aMenuKeyWithNoCommandModifierTeachesNothing() {
        // Finder › 显示 › 进入全屏幕, printed as 🌐F — which is not what the
        // mask says; see the globe test below.
        #expect(shortcut(character: "F", modifierMask: noCommand) == nil)
        // The same key arriving as a keycode instead of a character — the
        // function-key path, which never carries a character at all.
        #expect(shortcut(keyCode: vkF, modifierMask: noCommand) == nil)

        // A mask that is ⌃ and nothing else — a shortcut the keyboard half
        // records too, and one that has to stay coachable.
        #expect(shortcut(character: "C", modifierMask: noCommand | control)?.signature == "ctrl+c")
    }

    /// The globe (fn) key, as real system menu items report it.
    ///
    /// `AXMenuItemModifiers` documents four bits — ⇧, ⌥, ⌃, NoCommand — and
    /// bit 4 is not among them, yet Finder and Chrome report it. Measured on
    /// macOS 27 with both permissions granted:
    ///
    /// | menu command | printed | mask |
    /// |---|---|---|
    /// | 显示 › 进入全屏幕 | 🌐F | 24 |
    /// | 显示 › 进入全屏幕 | 🌐F | 20 |
    /// | 编辑 › 表情与符号 | 🌐E | 24 |
    /// | 窗口 › 居中 | 🌐⌃C | 28 |
    /// | 窗口 › 填充 | 🌐F | 28 |
    ///
    /// The danger is not the unknown bit, it is what is left when it is read
    /// as absence. 28 is bit 4 | ⌃ | NoCommand: drop bit 4 and what is left is
    /// ⌃C, a real shortcut the terminal already uses, so the card would be
    /// celebrated the next time ⌃C was pressed for its own reason. 20 is bit 4
    /// | ⌃, which drops to ⌃⌘F — also real. 24 (bit 4 | NoCommand) is the one
    /// that happens to survive being misread, because it drops to a bare F
    /// with no ⌘, which the command filter refuses anyway; a mask that is
    /// wrong only where another check happens to catch it is not a mask that
    /// is being read. And none of them could ever be confirmed by adoption
    /// detection, because the keyboard half's tap never reads
    /// `.maskSecondaryFn`.
    ///
    /// So a mask carrying an undocumented bit teaches nothing at all.
    @Test func aShortcutCarryingTheGlobeKeyTeachesNothing() {
        // The measured masks, over the characters those menus print.
        for (character, mask) in [("F", 24), ("E", 24), ("C", 28), ("F", 28), ("F", 20)] {
            #expect(shortcut(character: character, modifierMask: mask) == nil,
                    "\(character) under mask \(mask) carries the globe key, so it cannot be taught")
        }
        // The same key arriving as a keycode, which is how F-keys arrive.
        #expect(shortcut(keyCode: vkF, modifierMask: 24) == nil)
        #expect(shortcut(keyCode: vkF1, modifierMask: 24) == nil)
        // Bit 4 riding on a mask that is otherwise a real shortcut.
        #expect(shortcut(character: "S", modifierMask: control | 16) == nil)
        #expect(shortcut(keyCode: vkC, modifierMask: 16) == nil)
        // Every mask above the documented four, not only that one bit.
        for mask in 16..<256 {
            #expect(shortcut(character: "S", modifierMask: mask) == nil,
                    "mask \(mask) names a modifier LessMouse cannot draw")
            #expect(shortcut(keyCode: vkF, modifierMask: mask) == nil,
                    "mask \(mask) names a modifier LessMouse cannot draw")
        }
    }

    /// The other half of that: a mask the SDK *does* document is decoded, not
    /// refused — the filter has to be about unreadable modifiers, not about
    /// modifiers in general, or ⌃C and ⌥⇧O would go with it.
    @Test func aDocumentedModifierBitIsStillDecoded() {
        #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: 0) == false)
        #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: noCommand) == false)
        #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: shift | option | control | noCommand) == false)
        for mask in 16..<256 {
            #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: mask) == true,
                    "mask \(mask) is outside the four documented bits")
        }
    }

    /// A menu whose character is a bare letter: this is the one that wrote
    /// `a` and `shift+a` into stats.json, which the privacy promise says never
    /// happens.
    @Test func aMenuPrintingNothingButALetterWritesNothing() {
        #expect(shortcut(character: "A", modifierMask: noCommand) == nil)
        #expect(shortcut(character: "a", modifierMask: noCommand) == nil)
        // ⇧+letter is an uppercase letter being typed, exactly as it is on the
        // keyboard half.
        #expect(shortcut(character: "A", modifierMask: noCommand | shift) == nil)
        // A punctuation key with no command modifier is a keystroke too.
        #expect(shortcut(character: "/", modifierMask: noCommand) == nil)
        #expect(shortcut(character: "1", modifierMask: noCommand) == nil)
    }

    /// An item that reports no modifier mask at all: absence of the attribute
    /// is absence of a *value*, not absence of a shortcut, and zero is the
    /// value that names no modifier — ⌘ alone.
    @Test func anItemWithNoModifierMaskReadsAsCommandAlone() {
        #expect(shortcut(character: "F", modifierMask: nil)?.signature == "cmd+f")
        #expect(shortcut(keyCode: vkF, modifierMask: nil)?.signature == "cmd+f")
        #expect(shortcut(character: "S", modifierMask: nil)?.signature == "cmd+s")
        // The ordinary "Edit": no mask, and nothing to press either.
        #expect(shortcut(modifierMask: nil) == nil)
        #expect(shortcut(keyCode: nil, character: nil, modifierMask: nil) == nil)
    }

    // MARK: - What a menu may still teach

    /// The fix is a filter on the *modifiers*, not a retreat: everything that
    /// was already recognized keeps working, and ⌃/⌥-only shortcuts are among
    /// them because the keyboard half records those too.
    @Test func aMenuShortcutWithACommandModifierIsStillTaught() {
        #expect(shortcut(character: "S", modifierMask: command)?.signature == "cmd+s")
        #expect(shortcut(character: "S", modifierMask: command | shift)?.signature == "cmd+shift+s")
        #expect(shortcut(character: "C", modifierMask: noCommand | control)?.signature == "ctrl+c")
        #expect(shortcut(character: "A", modifierMask: noCommand | option)?.signature == "opt+a")
        #expect(shortcut(keyCode: vkF1, modifierMask: command)?.signature == "cmd+f1")
        #expect(shortcut(keyCode: vkLeft, modifierMask: noCommand | control)?.signature == "ctrl+left")
    }

    /// A navigation key carries no character, so the keyboard half records it
    /// bare — and a menu printing it bare stays coachable.
    @Test func aBareNavigationKeyAMenuPrintsIsStillCoachable() {
        #expect(shortcut(keyCode: vkEsc, modifierMask: noCommand)?.signature == "esc")
        #expect(shortcut(keyCode: vkLeft, modifierMask: noCommand)?.signature == "left")
        #expect(shortcut(keyCode: vkF1, modifierMask: noCommand | shift)?.signature == "shift+f1")
    }

    /// The characters that need ⇧ to press at all (⌘*, ⌘?, ⌘}) — the shift the
    /// character carries still lands, so the two halves meet on one string.
    @Test func aShiftedCharacterKeepsTheShiftItCannotBePressedWithout() {
        #expect(shortcut(character: "*", modifierMask: command)?.signature == "cmd+shift+8")
        #expect(shortcut(character: "?", modifierMask: command | shift)?.signature == "cmd+shift+slash")
        #expect(shortcut(character: "+", modifierMask: command)?.signature == "cmd+shift+equal")
    }

    // MARK: - The invariant

    /// The one that matters: whatever the menu half can teach, the keyboard
    /// half would also record — same key, same modifiers, same string. Swept
    /// over every key the whitelist knows and every character a layout can
    /// produce, under every mask a menu can print, so it holds for the cases
    /// nobody thought to write down rather than only for the ones we did.
    ///
    /// The mask sweep runs to 32 rather than 16 so bit 4 is inside it: a mask
    /// carrying it must teach nothing at all, and the sweep is what proves
    /// that for every key rather than for the five the user measured.
    @Test func everythingTheMenuHalfTeachesTheKeyboardHalfWouldRecord() {
        var taught = 0
        var refused = 0

        // The keycode path: every keycode in the table, under every mask.
        for (code, key) in KeyWhitelist.table {
            for mask in 0..<32 {
                guard let shortcut = shortcut(keyCode: Int(code), modifierMask: mask) else {
                    if mask >= 16 { refused += 1 }
                    continue
                }
                taught += 1
                #expect(shortcut.isRecordableGesture,
                        "\(key.token) under mask \(mask) cannot be recorded, so it cannot be taught")
                #expect(KeySignatureFilter.signature(for: KeyEvent(
                    timestamp: 0, keyCode: code, modifiers: shortcut.modifiers
                ))?.storageKey == shortcut.signature,
                        "\(key.token) under mask \(mask) taught \(shortcut.signature), which no keystroke writes")
            }
        }

        // The character path: every printable ASCII character, likewise.
        for scalar in 0x20...0x7E {
            let character = String(Unicode.Scalar(scalar)!)
            for mask in 0..<32 {
                guard let shortcut = shortcut(character: character, modifierMask: mask) else {
                    if mask >= 16 { refused += 1 }
                    continue
                }
                taught += 1
                #expect(shortcut.isRecordableGesture,
                        "\(character) under mask \(mask) cannot be recorded, so it cannot be taught")
                let code = KeyWhitelist.table.first { $0.value == shortcut.key }!.key
                #expect(KeySignatureFilter.signature(for: KeyEvent(
                    timestamp: 0, keyCode: code, modifiers: shortcut.modifiers
                ))?.storageKey == shortcut.signature,
                        "\(character) under mask \(mask) taught \(shortcut.signature), which no keystroke writes")
            }
        }

        #expect(taught > 100, "the sweep has to have covered real shortcuts, not nothing")
        #expect(refused > 100, "the sweep has to have covered the masks it refuses, not nothing")
    }

    /// The shortcuts the user's retest checked, end to end through the menu
    /// reading path rather than through `MenuShortcut(signature:)`: ⌘2, ⇧⌘B,
    /// ⇧⌘M, `? * +`, the arrows and the F-keys. Each arrives the way a real
    /// menu reports it, so a regression here is a regression a user would see.
    @Test func theShortcutsTheRetestCheckedSurviveTheMenuReadingPath() {
        let checked: [(String, Int, String)] = [
            // (character or keycode-as-string, mask, expected signature)
            ("2", command, "cmd+2"),
            ("B", command | shift, "cmd+shift+b"),
            ("M", command | shift, "cmd+shift+m"),
            ("?", command | shift, "cmd+shift+slash"),
            ("*", command, "cmd+shift+8"),
            ("+", command, "cmd+shift+equal"),
        ]
        for (character, mask, expected) in checked {
            #expect(shortcut(character: character, modifierMask: mask)?.signature == expected,
                    "\(character) under mask \(mask) must still teach \(expected)")
        }

        // Arrows and F-keys arrive as keycodes, never as characters.
        let keys: [(Int, Int, String)] = [
            (vkLeft, command, "cmd+left"),
            (vkLeft, command | shift, "cmd+shift+left"),
            (vkLeft, noCommand | control, "ctrl+left"),
            (vkF1, command, "cmd+f1"),
            (vkF1, command | shift, "cmd+shift+f1"),
        ]
        for (code, mask, expected) in keys {
            #expect(shortcut(keyCode: code, modifierMask: mask)?.signature == expected,
                    "keycode \(code) under mask \(mask) must still teach \(expected)")
        }
    }
}
