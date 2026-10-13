import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Darwin
@testable import LessMouseCore

// Checks the menu coach end to end against real accessibility data.
//
//   swift build
//   swiftc -o verify-menu-coach \
//     -I .build/debug -L .build/debug -lLessMouseCore \
//     Tools/VerifyMenuCoach.swift
//   DYLD_LIBRARY_PATH=.build/debug ./verify-menu-coach
//
// Five sections, three of which need no Accessibility grant at all:
//
//   1. Our own NSMenu with real key equivalents, read through the real
//      AXMenuAccessibility. A process can always read its own UI elements, so
//      this runs anywhere. It is what proves the printable majority of every
//      menu's shortcuts resolves — the bug that made Finder come out
//      12-for-174.
//
//   2. The raw modifier masks, including the globe (fn) bit. A self-made
//      NSMenu *cannot* exhibit it: AppKit refuses `.function` for a
//      non-system item. So the masks real system menus report are fed through
//      the reading path directly, as the numbers they arrive as.
//
//   3. The whole pipeline in a data directory of the tool's own: simulated
//      mouse pick → stats.json on disk → card → simulated keypress → adopted.
//      The real AppState, the real StatsStore, the real MenuClickTracker; only
//      the menu itself is a fake, because a menu bar cannot be built in a CLI
//      process. Never touches the real ~/Library data.
//
//   4. The frontmost app's real menu bar, every menu, every submenu: which
//      items carry a modifier bit the SDK does not document, what each would
//      have been decoded as, and the two-halves invariant across the lot.
//      **Needs Accessibility.** Leave a real app in front when you run this.
//
//   5. A hung app does not stall the read. **Needs Accessibility**, because
//      without the grant the API refuses immediately and there is nothing to
//      time.
//
// Sections 1–3 are the ones that run everywhere; 4 and 5 are the halves a
// machine without the grant cannot check, and the tool says so rather than
// reporting a pass it did not earn.
//
// What this tool cannot cover:
//
//   - Real mouse presses and real keypresses. The tracker is fed synthetic
//     `MenuClick`s and the state machine synthetic `KeyEvent`s. A CGEvent tap
//     cannot be created from a CLI process, so the tap itself is untested
//     here; `swift test` covers the event mask it asks for.
//   - The globe bit as *AppKit stores it*. Section 2 feeds the masks real
//     menus report; the only way to see one natively is a system-provided
//     menu item, which is why section 4 exists.
//   - Timing on a machine without Accessibility: section 5 is skipped there.
//   - Menus the accessibility API does not expose (a game in full screen, a
//     kiosk). Those read as "no menu bar", which is what the coach does with
//     them too.

// MARK: - Reporting

var pass = 0, fail = 0, skipped = 0
func report(_ ok: Bool, _ line: String) {
    if ok { pass += 1 } else { fail += 1 }
    print("  \(ok ? "ok  " : "FAIL") \(line)")
}
func skip(_ line: String) {
    skipped += 1
    print("  --  \(line)")
}
func section(_ title: String) {
    print("\n=== \(title) ===")
}
func total() {
    print("\nTOTAL: \(pass) passed, \(fail) failed, \(skipped) skipped")
    print(fail == 0 ? "ALL GOOD" : "FAILURES PRESENT")
}

// MARK: - The cases

struct Case {
    let title: String
    let key: String                  // NSMenuItem key equivalent
    let mods: NSEvent.ModifierFlags
    let enabled: Bool
    let want: String?                // expected storageKey; nil = no shortcut
    let note: String
}

