import Foundation
import CoreGraphics
import AppKit

/// Turns menu-bar clicks into "this menu command has a shortcut" facts.
///
/// The habit this watches is always *two* clicks: the user opens a menu with
/// the mouse, then picks a command out of it. Neither click on its own says
/// anything — clicking "Edit" is not a command — so the tracker remembers the
/// menu it just saw opened and resolves the *next* click against it, while
/// the menu is still on screen and its items still have real positions.
///
/// Reading the menu late is also what keeps it cheap. A menu bar holds a
/// dozen menus; reading all of them on every click would be a dozen
/// accessibility round trips per click. Instead the menu is read once, on the
/// click that might be a command.
///
/// Pure logic over injected snapshots: the accessibility API, the menu bar's
/// rectangle and the clock are all parameters, so the whole state machine is
/// tested without a menu bar.
///
/// Not an actor and not `@MainActor`, and deliberately so: the state machine
/// and the accessibility reads it drives run on `reader`, a serial queue of
/// this object's own. Reading another app's menu means waiting for that app,
/// and one that has stopped answering — `kill -STOP`, a hung modal — makes the
/// accessibility API wait with it: measured at roughly 1.5s per click against
/// 0.1s for a healthy app. Done on the main actor, that wait froze LessMouse's
/// UI and its key counting with it. Here it only delays the coach, and a click
/// that arrives while a read is in flight simply waits its turn.
public final class MenuClickTracker {
    private let accessibility: MenuAccessibilityReading
    private let menuBarStrip: () -> CGRect
    private let now: () -> Date
    /// How long an opened menu stays interesting. A click arriving after this
    /// landed somewhere else; the menu closed long ago.
    private let menuLifetime: TimeInterval

    /// The serial queue the two-click state machine and every accessibility
    /// read run on. Serial because the state is a sequence — two clicks
    /// resolved out of order would resolve neither correctly.
    private let reader = DispatchQueue(label: "app.lessmouse.menu-coach",
                                       qos: .userInitiated)

    private var pending: Pending?
    private var lastApp: String?

    /// Whether menus can be read at all right now. False means the user never
    /// granted Accessibility: the coach is dormant, and Settings is where they
    /// opt in — LessMouse never asks for it on its own.
    public var canReadMenus: Bool { accessibility.isAvailable }

    private struct Pending {
        let open: () -> [MenuItemSnapshot]
        let openedAt: Date
    }

    public init(accessibility: MenuAccessibilityReading,
                menuBarStrip: @escaping () -> CGRect = { MenuBarGeometry.strip() },
                now: @escaping () -> Date = { Date() },
                menuLifetime: TimeInterval = 8) {
        self.accessibility = accessibility
        self.menuBarStrip = menuBarStrip
        self.now = now
        self.menuLifetime = menuLifetime
    }

    /// Feed one left mouse press. The signature — when the press chose a menu
    /// command that has one — is delivered to `completion` on the main actor;
    /// never a title, never a position, never a count of anything but the
    /// command itself.
    public func click(at point: CGPoint, app: String?, pid: pid_t?,
                      completion: @escaping @MainActor (String?) -> Void) {
        // The menu bar's rectangle comes from AppKit, which belongs to the
        // caller's thread — the main actor in production — and not to the
        // reader queue below.
        let strip = menuBarStrip()
        reader.async { [self] in
            let signature = resolve(at: point, app: app, pid: pid, within: strip)
            Task { @MainActor in completion(signature) }
        }
    }

    /// Awaitable form of `click`, for callers that would rather not hand over
    /// a closure.
    public func click(at point: CGPoint, app: String?, pid: pid_t?) async -> String? {
        await withCheckedContinuation { continuation in
            click(at: point, app: app, pid: pid) { signature in
                continuation.resume(returning: signature)
            }
        }
    }

    // MARK: - Internals

    /// The two-click state machine. Runs on `reader`; touches nothing that
    /// belongs to the main actor.
    private func resolve(at point: CGPoint, app: String?, pid: pid_t?, within strip: CGRect) -> String? {
        // Another app's menu is never this app's habit, and a menu left open
        // by the app we just left must not be resolved into it.
        if app != lastApp {
            pending = nil
            lastApp = app
        }

        // A press in the menu bar strip is always a menu bar press: the
        // system menu bar owns that strip outright, whatever is under it.
        if strip.contains(point) {
            return menuBarClick(at: point, app: app, pid: pid)
        }

        guard let pending else { return nil }
        guard now().timeIntervalSince(pending.openedAt) <= menuLifetime else {
            self.pending = nil
            return nil
        }

        let items = pending.open()
        guard let hit = hitTest(items, at: point) else {
            // The click missed the menu, so the menu is gone with it.
            self.pending = nil
            return nil
        }
        return resolve(hit, app: app)
    }

    private func menuBarClick(at point: CGPoint, app: String?, pid: pid_t?) -> String? {
        guard let pid, let items = accessibility.menuBarItems(pid: pid) else {
            pending = nil
            return nil
        }
        guard let hit = hitTest(items, at: point) else {
            // The strip was pressed but no item was under it (the gap past
            // the last menu, an empty bar): nothing was opened.
            pending = nil
            return nil
        }
        return resolve(hit, app: app)
    }

    /// A hit inside a menu: either the command itself, or an item that opens
    /// a submenu ("Open Recent ›") which is remembered exactly the way a menu
    /// bar item was.
    private func resolve(_ hit: MenuItemSnapshot, app: String?) -> String? {
        // A greyed-out command cannot run, so clicking it used nothing — and
        // because it does not even close the menu, the menu is still open and
        // stays pending for the next click.
        guard hit.isEnabled else { return nil }
        if let shortcut = hit.shortcut {
            // The command ran; its menu is closed and there is nothing left
            // to resolve.
            pending = nil
            return shortcut.signature
        }
        pending = hit.openMenu.map { Pending(open: $0, openedAt: now()) }
        return nil
    }

    /// First item whose frame contains the point. Menu items never overlap,
    /// so the first hit is *the* item; a miss means the menu is no longer
    /// there.
    private func hitTest(_ items: [MenuItemSnapshot], at point: CGPoint) -> MenuItemSnapshot? {
        items.first { $0.frame.contains(point) }
    }
}

/// Where the system menu bar is, in the coordinate space a `CGEvent` reports
/// (global display points, top-left origin — not AppKit's bottom-left one).
public enum MenuBarGeometry {
    public static func strip() -> CGRect {
        // The menu bar lives on the primary display, whose Quartz bounds
        // start at the top-left corner of the global display space.
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGRect(x: bounds.minX, y: bounds.minY,
                      width: bounds.width, height: menuBarHeight())
    }

    /// The menu bar's height, from AppKit rather than a constant because it
    /// moves with the system's menu bar settings, and a strip that is too
    /// short silently misses clicks.
    ///
    /// `NSApp` is nil in a process that never launched an application — a CLI
    /// probe, a test bundle — and reading it there traps. Such a process has
    /// no menu bar to measure either, so the conventional 24 stands in.
    private static func menuBarHeight() -> CGFloat {
        NSApp?.mainMenu?.menuBarHeight ?? 24
    }
}
