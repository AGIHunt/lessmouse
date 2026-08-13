import Foundation
import ApplicationServices
import IOKit.hid
import AppKit

/// Asking macOS about the permission a listen-only event tap needs, and
/// walking the user to the right pane to grant it.
///
/// The permission a CGEventTap actually needs on modern macOS is **Input
/// Monitoring** — Accessibility alone stopped satisfying event taps. The
/// first version of this file checked `AXIsProcessTrusted() || IOHID…`, sent
/// the user to the Accessibility pane, and then reported "tap refused despite
/// permission" when the granted Accessibility didn't make the tap come up.
/// Input Monitoring is the gate; everything in this type now says so.
public protocol PermissionChecking: AnyObject {
    /// Whether a listen-only tap is expected to be allowed.
    func isGranted() -> Bool
    /// Trigger the system's own Input Monitoring prompt (no custom UI).
    func promptOnce()
    /// Deep-link System Settings to the Input Monitoring pane.
    func openSettings()
}

public final class PermissionGateway: PermissionChecking {
    public init() {}

    public func isGranted() -> Bool {
        // IOHIDCheckAccess is the same check the tap path goes through, so
        // "granted" here means the tap has a real chance of coming up.
        // Accessibility is deliberately NOT part of the answer: it can be
        // true while taps are still refused, which is exactly the state that
        // used to strand the app on "refused despite permission".
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    public func promptOnce() {
        // The system prompt for Input Monitoring, tied to this binary —
        // whatever the user answers becomes the IOHIDCheckAccess answer.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public func openSettings() {
        // The legacy pref-pane URL still resolves in modern System Settings.
        let inputMonitoring = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: inputMonitoring) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
