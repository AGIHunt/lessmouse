import Foundation
import CoreGraphics
import Testing
@testable import LessMouseCore

/// The menu coach's front half: turning two mouse clicks into a signature,
/// without a menu bar, a screen, or a permission prompt anywhere in sight.
@MainActor
@Suite(.serialized)
struct MenuCoachTests {
    /// The system menu bar's strip, in the coordinate space a CGEvent reports.
    private let strip = CGRect(x: 0, y: 0, width: 1200, height: 24)

    // MARK: - Fakes

    /// A menu bar that lives in a test rather than on a screen. Faithful to the
    /// real reader's contract: when the permission is missing it answers "no
    /// menus" rather than throwing.
    private final class FakeMenus: MenuAccessibilityReading, @unchecked Sendable {
        var items: [MenuItemSnapshot]?
        var available = true
        private(set) var readCount = 0

        var isAvailable: Bool { available }

        func menuBarItems(pid: pid_t) -> [MenuItemSnapshot]? {
            readCount += 1
            return available ? items : nil
        }
    }

    /// One menu element: where it sits, the shortcut it prints, and what it
    /// opens. A nil `openMenu` is a leaf.
    private func item(_ frame: CGRect,
                      shortcut: String? = nil,
                      submenu: [MenuItemSnapshot]? = nil,
                      isEnabled: Bool = true) -> MenuItemSnapshot {
        let open: (() -> [MenuItemSnapshot])?
        if let submenu {
            open = { submenu }
        } else {
            open = nil
        }
        return MenuItemSnapshot(
            frame: frame,
            shortcut: shortcut.flatMap { MenuShortcut(signature: $0) },
            isEnabled: isEnabled,
            openMenu: open)
    }

    /// A clock the test can wind forward.
    private final class Clock {
        var seconds: TimeInterval = 0
        func advance(_ by: TimeInterval) { seconds += by }
    }

    private func tracker(_ menus: FakeMenus, _ clock: Clock) -> MenuClickTracker {
        MenuClickTracker(accessibility: menus,
                         menuBarStrip: { self.strip },
                         now: { Date(timeIntervalSince1970: clock.seconds) })
    }

    /// The menu bar the tests click through: File (with Save ⌘S, Open Recent ›,
    /// Quit) and Edit.
    private func menuBar() -> [MenuItemSnapshot] {
        let save = item(CGRect(x: 8, y: 24, width: 140, height: 22), shortcut: "cmd+s")
        let recent = item(CGRect(x: 8, y: 46, width: 140, height: 22),
                          submenu: [
                            item(CGRect(x: 148, y: 46, width: 200, height: 22),
                                 shortcut: "cmd+shift+o"),
                            item(CGRect(x: 148, y: 68, width: 200, height: 22))
                          ])
        let quit = item(CGRect(x: 8, y: 68, width: 140, height: 22))
        return [
            item(CGRect(x: 8, y: 0, width: 40, height: 24), submenu: [save, recent, quit]),
            item(CGRect(x: 48, y: 0, width: 40, height: 24), submenu: [])
        ]
    }

    // MARK: - The two-click habit

