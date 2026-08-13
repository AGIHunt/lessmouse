import Foundation
import Testing
@testable import LessMouseCore

/// AppState pipeline behaviour with every dependency stubbed: no event tap,
/// no permission prompt, isolated defaults, throwaway store.
@MainActor
@Suite(.serialized)
struct AppStateTests {
    // MARK: - Stubs

    final class StubEventSource: KeyEventSource, @unchecked Sendable {
        var onEvent: ((KeyEvent) -> Void)?
        private let lock = NSLock()
        private var _startCount = 0
        private var _stopCount = 0
        var result: TapStartResult = .running

        var startCount: Int { lock.withLock { _startCount } }
        var stopCount: Int { lock.withLock { _stopCount } }

        func start() -> TapStartResult {
            lock.withLock { _startCount += 1 }
            return result
        }

        func stop() {
            lock.withLock { _stopCount += 1 }
        }
    }

    final class StubPermission: PermissionChecking, @unchecked Sendable {
        var granted = true
        private(set) var promptCount = 0
        private(set) var settingsOpened = 0

        func isGranted() -> Bool { granted }
        func promptOnce() { promptCount += 1 }
        func openSettings() { settingsOpened += 1 }
    }

    // MARK: - Fixtures

    private func makeState(paused: Bool = false,
                            monitor: StubEventSource = StubEventSource(),
                            permission: StubPermission = StubPermission()) -> (AppState, StubEventSource, StubPermission) {
        let suite = "lm-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(paused, forKey: "lm.paused")

        let store = StatsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("lm-tests-\(UUID().uuidString)"),
            calendar: .current,
            now: Date.init)
        let state = AppState(store: store,
                             settings: SettingsStore(defaults: defaults),
                             monitor: monitor,
                             permission: permission,
                             publishDelay: 0.01)
        return (state, monitor, permission)
    }

    private func backspace(at t: TimeInterval, app: String? = "com.apple.Terminal") -> KeyEvent {
        // kVK_Delete = 0x33, verified against Carbon.HIToolbox.
        KeyEvent(timestamp: t, keyCode: 0x33, modifiers: [], application: app)
    }

    private func waitOneTick() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    // MARK: - Pipeline

    @Test func grantedTapTracksAndCounts() async {
        let (state, monitor, _) = makeState()
        #expect(state.permissionPhase == .granted)
        #expect(state.isTracking)
        #expect(monitor.startCount == 1)

        state.ingest(backspace(at: 1))
        state.ingest(backspace(at: 2))
        state.ingest(backspace(at: 3))
        await waitOneTick()

        #expect(state.today.totalEvents == 3)
        #expect(state.today.combos["backspace"] == 3)
    }

    @Test func pauseStopsRecordingEntirely() async {
        let (state, monitor, _) = makeState()

        state.settings.isPaused = true
        await waitOneTick()
        #expect(monitor.stopCount == 1)
        #expect(state.isTracking == false)

        state.ingest(backspace(at: 1))
        await waitOneTick()
        #expect(state.today.totalEvents == 0)

        state.settings.isPaused = false
        await waitOneTick()
        #expect(monitor.startCount == 2)
        #expect(state.isTracking)
    }

    @Test func excludedAppsAreNotCounted() async {
        let (state, _, _) = makeState()
        state.settings.excludedApps = ["com.apple.Terminal"]

        state.ingest(backspace(at: 1, app: "com.apple.Terminal"))
        state.ingest(backspace(at: 2, app: "com.apple.Safari"))
        await waitOneTick()

        #expect(state.today.totalEvents == 1)
    }

    @Test func typedTextNeverReachesTheStore() async {
        let (state, _, _) = makeState()
        // Bare "e" and shift+"e" are text; the pipeline drops them before
        // counting, at the same filter the tap path uses.
        state.ingest(KeyEvent(timestamp: 1, keyCode: 0x0E, modifiers: [], application: nil))
        state.ingest(KeyEvent(timestamp: 2, keyCode: 0x0E, modifiers: .shift, application: nil))
        state.ingest(KeyEvent(timestamp: 3, keyCode: 0x08, modifiers: .command, application: nil))
        await waitOneTick()

        #expect(state.today.totalEvents == 1)
        #expect(state.today.combos["cmd+c"] == 1)
    }

    // MARK: - Permission flow

    @Test func deniedTapShowsPermissionPage() async {
        let monitor = StubEventSource()
        monitor.result = .needsPermission
        let (state, _, permission) = makeState(monitor: monitor)

        #expect(state.permissionPhase == .needsPermission)
        #expect(state.isTracking == false)

        // Granting and rechecking brings the tap up.
        monitor.result = .running
        permission.granted = true
        state.recheckPermission()
        #expect(state.permissionPhase == .granted)
        #expect(state.isTracking)
    }

    @Test func tapFailureSurfacesItsDetail() async {
        let monitor = StubEventSource()
        monitor.result = .failed("boom")
        let (state, _, _) = makeState(monitor: monitor)

        #expect(state.permissionPhase == .tapFailed("boom"))
        #expect(state.isTracking == false)
    }

    @Test func openPermissionSettingsPromptsOnceAndLinks() {
        let (state, _, permission) = makeState(monitor: StubEventSource(), permission: StubPermission())
        state.openPermissionSettings()
        #expect(permission.promptCount == 1)
        #expect(permission.settingsOpened == 1)
    }
}
