import Foundation
import AppKit

/// Frontmost-app snapshots for the tap thread.
///
/// `NSWorkspace`'s frontmost-application property is main-thread API, but the
/// tap callback runs on its own thread and cannot go asking. So: observe the
/// activation notification on main, keep the bundle id under a lock, and hand
/// the tap a lock-guarded read that never touches AppKit.
///
/// The observer goes on `NSWorkspace.shared.notificationCenter`, which is
/// *not* `NotificationCenter.default`. Workspace notifications are posted to
/// the workspace's own center; the default center never receives them, and an
/// observer installed there simply never fires. Measured: with the observer on
/// the default center, the frontmost app stayed whatever was in front at
/// launch for the life of the process.
public protocol AppContextProviding: AnyObject {
    /// Thread-safe snapshot read; nil when no app is known yet.
    func currentApp() -> String?
    /// The frontmost app's process id — the handle the menu coach reads menus
    /// through. Nil until the first activation is seen.
    func currentPID() -> pid_t?
}

public final class AppContextProvider: AppContextProviding {
    private let lock = NSLock()
    private var cached: String?
    private var cachedPID: pid_t?

    /// Fires on every app activation (main thread via the notification
    /// queue) — the behavior side of the trigger math. LessMouse's own
    /// activations are passed through like any other app; callers filter
    /// if they care.
    public var onActivation: ((String?) -> Void)?

    private var observer: NSObjectProtocol?

    public init() {}

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Install the observer and prime the cache. Call once, from main.
    public func start() {
        update(NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.update(info.bundleIdentifier, pid: info.processIdentifier)
            self?.onActivation?(info.bundleIdentifier)
        }
    }

    private func update(_ bundleID: String?, pid: pid_t?) {
        lock.lock()
        cached = bundleID
        cachedPID = pid
        lock.unlock()
    }

    public func currentApp() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    public func currentPID() -> pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return cachedPID
    }
}
