import Foundation

/// What the pipeline sees of the keyboard. The protocol exists so tests can
/// push synthetic events into AppState without an event tap (or a permission
/// prompt) anywhere in sight.
public protocol KeyEventSource: AnyObject {
    /// Fired on the tap's private thread — implementations must hop to main
    /// (or elsewhere) themselves.
    var onEvent: ((KeyEvent) -> Void)? { get set }

    /// Left mouse presses, for the menu coach. Fired on the tap's thread, like
    /// `onEvent`; only ever delivered while `watchesMouse` is on.
    var onMenuClick: ((MenuClick) -> Void)? { get set }

    /// Whether the tap also watches the mouse. Off by default so a source that
    /// knows nothing about the coach (every test double) behaves exactly like
    /// a keyboard-only monitor — and so a user who never wants the coach is
    /// watched for the keyboard alone.
    var watchesMouse: Bool { get set }

    /// Begin observing. `.needsPermission` is a normal outcome on a fresh
    /// machine, not an error — the UI turns it into the permission page.
    /// Still delivering? See the extension for the default.
    var isAlive: Bool { get }

    func start() -> TapStartResult

    /// Stop observing and tear the tap down completely. "Paused" means
    /// *nothing is watched at all*, not "watched but not recorded".
    func stop()
}

/// Defaults that keep a keyboard-only implementation of `KeyEventSource`
/// complete. The real monitor overrides both.
extension KeyEventSource {
    /// Whether the running source is still delivering — false once the
    /// system has disabled or invalidated it. Sources that cannot tell (test
    /// stubs) answer true.
    public var isAlive: Bool { true }

    public var onMenuClick: ((MenuClick) -> Void)? {
        get { nil }
        set { }
    }

    public var watchesMouse: Bool {
        get { false }
        set { }
    }
}

public enum TapStartResult: Equatable {
    case running
    case needsPermission
    case failed(String)
}