// Function-key constants are the ones AppKit actually uses. U+F706 is F3;
// U+F703 is the RIGHT ARROW. Getting that wrong makes a correct library look
// broken — that is exactly how F3 first appeared to resolve as cmd+right.
let cases: [Case] = [
    // The printable majority that was entirely missing.
    Case(title: "Save",           key: "s",        mods: .command,            enabled: true, want: "cmd+s",            note: "the README's own example"),
    Case(title: "Close",          key: "w",        mods: .command,            enabled: true, want: "cmd+w",            note: ""),
    Case(title: "View Two",       key: "2",        mods: .command,            enabled: true, want: "cmd+2",            note: "digit"),
    Case(title: "Bookmarks",      key: "B",        mods: [.command, .shift],  enabled: true, want: "cmd+shift+b",     note: "shift"),
    Case(title: "Minimise",       key: "M",        mods: [.command, .shift],  enabled: true, want: "cmd+shift+m",     note: "shift"),
    Case(title: "Slash",          key: "/",        mods: .command,            enabled: true, want: "cmd+slash",        note: "punctuation"),
    Case(title: "Bracket",        key: "[",        mods: .command,            enabled: true, want: "cmd+bracketLeft",  note: "punctuation"),
    Case(title: "Minus",          key: "-",        mods: [.command, .shift],  enabled: true, want: "cmd+shift+minus",  note: "shifted punctuation"),
    Case(title: "Period",         key: ".",        mods: [.command, .shift],  enabled: true, want: "cmd+shift+period", note: "shifted punctuation"),
    Case(title: "Quote",          key: "'",        mods: .command,            enabled: true, want: "cmd+quote",        note: "punctuation"),
    Case(title: "Semicolon",      key: ";",        mods: .command,            enabled: true, want: "cmd+semicolon",    note: ""),
    Case(title: "Zero",           key: "0",        mods: .command,            enabled: true, want: "cmd+0",            note: "digit"),
    Case(title: "Backslash",      key: "\\",       mods: .command,            enabled: true, want: "cmd+backslash",    note: "punctuation"),
    Case(title: "Grave",          key: "`",        mods: .command,            enabled: true, want: "cmd+grave",        note: "punctuation"),
    Case(title: "Asterisk",       key: "*",        mods: .command,            enabled: true, want: "cmd+shift+8",      note: "shifted, main keyboard not keypad"),
    Case(title: "Plus",           key: "+",        mods: .command,            enabled: true, want: "cmd+shift+equal",  note: "shifted, main keyboard not keypad"),
    Case(title: "Question",       key: "?",        mods: [.command, .shift],  enabled: true, want: "cmd+shift+slash",  note: "shifted, main keyboard not keypad"),

    // The special keys that always worked.
    Case(title: "Enclosing",      key: "\u{F700}", mods: .command,            enabled: true, want: "cmd+up",          note: "Finder enclosing folder"),
    Case(title: "Left",           key: "\u{F702}", mods: .command,            enabled: true, want: "cmd+left",        note: "arrow"),
    Case(title: "Right",          key: "\u{F703}", mods: [.command, .shift],  enabled: true, want: "cmd+shift+right", note: "shifted arrow"),
    Case(title: "Down",           key: "\u{F701}", mods: [.control],          enabled: true, want: "ctrl+down",       note: "no command key at all"),
    Case(title: "Backspace",      key: "\u{0008}", mods: .command,            enabled: true, want: "cmd+backspace",   note: ""),
    Case(title: "Escape",         key: "\u{001B}", mods: [.command, .option], enabled: true, want: "cmd+opt+esc",     note: "prints ⌥⌘⎋"),
    Case(title: "Tab",            key: "\u{0009}", mods: .command,            enabled: true, want: "cmd+tab",         note: ""),
    Case(title: "F1",             key: "\u{F704}", mods: .command,            enabled: true, want: "cmd+f1",          note: "F-key"),
    Case(title: "F3 real",        key: "\u{F706}", mods: .command,            enabled: true, want: "cmd+f3",          note: "F3, not the right arrow"),
    Case(title: "F5 real",        key: "\u{F708}", mods: [.command, .shift],  enabled: true, want: "cmd+shift+f5",    note: "shifted F-key"),
    Case(title: "F12",            key: "\u{F70F}", mods: .command,            enabled: true, want: "cmd+f12",         note: "F-key"),
    Case(title: "Forward Delete", key: "\u{F728}", mods: .command,            enabled: true, want: "cmd+delete",      note: ""),

    // Modifier shapes.
    Case(title: "Option A",       key: "a",        mods: .option,             enabled: true, want: "opt+a",           note: "no command key at all"),
    Case(title: "Control Q",      key: "q",        mods: .control,            enabled: true, want: "ctrl+q",          note: "no command key at all"),
    Case(title: "Ctrl Shift P",   key: "p",        mods: [.control, .shift],  enabled: true, want: "ctrl+shift+p",    note: ""),

    // The fn (🌐) family as AppKit stores it. AppKit drops `.function` when the
    // key equivalent is set, so what accessibility reports here is the same
    // shortcut with the globe gone — which is exactly why section 2 exists:
    // the masks *real* system menus report are not these.
    Case(title: "Globe F",        key: "f",        mods: [.function],           enabled: true, want: nil,           note: "Finder Enter Full Screen prints 🌐F"),
    Case(title: "Globe Shift F",  key: "f",        mods: [.function, .shift],   enabled: true, want: nil,           note: "🌐⇧F"),
    Case(title: "Globe Ctrl C",   key: "c",        mods: [.function, .control], enabled: true, want: "ctrl+c",       note: "🌐⌃C as AppKit stores it — the ⌃ survives, the globe is gone"),

    // No ⌘/⌥/⌃ at all: this is typing, and the keyboard half never counts it.
    // A menu reading like this used to write `a` and `shift+a` into stats.json
    // and generate cards for them.
    Case(title: "Bare A",         key: "a",        mods: [],                  enabled: true, want: nil,               note: "no modifiers"),
    Case(title: "Bare F",         key: "f",        mods: [],                  enabled: true, want: nil,               note: "no modifiers"),
    Case(title: "Shift A",        key: "a",        mods: [.shift],            enabled: true, want: nil,               note: "⇧+letter is an uppercase letter"),
    Case(title: "Bare Slash",     key: "/",        mods: [],                  enabled: true, want: nil,               note: "punctuation with no command is a keystroke"),
    Case(title: "Bare One",       key: "1",        mods: [],                  enabled: true, want: nil,               note: "a digit with no command is a keystroke"),

    // Not coachable, and must not be invented.
    Case(title: "No Equivalent",  key: "",         mods: [],                  enabled: true, want: nil,               note: "a menu bar item like Edit"),
    Case(title: "Space",          key: "\u{0020}", mods: .command,            enabled: true, want: nil,               note: "space is not in the whitelist"),
    Case(title: "Return",         key: "\u{000D}", mods: .command,            enabled: true, want: nil,               note: "return is not in the whitelist"),

    // Disabled: prints a shortcut, but used nothing.
    Case(title: "Greyed Save",    key: "s",        mods: .command,            enabled: false, want: "cmd+s",          note: "readable, but the tracker must ignore it"),
]

