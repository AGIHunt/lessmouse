import Foundation
import AppKit
import Testing
@testable import LessMouseCore

/// The frontmost-app snapshot the tap thread reads.
///
/// The failure this file guards against is a silent one. The provider used to
/// observe `NSWorkspace.didActivateApplicationNotification` on
/// `NotificationCenter.default` — but workspace notifications are posted to
/// `NSWorkspace.shared.notificationCenter`, and the default center never
/// receives them. Nothing crashed, nothing logged; the provider simply went on
/// answering with whatever app was in front at launch, for the life of the
/// process. Measured: the default center receives nothing.
///
/// What that broke downstream: the menu coach read the *wrong* app's menus
/// through a stale pid, per-app stats and exclusions missed, and the
/// app-switch cards (⌘Tab, ⌃Tab, ⌘`) stopped moving at all.
@MainActor
@Suite(.serialized)
struct AppContextProviderTests {
    /// A real running application that is not this process, or nil on a
    /// machine with nothing else running.
    private var someOtherApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
    }

    /// The snapshot tracks activations rather than sticking to the app that
    /// was in front at launch. Two activations, because one proves the
    /// observer fires and two prove it keeps firing — the bug's symptom was a
    /// provider frozen on its first value, which a single delivery would not
    /// have caught.
    @Test func appActivationUpdatesTheFrontmostApp() async {
        let provider = AppContextProvider()
        provider.start()

        let first = NSRunningApplication.current
        let second = someOtherApp ?? first

        // Posted to the workspace's own center — the only center that receives
        // workspace notifications.
        NSWorkspace.shared.notificationCenter.post(activation(of: first))
        await until(provider.currentPID() == first.processIdentifier)

        #expect(provider.currentPID() == first.processIdentifier)
        #expect(provider.currentApp() == first.bundleIdentifier)

        NSWorkspace.shared.notificationCenter.post(activation(of: second))
        await until(provider.currentPID() == second.processIdentifier)

        #expect(provider.currentPID() == second.processIdentifier)
        #expect(provider.currentApp() == second.bundleIdentifier)
    }

    /// The behavior side of the ledger: every activation is announced, not
    /// only the ones that change the snapshot.
    @Test func everyActivationIsAnnounced() async {
        let provider = AppContextProvider()
        let seen = Locked<[String?]>([])
        provider.onActivation = { bundleID in seen.withValue { $0.append(bundleID) } }
        provider.start()

        let app = NSRunningApplication.current
        NSWorkspace.shared.notificationCenter.post(activation(of: app))
        await until(provider.currentPID() == app.processIdentifier)

        let announced: [String?] = seen.withValue { $0 }
        #expect(announced == [app.bundleIdentifier])
    }

    /// A notification that carries no application leaves the snapshot alone —
    /// an activation LessMouse cannot name is not an activation it should
    /// overwrite the last known app with.
    @Test func anActivationWithNoApplicationChangesNothing() async {
        let provider = AppContextProvider()
        provider.start()

        let app = NSRunningApplication.current
        NSWorkspace.shared.notificationCenter.post(activation(of: app))
        await until(provider.currentPID() == app.processIdentifier)

        NSWorkspace.shared.notificationCenter.post(Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: nil))

        #expect(provider.currentPID() == app.processIdentifier)
        #expect(provider.currentApp() == app.bundleIdentifier)
    }

    // MARK: - Helpers

    private func activation(of app: NSRunningApplication) -> Notification {
        Notification(name: NSWorkspace.didActivateApplicationNotification,
                     object: NSWorkspace.shared,
                     userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    /// Waits for the main queue to deliver. The observer is installed with
    /// `queue: .main`, so awaiting here lets the main thread go back to its run
    /// loop — which is what services the queue — without re-entering it.
    private func until(_ condition: @autoclosure @MainActor () -> Bool,
                       timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// A mutex-guarded box, because the notification block runs on the main queue
/// and the test body reads it from the main actor's continuation.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withValue<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
