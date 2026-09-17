import Foundation
import CoreGraphics
import Carbon.HIToolbox.Events

/// Listen-only event tap wrapped in its own thread.
///
/// This is the only file in the pipeline that touches CGEventTap, and it
/// stays deliberately thin: convert, hand over, get out. Every way this can
/// go wrong is a known, documented failure mode, handled here:
///
/// - **The callback must be a C function pointer** — no captures. Self
///   travels through `userInfo` as an unretained pointer (the monitor
///   outlives the tap because `stop()` tears the tap down before release).
/// - **The callback must never block.** The watchdog disables any tap whose
///   callback stalls (~0.25–1s), which kills tracking silently. So the
///   callback does three lock-free reads and returns; all real work happens
///   downstream, off this thread.
/// - **Timeout disable is recoverable**: the system re-enqueues a
///   `.tapDisabledByTimeout` event, we flip the tap back on and carry on.
/// - **The run loop must be the one the tap was created on** — hence a
///   dedicated thread that creates the tap and then runs its own loop.
/// - **`tapCreate` returning nil is a state, not a crash**: on a fresh
///   machine it simply means "not granted yet" (or, rarely, granted-but-
///   cached-refused — the UI's answer to that is "relaunch the app").
public final class KeyboardMonitor: KeyEventSource {
    public var onEvent: ((KeyEvent) -> Void)?

    private let permission: PermissionChecking
    private let appContext: AppContextProviding

    private let stateLock = NSLock()
    private var tap: CFMachPort?
    private var loopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var exitSemaphore: DispatchSemaphore?

    public init(permission: PermissionChecking, appContext: AppContextProviding) {
        self.permission = permission
        self.appContext = appContext
    }

    deinit {
        stop()
    }

    // MARK: - KeyEventSource

    public func start() -> TapStartResult {
        stop()

        // Handshake: the thread reports back what happened before it parks
        // in its run loop, so `start()` can answer synchronously.
        let boot = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let exitSem = DispatchSemaphore(value: 0)
        stateLock.lock()
        self.exitSemaphore = exitSem
        stateLock.unlock()

        let thread = Thread { [weak self] in
            defer { exitSem.signal() }
            guard let self else {
                box.store(.failed("monitor released during start"))
                boot.signal()
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: Self.tapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                let granted = self.permission.isGranted()
                box.store(granted
                          ? .failed("event tap was refused despite Input Monitoring — relaunch the app")
                          : .needsPermission)
                boot.signal()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            self.stateLock.lock()
            self.tap = tap
            self.loopSource = source
            self.runLoop = runLoop
            self.stateLock.unlock()

            box.store(.running)
            boot.signal()

            // Parks here until stop() calls CFRunLoopStop.
            CFRunLoopRun()

            // Teardown happens on this thread, where the tap lives.
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.stateLock.lock()
            self.tap = nil
            self.loopSource = nil
            self.runLoop = nil
            self.stateLock.unlock()
        }
        thread.name = "lm.eventtap"
        // Do NOT shrink this thread's stack. The system's tap dispatch chain
        // (SkyLight's eventTapMessageHandler and friends) runs on this stack
        // and needs far more than a minimal callback would suggest — a 16 KB
        // stack crashed with EXC_BAD_ACCESS "Thread stack size exceeded" on
        // the very first event after permission was granted. The default
        // half-megabyte is the only tested configuration.
        thread.start()
        self.thread = thread

        boot.wait()
        return box.load()
    }

    public func stop() {
        stateLock.lock()
        let runLoop = runLoop
        let tap = tap
        let exitSem = exitSemaphore
        stateLock.unlock()

        // Wait for the thread to finish its teardown, not just to be told to.
        // `start()` calls `stop()` first, and the old thread's cleanup nils
        // `tap` / `runLoop` — without the wait that could land after the new
        // thread has stored its own, leaving a live tap nobody can stop or
        // re-enable after a timeout. The bound is a safety net; teardown is
        // a few mach calls and normally completes in microseconds.
        if let runLoop {
            CFRunLoopStop(runLoop)
            _ = exitSem?.wait(timeout: .now() + 1.0)
        } else if let tap {
            // Started but never reached its loop — invalidate defensively.
            CFMachPortInvalidate(tap)
            _ = exitSem?.wait(timeout: .now() + 1.0)
        }

        stateLock.lock()
        self.thread = nil
        self.exitSemaphore = nil
        stateLock.unlock()
    }

    // MARK: - The C callback

    /// No captures: `userInfo` carries the monitor. Returning the event
    /// unchanged (listen-only) is also what passes it on to the system.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout {
            monitor.stateLock.lock()
            let tap = monitor.tap
            monitor.stateLock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              // A password sheet sets secure input system-wide; while it is
              // up, LessMouse observes nothing at all rather than
              // "everything except the characters". Checked here rather
              // than inside the normalizer so the conversion stays pure and
              // the tests stay deterministic on any machine.
              !IsSecureEventInputEnabled(),
              let keyEvent = CGEventNormalizer.keyEvent(
                from: event,
                timestamp: KeyboardMonitor.monotonicNow(),
                application: monitor.appContext.currentApp())
        else { return Unmanaged.passUnretained(event) }

        monitor.onEvent?(keyEvent)
        return Unmanaged.passUnretained(event)
    }

    /// Monotonic seconds — pattern windows measure elapsed time, and wall
    /// clocks jump (NTP, sleep). Uptime never does.
    private static func monotonicNow() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

/// Minimal synchronized box for the start handshake — an array of one, because
/// Swift closures can't capture `inout` state.
private final class ResultBox {
    private let lock = NSLock()
    private var result: TapStartResult = .failed("thread did not report")

    func store(_ result: TapStartResult) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> TapStartResult {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
