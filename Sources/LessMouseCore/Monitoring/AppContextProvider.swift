import Foundation
import AppKit

/// Frontmost-app snapshots for the tap thread.
///
/// `NSWorkspace`'s frontmost-application property is main-thread API, but the
/// tap callback runs on its own thread and cannot go asking. So: observe the
/// activation notification on main, keep the bundle id under a lock, and hand
/// the tap a lock-guarded read that never touches AppKit.
public protocol AppContextProviding: AnyObject {
    /// Thread-safe snapshot read; nil when no app is known yet.
    func currentApp() -> String?
}

public final class AppContextProvider: AppContextProviding {
    private let lock = NSLock()
    private var cached: String?

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
        }
    }

    /// Install the observer and prime the cache. Call once, from main.
    public func start() {
        cached = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.update(info.bundleIdentifier)
            self?.onActivation?(info.bundleIdentifier)
        }
    }

    private func update(_ bundleID: String?) {
        lock.lock()
        cached = bundleID
        lock.unlock()
    }

    public func currentApp() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }
}