final class Target: NSObject { @objc func noop() {} }

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let target = Target()
let mainMenu = NSMenu()
let probe = NSMenuItem()
probe.title = "ProbeMenu"
let sub = NSMenu(title: "ProbeMenu")
// AppKit validates items against their target when this is on, and re-enables
// anything whose target responds — silently undoing the disabled case below.
sub.autoenablesItems = false
for c in cases {
    let item = NSMenuItem(title: c.title, action: #selector(Target.noop), keyEquivalent: c.key)
    item.target = target
    item.keyEquivalentModifierMask = c.mods
    item.isEnabled = c.enabled
    sub.addItem(item)
}
probe.submenu = sub
mainMenu.addItem(probe)
app.mainMenu = mainMenu
app.finishLaunching()
// Deliberately NOT activated. Section 4 reads the *frontmost* app's menus, and
// a tool that steals focus would only ever measure itself. Our own menu bar
// is still readable — a process can always read its own UI elements.

// The same strokes as the event tap records: keycode -> whitelist -> signature.
func viaKeyboard(keyCode: UInt16, modifiers: ModifierSet) -> String? {
    guard let key = KeyWhitelist.table[keyCode] else { return nil }
    return KeySignature(modifiers: modifiers, key: key).storageKey
}

// Keycodes for the special and function keys, which are named outright by the
// virtual-key attribute rather than translated from a character.
let specialKeyCodes: [String: UInt16] = [
    "Enclosing": 126, "F1": 122, "F3 real": 99, "F5 real": 96, "F12": 111,
    "Left": 123, "Right": 124, "Down": 125, "Forward Delete": 117,
]

/// The physical gesture that runs a command whose key equivalent is `key`,
/// found by asking the keyboard layout directly — which key prints that
/// character, and whether it prints it only under ⇧.
///
/// Deliberately *not* routed through `KeyboardLayoutKeys`: that is the code
/// under test. Reading the layout here by hand is what makes the comparison
/// below an oracle rather than a tautology, and it is the only way to catch the
/// library naming ⌘8 where a hand writes ⇧⌘8.
func physicalGesture(for key: String) -> (code: UInt16, needsShift: Bool)? {
    let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let data = unsafeBitCast(raw, to: CFData.self)
    guard let bytes = CFDataGetBytePtr(data) else { return nil }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    let type = LMGetKbdType()

    func prints(_ code: UInt16, _ state: UInt32) -> String {
        var chars = [UniChar](repeating: 0, count: 4)
        var n = 0
        var dead: UInt32 = 0
        guard UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), state, UInt32(type),
                             UInt32(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &n, &chars) == noErr,
              n > 0 else { return "" }
        return String(utf16CodeUnits: &chars, count: n)
    }

    // The keypad is skipped: its keys are not in the whitelist, so a command
    // that lives there could never be drawn on a card anyway.
    let mainKeys = (0..<128).filter { !(65...81).contains(UInt16($0)) }
    let wanted = key.lowercased()

    for code in mainKeys where prints(UInt16(code), 0).lowercased() == wanted {
        return (UInt16(code), false)
    }
    for code in mainKeys {
        for bit in 1..<8 where prints(UInt16(code), UInt32(1) << bit).lowercased() == wanted {
            return (UInt16(code), true)
        }
    }
    return nil
}

// MARK: - The invariant both halves share

/// Every shortcut the menu half resolved must be a gesture the keyboard half
/// would also *record* — same key, same modifiers, same string. A card that
/// fails this can never be adopted by pressing anything, and a bare letter
/// that passes it would put typing into stats.json, which is the one thing the
/// privacy promise rules out. Run against real accessibility data rather than
/// a hand-built element, which is what makes it worth running.
func verifyTwoHalvesAgree(_ commands: [MenuItemSnapshot], _ label: String) {
    var coachable = 0
    for command in commands {
        guard let shortcut = command.shortcut else { continue }
        coachable += 1
        guard let code = KeyWhitelist.table.first(where: { $0.value == shortcut.key })?.key else {
            report(false, "\(label): \(shortcut.signature) names a key no keycode produces")
            continue
        }
        // The keyboard half's own filter, not just its naming: the question is
        // whether it would keep this stroke at all.
        let tap = KeySignatureFilter.signature(
            for: KeyEvent(timestamp: 0, keyCode: code, modifiers: shortcut.modifiers)
        )?.storageKey
        report(tap == shortcut.signature,
               "\(label): menu=\(shortcut.signature.padding(toLength: 16, withPad: " ", startingAt: 0)) tap=\(tap ?? "nil")")
    }
    if coachable == 0 { print("  (\(label): nothing coachable to compare)") }
}

// MARK: - Section 1: our own menu, no grant needed

func verifyOwnMenu() -> [MenuItemSnapshot] {
    let reader = AXMenuAccessibility()
    print("AXIsProcessTrusted() = \(reader.isAvailable)   <- the gate the tracker needs for OTHER apps")
    print("reading our own menu bar without that gate\n")

    guard let bars = reader.readMenuBar(pid: getpid()) else {
        print("!! could not read the menu bar"); exit(1)
    }
    // Ours is the last menu bar item; AppKit synthesises the Apple menu first.
    guard let mine = bars.last, let commands = mine.openMenu?() else {
        print("!! no menu with contents"); exit(1)
    }
    print("read \(commands.count) commands from a menu holding \(cases.count)\n")

    for (i, c) in cases.enumerated() {
        guard i < commands.count else {
            report(false, "\(c.title): only \(commands.count) commands read")
            continue
        }
        let snap = commands[i]
        let got = snap.shortcut?.signature
        let note = c.note.isEmpty ? "" : "   (\(c.note))"
        report(got == c.want,
               "\(c.title.padding(toLength: 16, withPad: " ", startingAt: 0)) enabled=\(snap.isEnabled ? "y" : "n")  want=\((c.want ?? "nil").padding(toLength: 16, withPad: " ", startingAt: 0)) got=\(got ?? "nil")\(note)")
    }
    return commands
}