    @Test func openingAMenuThenPickingACommandYieldsItsSignature() async {
        let menus = FakeMenus()
        menus.items = menuBar()
        let clock = Clock()
        let tracker = tracker(menus, clock)

        // Opening "File" says nothing on its own — it is not a command.
        #expect(await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42) == nil)
        #expect(menus.readCount == 1, "the menu bar is read once, on the opening click")

        // Picking Save out of it does.
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "com.apple.TextEdit", pid: 42) == "cmd+s")
        #expect(menus.readCount == 1,
                "the menu's contents come from the click that resolves the command, not another read")
    }

    @Test func aCommandWithoutAShortcutTeachesNothing() async {
        let menus = FakeMenus()
        menus.items = menuBar()
        let clock = Clock()
        let tracker = tracker(menus, clock)

        _ = await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42)
        // Quit prints no shortcut: nothing to coach, and nothing stored.
        #expect(await tracker.click(at: CGPoint(x: 60, y: 74), app: "com.apple.TextEdit", pid: 42) == nil)
    }

    @Test func aSubmenuIsFollowedTheSameWayAsAMenu() async {
        let menus = FakeMenus()
        menus.items = menuBar()
        let clock = Clock()
        let tracker = tracker(menus, clock)

        _ = await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42)
        // "Open Recent ›" opens a submenu instead of running.
        #expect(await tracker.click(at: CGPoint(x: 60, y: 52), app: "com.apple.TextEdit", pid: 42) == nil)
        // One more click lands inside it, on an item that has a shortcut.
        #expect(await tracker.click(at: CGPoint(x: 200, y: 52), app: "com.apple.TextEdit", pid: 42)
               == "cmd+shift+o")
    }

    // MARK: - What is not a command

    @Test func anOrdinaryClickNeverReachesTheAccessibilityAPI() async {
        let menus = FakeMenus()
        menus.items = menuBar()
        let clock = Clock()
        let tracker = tracker(menus, clock)

        // Middle of a document: not the strip, and no menu is open.
        #expect(await tracker.click(at: CGPoint(x: 600, y: 600), app: "com.apple.TextEdit", pid: 42) == nil)
        #expect(menus.readCount == 0,
                "a click that cannot be a menu command must cost nothing at all")
    }

    @Test func aStaleMenuIsNotResolved() async {
        let menus = FakeMenus()
        menus.items = menuBar()
        let clock = Clock()
        let tracker = tracker(menus, clock)

        _ = await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42)
        // The menu closed long ago; a click where it used to be is just a click.
        clock.advance(60)
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "com.apple.TextEdit", pid: 42) == nil)
        // And it is not still pending afterwards either.
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "com.apple.TextEdit", pid: 42) == nil)
    }

    @Test func aMissClearsTheOpenMenu() async {
        let menus = FakeMenus()
        menus.items = menuBar()
        let clock = Clock()
        let tracker = tracker(menus, clock)

        _ = await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42)
        // Clicking outside the menu dismisses it.
        #expect(await tracker.click(at: CGPoint(x: 900, y: 900), app: "com.apple.TextEdit", pid: 42) == nil)
        // So the next click over where Save was resolves nothing.
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "com.apple.TextEdit", pid: 42) == nil)
    }

    @Test func anotherAppsMenuIsNeverThisAppsHabit() async {
        let menus = FakeMenus()
        menus.items = menuBar()
        let clock = Clock()
        let tracker = tracker(menus, clock)

        _ = await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42)
        // The frontmost app changed between the two clicks: the menu left open
        // belongs to the app we just left.
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "com.apple.Safari", pid: 43) == nil)
    }

    @Test func withoutThePermissionNothingIsRead() async {
        let menus = FakeMenus()
        menus.available = false
        let clock = Clock()
        let tracker = tracker(menus, clock)

        #expect(tracker.canReadMenus == false)
        // The tracker still asks — the reader is the one that knows it cannot
        // answer, and it answers "no menus" without touching another app.
        #expect(await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42) == nil)
        #expect(menus.readCount == 1)
    }

    @Test func anAppWithNoMenuBarReadsAsNothingToCoach() async {
        let menus = FakeMenus()
        menus.items = []
        let clock = Clock()
        let tracker = tracker(menus, clock)

        #expect(await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.games.kiosk", pid: 42) == nil)
    }

    // MARK: - A command that cannot run

    /// A greyed-out command prints its shortcut but does nothing when clicked,
    /// and does not even close the menu. Counting it would teach a shortcut
    /// the user cannot use, and would throw away a menu that is still open.
    @Test func aDisabledCommandIsNotAUse() async {
        let menus = FakeMenus()
        let save = item(CGRect(x: 8, y: 24, width: 140, height: 22),
                        shortcut: "cmd+s", isEnabled: false)
        let close = item(CGRect(x: 8, y: 46, width: 140, height: 22), shortcut: "cmd+w")
        menus.items = [item(CGRect(x: 8, y: 0, width: 40, height: 24),
                            submenu: [save, close])]
        let clock = Clock()
        let tracker = tracker(menus, clock)

        // Open the menu.
        await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42)
        // The greyed Save records nothing...
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "com.apple.TextEdit", pid: 42) == nil)
        // ...and the menu is still open, so the very next click still resolves.
        #expect(await tracker.click(at: CGPoint(x: 60, y: 52), app: "com.apple.TextEdit", pid: 42) == "cmd+w")
    }

    /// A menu that is nothing but greyed-out commands must not leave the
    /// tracker holding a menu it will keep resolving into.
    @Test func aWholeMenuOfDisabledCommandsRecordsNothing() async {
        let menus = FakeMenus()
        menus.items = [item(CGRect(x: 8, y: 0, width: 40, height: 24),
                            submenu: [
                                item(CGRect(x: 8, y: 24, width: 140, height: 22),
                                     shortcut: "cmd+s", isEnabled: false),
                                item(CGRect(x: 8, y: 46, width: 140, height: 22),
                                     shortcut: "cmd+o", isEnabled: false)
                            ])]
        let clock = Clock()
        let tracker = tracker(menus, clock)

        await tracker.click(at: CGPoint(x: 20, y: 10), app: "com.apple.TextEdit", pid: 42)
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "com.apple.TextEdit", pid: 42) == nil)
        #expect(await tracker.click(at: CGPoint(x: 60, y: 52), app: "com.apple.TextEdit", pid: 42) == nil)
    }

    // MARK: - The signature model

    @Test func signaturesRoundTripThroughTheMenuForm() async {
        let save = MenuShortcut(signature: "cmd+s")
        #expect(save?.signature == "cmd+s")
        #expect(save?.displayLabel == "⌘S")
        #expect(save?.keyCaps == [.modifier(.command), .key("S")])

        // Modifier order in the stored form is not the display order, and the
        // round trip has to survive that: stored "opt+shift+left" prints as
        // the Mac does, ⌥ before ⇧.
        let select = MenuShortcut(signature: "opt+shift+left")
        #expect(select?.signature == "opt+shift+left")
        #expect(select?.displayLabel == "⌥⇧←")
        #expect(select?.keyCaps == [.modifier(.option), .modifier(.shift), .key("←")])

        // A bare navigation key the menu may legally print. Displayed the way
        // the menu prints it — ⌥⌘⎋, not ⌥⌘esc — while the stored form stays
        // "esc", which is what the keyboard half writes for the same key.
        let escape = MenuShortcut(signature: "esc")
        #expect(escape?.signature == "esc")
        #expect(escape?.keyCaps == [.key("⎋")])
        #expect(escape?.displayLabel == "⎋")
    }

    @Test func aSignatureThatCannotBeDrawnIsNotAShortcut() async {
        // An unmapped keycode: no keycap exists for it, so no card can teach it.
        #expect(MenuShortcut(signature: "cmd+k103") == nil)
        #expect(MenuShortcut(signature: "") == nil)
        #expect(MenuShortcut(signature: "cmd+") == nil)
    }

    // MARK: - The modifier mask

    /// `AXMenuItemCmdModifiers` treats ⌘ as implicit and needs an explicit
    /// "no command" bit — read the other way round, every menu would teach
    /// "⌘⌘S".
    @Test func modifierMasksReadTheWayMenusPrintThem() async {
        let shift = 1 << 0, option = 1 << 1, control = 1 << 2, noCommand = 1 << 3

        #expect(AXMenuAccessibility.modifiers(mask: 0) == [.command])
        #expect(AXMenuAccessibility.modifiers(mask: noCommand) == [])
        #expect(AXMenuAccessibility.modifiers(mask: shift) == [.command, .shift])
        #expect(AXMenuAccessibility.modifiers(mask: option) == [.command, .option])
        #expect(AXMenuAccessibility.modifiers(mask: control) == [.command, .control])
        #expect(AXMenuAccessibility.modifiers(mask: shift | option) == [.command, .shift, .option])
        #expect(AXMenuAccessibility.modifiers(mask: noCommand | shift) == [.shift])
        #expect(AXMenuAccessibility.modifiers(mask: noCommand | control) == [.control])

        // And the mask is what the signature is built from, so a masked ⌘S and
        // a pressed ⌘S write the same string.
        let masked = MenuShortcut(modifiers: AXMenuAccessibility.modifiers(mask: 0),
                                  key: KeyWhitelist.table[0x01]!)
        #expect(masked.signature == "cmd+s")

        // The measured masks, and what they must be read as: the globe key is
        // not one of the four documented bits, so a mask carrying it is
        // refused rather than decoded into a different shortcut.
        for mask in [24, 28, 20] {
            #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: mask) == true,
                    "mask \(mask) carries the globe key")
        }
    }

    // MARK: - What the coach costs when it is off

    /// Off means off, all the way down: the tap does not watch the mouse, so
    /// a user who never turns the coach on is watched for the keyboard alone.
    /// Building a tap is the one thing a test cannot do cheaply or undo, so
    /// this checks the mask rather than the tap.
    @Test func theTapWatchesTheMouseOnlyWhileTheCoachIsOn() {
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let leftMouseDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)

        #expect(KeyboardMonitor.eventMask(watchesMouse: false) == keyDown)
        #expect(KeyboardMonitor.eventMask(watchesMouse: true) == keyDown | leftMouseDown)
    }

    /// The accessibility read is bounded, or one hung app stalls the reader
    /// queue and the clicks queued behind it arrive after the menu closed.
    /// The bound itself is what this pins: short enough that a hung app costs
    /// a fraction of a second per click, long enough that a healthy app —
    /// measured at ~0.1s — always answers. How a hung app actually behaves is
    /// measured by the verification tool, not here.
    @Test func theAccessibilityReadIsBoundedToAFractionOfASecond() {
        #expect(AXMenuAccessibility.messagingTimeout >= 0.05,
                "too short to survive a healthy app, which answers in ~0.1s")
        #expect(AXMenuAccessibility.messagingTimeout <= 1.0,
                "too long: a hung app would hold the reader queue for seconds")
    }
}
