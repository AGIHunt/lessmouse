import Foundation
import CoreGraphics
import Carbon.HIToolbox.Events

/// CGEvent → KeyEvent → KeySignature. The only file where a real `CGEvent`
/// is touched; everything past `keyEvent(from:)` is pure and testable.
///
/// The tap layer (KeyboardMonitor) calls `keyEvent(from:)` and hands the
/// result to the pipeline; the pipeline calls
/// `KeySignatureFilter.signature(for:)` which is where the privacy rules
/// live. Splitting it this way keeps the filter free of any framework
/// import, so the privacy regression tests exercise exactly the production
/// code path and nothing incidental.
public enum CGEventNormalizer {
    /// Convert a raw event, or nil if it must not become a KeyEvent at all.
    ///
    /// Nil for: secure input active (a password field has focus — the system
    /// already filters tapped events there, this is the second lock on the
    /// door), and events carrying no keycode we can name.
    public static func keyEvent(from event: CGEvent,
                                timestamp: TimeInterval,
                                application: String?) -> KeyEvent? {
        // A password sheet sets secure input process-wide; while it is up,
        // LessMouse observes nothing at all rather than "everything except
        // the characters".
        if IsSecureEventInputEnabled() { return nil }

        guard event.type == .keyDown else { return nil }

        // Keep only the four meaning-bearing modifiers; alphaShift (caps lock
        // state), fn and numeric-pad flags ride along on ordinary keystrokes
        // and would fork one shortcut into several signatures.
        var modifiers: ModifierSet = []
        let flags = event.flags
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }

        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        return KeyEvent(timestamp: timestamp,
                        keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                        modifiers: modifiers,
                        isAutorepeat: autorepeat,
                        application: application)
    }
}