/// The menu half and the keyboard half must name the SAME gesture, or adoption
/// detection never fires. The gesture comes from the layout, read here by
/// hand, so this is a real comparison and not the menu being asked to agree
/// with itself.
func verifyMenuAgainstKeyboard(_ commands: [MenuItemSnapshot]) {
    print("\n--- menu half vs keyboard half, gesture by gesture ---")
    var agree = 0, differ = 0
    for (i, c) in cases.enumerated() where c.want != nil {
        guard i < commands.count, let shortcut = commands[i].shortcut else { continue }

        let gesture: (code: UInt16, needsShift: Bool)?
        if let special = specialKeyCodes[c.title] {
            // A function or special key: named outright, never through the
            // layout, so there is no shift to infer.
            gesture = (special, false)
        } else {
            gesture = physicalGesture(for: c.key)
        }

        // The modifiers a hand actually holds: everything the app declared,
        // plus ⇧ if the character cannot be printed without it. Both sources —
        // a menu printing ⇧⌘B declares the shift; a menu printing ⌘* carries it
        // in the character — which is the same union the library applies.
        var modifiers = ModifierSet()
        if c.mods.contains(.command) { modifiers.insert(.command) }
        if c.mods.contains(.option) { modifiers.insert(.option) }
        if c.mods.contains(.control) { modifiers.insert(.control) }
        if c.mods.contains(.shift) { modifiers.insert(.shift) }
        if let gesture, gesture.needsShift { modifiers.insert(.shift) }

        let tap = gesture.flatMap { viaKeyboard(keyCode: $0.code, modifiers: modifiers) }
        let ok = tap == shortcut.signature
        if ok { agree += 1 } else { differ += 1 }
        let code = gesture.map { String($0.code) } ?? "nil"
        print("  \(ok ? "agree " : "DIFFER") \(c.title.padding(toLength: 16, withPad: " ", startingAt: 0)) menu=\(shortcut.signature.padding(toLength: 16, withPad: " ", startingAt: 0)) keycode=\(code.padding(toLength: 4, withPad: " ", startingAt: 0)) tap=\(tap ?? "nil")")
    }
    print("\(agree) agree, \(differ) differ")
}

/// The disabled rule through the real state machine. Only the geometry is
/// substituted — this app is launched from a terminal, so AppKit reports
/// degenerate frames for its menu bar; `isEnabled` and `shortcut` are the real
/// values just read out of accessibility.
@MainActor
func verifyDisabledThroughTracker(_ commands: [MenuItemSnapshot]) async {
    print("\n--- disabled item, through MenuClickTracker ---")
    var laidOut: [MenuItemSnapshot] = []
    var row: CGFloat = 100
    for snap in commands {
        laidOut.append(MenuItemSnapshot(
            frame: CGRect(x: 50, y: row, width: 300, height: 24),
            shortcut: snap.shortcut,
            isEnabled: snap.isEnabled,
            openMenu: snap.openMenu))
        row += 24
    }
    let barItem = MenuItemSnapshot(
        frame: CGRect(x: 100, y: 0, width: 120, height: 24),
        shortcut: nil, isEnabled: true,
        openMenu: { laidOut })
    final class Fixed: MenuAccessibilityReading {
        let items: [MenuItemSnapshot]
        init(items: [MenuItemSnapshot]) { self.items = items }
        var isAvailable: Bool { true }
        func menuBarItems(pid: pid_t) -> [MenuItemSnapshot]? { items }
    }
    let tracker = MenuClickTracker(
        accessibility: Fixed(items: [barItem]),
        menuBarStrip: { CGRect(x: 0, y: 0, width: 1440, height: 24) },
        menuLifetime: 30)

    func centre(_ index: Int) -> CGPoint {
        let f = laidOut[index].frame
        return CGPoint(x: f.midX, y: f.midY)
    }
    let greyIndex = cases.firstIndex { $0.title == "Greyed Save" }!
    let saveIndex = cases.firstIndex { $0.title == "Save" }!

    let opened = await tracker.click(at: CGPoint(x: 160, y: 12), app: "probe", pid: getpid())
    print("  click 1 (menu bar item): \(opened ?? "nil")   want: nil")
    let picked = await tracker.click(at: centre(greyIndex), app: "probe", pid: getpid())
    print("  click 2 (greyed command): \(picked ?? "nil")   want: nil")
    report(picked == nil, "greyed command recorded nothing")
    let saved = await tracker.click(at: centre(saveIndex), app: "probe", pid: getpid())
    print("  click 3 (enabled Save): \(saved ?? "nil")   want: cmd+s")
    report(saved == "cmd+s", "enabled command still recorded")

    // The globe bit riding on a real menu item, through the same tracker: a
    // mask that carries it must record nothing at all, which is what stops
    // 🌐⌃C from being written as ctrl+c.
    let globeC = MenuItemSnapshot(
        frame: CGRect(x: 50, y: 100, width: 300, height: 24),
        shortcut: AXMenuAccessibility.shortcut(
            fromKeyCode: nil, character: "C", modifierMask: 28),
        isEnabled: true,
        openMenu: nil)
    let globeF = MenuItemSnapshot(
        frame: CGRect(x: 50, y: 124, width: 300, height: 24),
        shortcut: AXMenuAccessibility.shortcut(
            fromKeyCode: 0x03, character: nil, modifierMask: 24),
        isEnabled: true,
        openMenu: nil)
    report(globeC.shortcut == nil, "🌐⌃C (mask 28) resolves to no shortcut")
    report(globeF.shortcut == nil, "🌐F (mask 24) resolves to no shortcut")
    let globeBar = MenuItemSnapshot(
        frame: CGRect(x: 100, y: 0, width: 120, height: 24),
        shortcut: nil, isEnabled: true,
        openMenu: { [globeC, globeF] })
    let globeTracker = MenuClickTracker(
        accessibility: Fixed(items: [globeBar]),
        menuBarStrip: { CGRect(x: 0, y: 0, width: 1440, height: 24) },
        menuLifetime: 30)
    let openedGlobe = await globeTracker.click(at: CGPoint(x: 160, y: 12), app: "probe", pid: getpid())
    report(openedGlobe == nil, "opening a globe-key menu records nothing")
    let pickedGlobe = await globeTracker.click(at: centre(0), app: "probe", pid: getpid())
    report(pickedGlobe == nil, "a globe-key command records nothing through the tracker")
    let pickedGlobe2 = await globeTracker.click(at: centre(1), app: "probe", pid: getpid())
    report(pickedGlobe2 == nil, "and neither does the other one")
}

