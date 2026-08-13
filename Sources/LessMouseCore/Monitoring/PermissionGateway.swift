import Foundation
import ApplicationServices
import IOKit.hid
import AppKit

/// Asking macOS about the permission a listen-only event tap needs, and
/// walking the user to the right pane to grant it.
///
/// The formal requirement is "Input Monitoring"; in practice the Accessibility
/// grant also satisfies the tap — so both are checked, both are offered, and
/// `KeyboardMonitor.start()` remains the final judge of whether the tap
/// actually came up.
public protocol PermissionChecking: AnyObject {
    func isGranted() -> Bool
    /// One system prompt, only when the user asked for it (never on launch).
    func promptOnce()
    /// Deep-link System Settings to the accessibility pane.
    func openSettings()
}

public final class PermissionGateway: PermissionChecking {
    public init() {}

    public func isGranted() -> Bool {
        if AXIsProcessTrusted() { return true }
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    public func promptOnce() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openSettings() {
        // The legacy pref-pane URL still resolves in modern System Settings;
        // if Apple ever drops it, the fallback opens the Privacy list itself.
        let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: accessibility) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
