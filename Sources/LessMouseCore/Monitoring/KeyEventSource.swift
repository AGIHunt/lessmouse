import Foundation

/// What the pipeline sees of the keyboard. The protocol exists so tests can
/// push synthetic events into AppState without an event tap (or a permission
/// prompt) anywhere in sight.
public protocol KeyEventSource: AnyObject {
    /// Fired on the tap's private thread — implementations must hop to main
    /// (or elsewhere) themselves.
    var onEvent: ((KeyEvent) -> Void)? { get set }

    /// Begin observing. `.needsPermission` is a normal outcome on a fresh
    /// machine, not an error — the UI turns it into the permission page.
    func start() -> TapStartResult

    /// Stop observing and tear the tap down completely. "Paused" means
    /// *nothing is watched at all*, not "watched but not recorded".
    func stop()
}

public enum TapStartResult: Equatable {
    case running
    case needsPermission
    case failed(String)
}