// MARK: - Section 2: the raw modifier masks, no grant needed

/// The masks real system menus report. Measured against Finder and Chrome on
/// macOS 27, both permissions granted:
///
/// | menu command | printed | mask |
/// |---|---|---|
/// | 显示 › 进入全屏幕 | 🌐F | 24 |
/// | 显示 › 进入全屏幕 | 🌐F | 20 |
/// | 编辑 › 表情与符号 | 🌐E | 24 |
/// | 窗口 › 居中 | 🌐⌃C | 28 |
/// | 窗口 › 填充 | 🌐F | 28 |
///
/// Bit 4 (16) is the globe key, and it is not in the public SDK —
/// `AXAttributeConstants.h` stops at NoCommand, and Carbon's `kMenu*Modifier`
/// enum stops there too. What matters is not naming it but what is left when
/// it is read as absence:
///
/// - 28 is bit 4 | ⌃ | NoCommand. Drop bit 4 and what is left is ⌃C — a real
///   shortcut, and the one a terminal already uses for SIGINT.
/// - 20 is bit 4 | ⌃. Drop bit 4 and ⌘ stays implicit, so what is left is
///   ⌃⌘F — also a real shortcut.
/// - 16 alone drops to zero, which is ⌘ alone.
///
/// 24 (bit 4 | NoCommand) is the one that survives being misread, and only by
/// accident: it drops to NoCommand, a bare F with no ⌘, which the command
/// filter refuses anyway. A mask that is wrong only where another check
/// happens to catch it is not a mask that is being read.
///
/// The "would have been" column is the decode the old code produced, printed
/// next to the one this code produces. `nil` there is a mask that was saved by
/// a different rule, not one that was read correctly.
func verifyRawMasks() {
    section("2. the raw modifier masks, including the globe bit")
    print("measured against Finder and Chrome on macOS 27\n")

    let measured: [(String, Int, String, Int?, String?)] = [
        ("显示 › 进入全屏幕", 24, "🌐F",  0x03, nil),
        ("显示 › 进入全屏幕", 20, "🌐F",  0x03, nil),
        ("编辑 › 表情与符号", 24, "🌐E",  nil, "E"),
        ("窗口 › 居中",       28, "🌐⌃C", nil, "C"),
        ("窗口 › 填充",       28, "🌐F",  0x03, nil),
    ]
    print("  \("command".padding(toLength: 22, withPad: " ", startingAt: 0)) \("printed".padding(toLength: 8, withPad: " ", startingAt: 0)) \("mask".padding(toLength: 5, withPad: " ", startingAt: 0)) \("taught".padding(toLength: 8, withPad: " ", startingAt: 0)) would have been")
    for (command, mask, printed, keyCode, character) in measured {
        let taught = AXMenuAccessibility.shortcut(
            fromKeyCode: keyCode, character: character, modifierMask: mask)?.signature ?? "nil"
        // What the same reading decodes to once the undocumented bit is
        // dropped — the wrong answer the old code gave.
        let dropped = AXMenuAccessibility.shortcut(
            fromKeyCode: keyCode, character: character,
            modifierMask: mask & 0b1111)?.signature ?? "nil"
        report(taught == "nil",
               "\(command.padding(toLength: 22, withPad: " ", startingAt: 0)) \(printed.padding(toLength: 8, withPad: " ", startingAt: 0)) \(String(mask).padding(toLength: 5, withPad: " ", startingAt: 0)) \(taught.padding(toLength: 8, withPad: " ", startingAt: 0)) \(dropped)")
    }

    // A missing mask is a mask of zero — ⌘ alone — not a missing shortcut.
    print("")
    report(AXMenuAccessibility.shortcut(fromKeyCode: nil, character: "S", modifierMask: nil)?.signature == "cmd+s",
           "an item reporting no mask at all still reads as ⌘S")
    report(AXMenuAccessibility.shortcut(fromKeyCode: nil, character: nil, modifierMask: nil) == nil,
           "an item reporting nothing at all reads as no shortcut")

    // The same four masks over one key, so the drop is visible side by side.
    // "would have been" is what the reading says once bit 4 is thrown away;
    // `nil` there is a mask another rule caught, not one that was read right.
    print("")
    for mask in [16, 20, 28, 24] {
        let taught = AXMenuAccessibility.shortcut(
            fromKeyCode: 0x03, character: nil, modifierMask: mask)?.signature ?? "nil"
        let dropped = AXMenuAccessibility.shortcut(
            fromKeyCode: 0x03, character: nil, modifierMask: mask & 0b1111)?.signature ?? "nil"
        report(taught == "nil",
               "🌐F under mask \(String(mask).padding(toLength: 3, withPad: " ", startingAt: 0)): taught \(taught.padding(toLength: 4, withPad: " ", startingAt: 0)), would have been \(dropped)")
    }

    // Every mask above the four documented bits, over a letter and a function
    // key both: none of them may teach anything.
    print("")
    var refused = 0
    for mask in 16..<256 {
        for (keyCode, character) in [(0x01, "s" as String?), (0x03, nil as String?)] {
            if AXMenuAccessibility.shortcut(fromKeyCode: keyCode, character: character,
                                            modifierMask: mask) == nil { refused += 1 }
        }
    }
    report(refused == 240 * 2, "all 240 masks above the documented bits refuse to teach (\(refused)/480)")

    // And the documented ones still decode — the filter is about unreadable
    // modifiers, not about modifiers.
    var decoded = 0
    for mask in 0..<16 {
        if AXMenuAccessibility.shortcut(fromKeyCode: 0x01, character: nil, modifierMask: mask) != nil { decoded += 1 }
    }
    report(decoded > 0, "the 16 documented masks still decode (\(decoded) of them)")
}

// MARK: - Section 3: the whole pipeline, in a data directory of its own

final class SilentTap: KeyEventSource {
    var onEvent: ((KeyEvent) -> Void)?
    var onMenuClick: ((MenuClick) -> Void)?
    var watchesMouse = false
    func start() -> TapStartResult { .running }
    func stop() {}
}

final class GrantedPermission: PermissionChecking {
    func isGranted() -> Bool { true }
    func promptOnce() {}
    func openSettings() {}
}

/// A menu bar that lives in this process rather than on a screen. Faithful to
/// the real reader's contract: nil when the permission is missing.
final class ProbeMenus: MenuAccessibilityReading, @unchecked Sendable {
    var items: [MenuItemSnapshot]?
    var isAvailable: Bool { true }
    func menuBarItems(pid: pid_t) -> [MenuItemSnapshot]? { items }
}

/// One menu element: where it sits, the shortcut it prints, what it opens.
func probeItem(_ frame: CGRect, shortcut: String? = nil,
               submenu: [MenuItemSnapshot]? = nil, isEnabled: Bool = true) -> MenuItemSnapshot {
    MenuItemSnapshot(frame: frame,
                     shortcut: shortcut.flatMap { MenuShortcut(signature: $0) },
                     isEnabled: isEnabled,
                     openMenu: submenu.map { items in { items } })
}

@MainActor
func verifyPipeline() async {
    section("3. the whole pipeline, in a data directory of its own")

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("lm-verify-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let suite = "lm-verify-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let settings = SettingsStore(defaults: defaults)
    settings.isMenuCoachEnabled = true

    let menus = ProbeMenus()
    // File (the menu bar item) → Save ⌘S, and the same shape for the globe and
    // bare-letter commands that must record nothing.
    let save = probeItem(CGRect(x: 8, y: 24, width: 140, height: 22), shortcut: "cmd+s")
    let globeC = probeItem(CGRect(x: 8, y: 46, width: 140, height: 22),
                           shortcut: nil)   // mask 28 → unteachable
    let bareA = probeItem(CGRect(x: 8, y: 68, width: 140, height: 22), shortcut: nil)
    menus.items = [probeItem(CGRect(x: 8, y: 0, width: 40, height: 24),
                             submenu: [save, globeC, bareA])]

    let store = StatsStore(directory: directory, calendar: .current, now: Date.init)
    let tracker = MenuClickTracker(accessibility: menus,
                                   menuBarStrip: { CGRect(x: 0, y: 0, width: 1440, height: 24) })
    let state = AppState(store: store, settings: settings, monitor: SilentTap(),
                         permission: GrantedPermission(), menuTracker: tracker,
                         publishDelay: 0.01)
    print("data directory: \(directory.path)")
    print("(the real ~/Library data is never touched)\n")

    // The coach's own entry point, so the settings gate is exercised too.
    func pick(_ row: CGFloat) {
        state.ingestMenuClick(MenuClick(point: CGPoint(x: 20, y: 12),
                                        application: "com.apple.TextEdit", pid: 42))
        state.ingestMenuClick(MenuClick(point: CGPoint(x: 60, y: row),
                                        application: "com.apple.TextEdit", pid: 42))
    }
    let saveRow: CGFloat = 36, globeRow: CGFloat = 58, bareRow: CGFloat = 80
    let cardID = MenuRuleFactory.id(for: "cmd+s")

    // Two picks: not yet a habit.
    pick(saveRow); pick(saveRow)
    try? await Task.sleep(for: .milliseconds(120))
    state.popoverDidOpen()
    report(state.unreadCount == 0, "two picks are not yet a habit")
    report(state.today.totalMenuCommands == 2, "both picks counted (today = \(state.today.totalMenuCommands))")

    // The third is.
    pick(saveRow)
    try? await Task.sleep(for: .milliseconds(120))
    state.popoverDidOpen()
    report(state.today.totalMenuCommands == 3, "the third pick counted")
    report(state.unreadCount == 1, "and it made a card")
    report(state.rules.contains { $0.id == cardID }, "the card is on the shelf the UI reads")
    report(state.rule(withID: cardID)?.primaryShortcutLabel == "⌘S",
           "the card names ⌘S (got \(state.rule(withID: cardID)?.primaryShortcutLabel ?? "nil"))")

    // What landed on disk.
    store.flush()
    let json = (try? String(contentsOf: store.storageURL, encoding: .utf8)) ?? ""
    report(json.contains("\"cmd+s\""), "stats.json names cmd+s")
    report(json.contains("\"menuCommands\""), "stats.json has the menuCommands ledger")
    report(store.menuCommandCount("cmd+s") == 3,
           "and reading it back gives 3 (got \(store.menuCommandCount("cmd+s")))")

    // Pressing the taught shortcut adopts it — the same keystroke path the
    // rest of the book uses.
    state.ingest(KeyEvent(timestamp: 1, keyCode: 0x01, modifiers: .command,
                          application: "com.apple.TextEdit"))
    report(state.celebration == cardID, "pressing ⌘S celebrated the card")
    report(state.suggestionStates[cardID]?.status == .adopted, "and it flipped to adopted")

    // The globe and bare-letter commands: nothing may be recorded for them,
    // and no card may appear for them.
    let before = state.today.totalMenuCommands
    pick(globeRow); pick(globeRow); pick(globeRow)      // the globe-key command
    pick(bareRow); pick(bareRow); pick(bareRow)          // the bare-letter command
    try? await Task.sleep(for: .milliseconds(120))
    state.popoverDidOpen()
    report(state.today.totalMenuCommands == before,
           "the globe-key and bare-letter commands recorded nothing (today = \(state.today.totalMenuCommands))")
    report(state.rules.filter { $0.id.hasPrefix(MenuRuleFactory.idPrefix) }.count == 1,
           "and no card appeared for either of them")

    // Erasing takes the menu card with it.
    state.eraseAllData()
    report(state.rules.count == RuleLibrary.all.count,
           "erasing leaves the book alone (\(state.rules.count) rules)")
    report(store.menuCommandCount("cmd+s") == 0, "and clears the ledger")
}

// MARK: - Section 4: a real app's menu bar, grant required

/// One menu item's raw shortcut readings, taken straight from accessibility.
///
/// Read here, by hand, rather than through the library: the point is to see
/// what the *element* reports before the library decides anything about it.
/// Only the three shortcut attributes are requested. The title is not among
/// them, for the same reason it is not in the library.
struct RawShortcut {
    let keyCode: Int?
    let character: String?
    let modifierMask: Int?
}

func rawNumber(_ value: AnyObject) -> Int? {
    guard CFGetTypeID(value) != AXValueGetTypeID() else { return nil }
    return (value as? NSNumber)?.intValue
}

func rawShortcut(of element: AXUIElement) -> RawShortcut {
    var values: CFArray?
    guard AXUIElementCopyMultipleAttributeValues(
        element,
        [kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdCharAttribute,
         kAXMenuItemCmdModifiersAttribute] as CFArray,
        [], &values) == .success,
        let values = values as? [AnyObject], values.count == 3
    else { return RawShortcut(keyCode: nil, character: nil, modifierMask: nil) }
    return RawShortcut(keyCode: rawNumber(values[0]),
                       character: values[1] as? String,
                       modifierMask: rawNumber(values[2]))
}

/// Every menu item in the tree under `element`, with its raw readings. Walks
/// the whole tree rather than one level, so submenus are included.
func everyMenuItem(_ element: AXUIElement, depth: Int = 0,
                   into out: inout [RawShortcut]) {
    guard depth < 16 else { return }
    var roleValue: CFTypeRef?
    let role = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success
        ? (roleValue as? String) : nil
    if role == kAXMenuItemRole {
        AXUIElementSetMessagingTimeout(element, AXMenuAccessibility.messagingTimeout)
        out.append(rawShortcut(of: element))
    }
    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AnyObject] else { return }
    for child in children where CFGetTypeID(child) == AXUIElementGetTypeID() {
        everyMenuItem(child as! AXUIElement, depth: depth + 1, into: &out)
    }
}

func verifyFrontmostApp() {
    section("4. the frontmost app's real menu bar")
    guard AXIsProcessTrusted() else {
        print("Accessibility is not granted here, so cross-process reads cannot")
        print("be checked on this machine. Grant it and re-run to close that gap.")
        skip("frontmost app's menus: no Accessibility grant")
        return
    }

    guard let front = NSWorkspace.shared.frontmostApplication else {
        print("!! no frontmost app"); return
    }
    print("app: \(front.localizedName ?? "?") (\(front.bundleIdentifier ?? "?")) pid \(front.processIdentifier)")

    let reader = AXMenuAccessibility()
    guard let bars = reader.menuBarItems(pid: front.processIdentifier) else {
        print("!! could not read its menu bar")
        skip("frontmost app's menus: no menu bar exposed")
        return
    }
    print("menu bar items: \(bars.count)")

    var commandCount = 0, withShortcut = 0, disabled = 0
    var everyCommand: [MenuItemSnapshot] = []
    for bar in bars {
        let commands = bar.openMenu?() ?? []
        everyCommand.append(contentsOf: commands)
        for command in commands {
            commandCount += 1
            if command.shortcut != nil { withShortcut += 1 }
            if !command.isEnabled { disabled += 1 }
        }
    }
    print("commands read: \(commandCount)")
    print("  with a coachable shortcut: \(withShortcut)")
    print("  disabled: \(disabled)")

    // The number that matters: of the commands that PRINT a shortcut, how many
    // did the coach actually resolve? Anything short of all of them is a miss.
    print("\nA healthy app resolves every command that prints a shortcut.")
    print("If \(withShortcut) is far below what the menu visibly prints, that is")
    print("the bug this tool exists to catch.")

    // The same invariant, on another app's real menu bar — the half a machine
    // without the grant cannot reach at all.
    print("\n--- everything coachable is a gesture a keystroke writes ---")
    verifyTwoHalvesAgree(everyCommand, front.localizedName ?? "app")

    // Every menu item in the whole tree, submenus included, with its raw
    // readings — this is the half that finds the globe bit.
    var raw: [RawShortcut] = []
    everyMenuItem(AXUIElementCreateApplication(front.processIdentifier), into: &raw)
    print("\n--- menu items read from the whole tree: \(raw.count) ---")

    var globe: [(RawShortcut, String)] = []
    for item in raw {
        guard let mask = item.modifierMask,
              AXMenuAccessibility.carriesAnUnverifiableModifier(mask: mask) else { continue }
        let dropped = AXMenuAccessibility.shortcut(
            fromKeyCode: item.keyCode, character: item.character,
            modifierMask: mask & 0b1111)?.signature ?? "nil"
        globe.append((item, dropped))
    }

    if globe.isEmpty {
        print("  no item carries a modifier bit outside the four the SDK documents.")
        print("  That is the expected answer for most apps — the globe key is rare,")
        print("  and this app may simply not use it. Finder and Chrome both do.")
    } else {
        print("  \("mask".padding(toLength: 5, withPad: " ", startingAt: 0)) \("keyCode".padding(toLength: 8, withPad: " ", startingAt: 0)) \("char".padding(toLength: 6, withPad: " ", startingAt: 0)) \("taught".padding(toLength: 8, withPad: " ", startingAt: 0)) would have been")
        for (item, dropped) in globe {
            let taught = AXMenuAccessibility.shortcut(
                fromKeyCode: item.keyCode, character: item.character,
                modifierMask: item.modifierMask)?.signature ?? "nil"
            print("  \(String(item.modifierMask!).padding(toLength: 5, withPad: " ", startingAt: 0)) \((item.keyCode.map { String($0) } ?? "-").padding(toLength: 8, withPad: " ", startingAt: 0)) \((item.character ?? "-").padding(toLength: 6, withPad: " ", startingAt: 0)) \(taught.padding(toLength: 8, withPad: " ", startingAt: 0)) \(dropped)")
            report(taught == "nil",
                   "mask \(item.modifierMask!) is unreadable, so it teaches nothing (not \(dropped))")
        }
    }
}

// MARK: - Section 5: a hung app does not stall the read

/// One stopped process, one read, one measurement. The read is bounded by
/// `AXMenuAccessibility.messagingTimeout`; without that bound a stopped app
/// holds the reader queue for seconds and the clicks queued behind it arrive
/// after the menu has closed.
func verifyHungApp() {
    section("5. a hung app does not stall the read")
    guard AXIsProcessTrusted() else {
        skip("hung app: no Accessibility grant, so nothing would hang")
        return
    }

    let sleep = Process()
    sleep.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleep.arguments = ["60"]
    do { try sleep.run() } catch {
        skip("hung app: could not start a helper process (\(error.localizedDescription))")
        return
    }
    let pid = sleep.processIdentifier
    // SIGSTOP, not a hung modal: deterministic, and the helper is a plain
    // `sleep` that nothing depends on. SIGCONT comes before the exit either way.
    defer {
        kill(pid, SIGCONT)
        sleep.waitUntilExit()
    }
    kill(pid, SIGSTOP)
    usleep(200_000)   // let the stop land

    let reader = AXMenuAccessibility()
    let bound = Double(AXMenuAccessibility.messagingTimeout)

    // Three reads, because one measurement is noise.
    var worst = 0.0
    for i in 1...3 {
        let start = DispatchTime.now()
        _ = reader.menuBarItems(pid: pid)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        worst = max(worst, elapsed)
        print("  read \(i): \(String(format: "%.3f", elapsed))s")
    }
    print("  worst: \(String(format: "%.3f", worst))s   bound: \(bound)s")

    // A stopped app cannot answer at all, so every read should come back at
    // the bound rather than hanging. Some margin for scheduling noise.
    report(worst <= bound + 1.0,
           "a stopped app cost at most the bound, not seconds (worst \(String(format: "%.3f", worst))s)")

    // And a healthy read is nowhere near the bound — that is what keeps the
    // timeout from eating real menus.
    let start = DispatchTime.now()
    _ = reader.menuBarItems(pid: getpid())
    let healthy = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
    print("  our own menu bar: \(String(format: "%.3f", healthy))s")
    report(healthy < bound, "a healthy read is well inside the bound (\(String(format: "%.3f", healthy))s)")
}

// MARK: - Go

DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    Task { @MainActor in
        section("1. our own menu, no Accessibility grant needed")
        let commands = verifyOwnMenu()
        verifyMenuAgainstKeyboard(commands)
        verifyTwoHalvesAgree(commands, "own menu")
        await verifyDisabledThroughTracker(commands)

        verifyRawMasks()
        await verifyPipeline()

        verifyFrontmostApp()
        verifyHungApp()

        total()
        exit(fail == 0 ? 0 : 1)
    }
}
app.run()
