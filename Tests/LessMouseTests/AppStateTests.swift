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
                            permission: StubPermission = StubPermission(),
                            store: StatsStore? = nil) -> (AppState, StubEventSource, StubPermission) {
        let suite = "lm-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(paused, forKey: "lm.paused")

        let store = store ?? StatsStore(
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

    /// Polls until `condition` holds, up to 2s. Fixed sleeps made these
    /// tests flaky when a parallel suite's snapshot rendering occupied the
    /// main actor past the sleep window — a condition wait cannot.
    private func waitUntil(
        _ condition: @autoclosure @MainActor () -> Bool,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
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
        await waitUntil(state.today.totalEvents == 3)

        #expect(state.today.totalEvents == 3)
        #expect(state.today.combos["backspace"] == 3)
    }

    @Test func pauseStopsRecordingEntirely() async {
        let (state, monitor, _) = makeState()

        state.settings.isPaused = true
        await waitUntil(monitor.stopCount == 1)
        #expect(monitor.stopCount == 1)
        #expect(state.isTracking == false)

        state.ingest(backspace(at: 1))
        await waitUntil(monitor.stopCount == 1)  // settle before asserting
        #expect(state.today.totalEvents == 0)

        state.settings.isPaused = false
        await waitUntil(monitor.startCount == 2)
        #expect(monitor.startCount == 2)
        #expect(state.isTracking)
    }

    @Test func excludedAppsAreNotCounted() async {
        let (state, _, _) = makeState()
        state.settings.excludedApps = ["com.apple.Terminal"]

        state.ingest(backspace(at: 1, app: "com.apple.Terminal"))
        state.ingest(backspace(at: 2, app: "com.apple.Safari"))
        await waitUntil(state.today.totalEvents == 1)

        #expect(state.today.totalEvents == 1)
    }

    @Test func excludedAppActivationsAreNotCounted() async {
        let (state, _, _) = makeState()
        state.settings.excludedApps = ["com.agilebits.onepassword7"]

        state.noteAppActivation("com.agilebits.onepassword7")
        state.noteAppActivation("com.apple.Safari")
        await waitUntil(state.todayAppSwitches == 1)

        #expect(state.todayAppSwitches == 1)
        #expect(state.activityDays.browser == 1)
    }

    @Test func burstsDoNotStitchAcrossAnExcludedApp() async {
        let (state, _, _) = makeState()
        state.settings.excludedApps = ["com.agilebits.onepassword7"]

        // Four backspaces in Terminal — one short of a burst.
        for j in 0..<4 {
            state.ingest(backspace(at: Double(j) * 0.2, app: "com.apple.Terminal"))
        }
        // The excluded app is a hard boundary, even though its keys are dropped.
        state.ingest(backspace(at: 0.9, app: "com.agilebits.onepassword7"))
        // Back in Terminal: a fifth press must start a new window, not fire.
        state.ingest(backspace(at: 1.1, app: "com.apple.Terminal"))
        await waitUntil(state.today.totalEvents == 5)

        #expect(state.today.patterns["backspace-burst"] == nil
                || state.today.patterns["backspace-burst"] == 0)
    }

    @Test func typedTextNeverReachesTheStore() async {
        let (state, _, _) = makeState()
        // Bare "e" and shift+"e" are text; the pipeline drops them before
        // counting, at the same filter the tap path uses.
        state.ingest(KeyEvent(timestamp: 1, keyCode: 0x0E, modifiers: [], application: nil))
        state.ingest(KeyEvent(timestamp: 2, keyCode: 0x0E, modifiers: .shift, application: nil))
        state.ingest(KeyEvent(timestamp: 3, keyCode: 0x08, modifiers: .command, application: nil))
        await waitUntil(state.today.totalEvents == 1)

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

    // MARK: - Behavior signals

    @Test func appActivationsFeedTheBehaviorLedger() async {
        let (state, _, _) = makeState()
        state.noteAppActivation("com.apple.Safari")
        state.noteAppActivation("com.google.Chrome")
        state.noteAppActivation("com.apple.Safari")
        await waitUntil(state.todayAppSwitches == 3)

        #expect(state.todayAppSwitches == 3)
        #expect(state.activityDays.browser == 1,
                "a browser was frontmost today, so today counts as a browser day")
        #expect(state.activityDays.multiApp == 1,
                "two distinct apps were frontmost today")
    }

    // MARK: - End to end: burst → card → adoption

    @Test func fiveBackspacesProduceAnUnreadCard() async {
        let (state, _, _) = makeState()
        for i in 0..<3 {
            // Three separate bursts of five, each well inside its own window.
            for j in 0..<5 {
                state.ingest(backspace(at: Double(i) * 10 + Double(j) * 0.2))
            }
            await waitUntil(state.today.totalPatterns >= (i + 1))
        }

        #expect(state.today.totalPatterns >= 3)
        #expect(state.unreadCount == 1)
        #expect(state.suggestionStates["delete-by-word"]?.status == .unread)
    }

    /// Three bursts of five — enough to cross the rule's 3-bursts-a-day line.
    private func triggerDeleteByWordCard(_ state: AppState) async {
        for i in 0..<3 {
            for j in 0..<5 {
                state.ingest(backspace(at: Double(i) * 10 + Double(j) * 0.2))
            }
            await waitUntil(state.today.totalPatterns >= (i + 1))
        }
    }

    @Test func usingTheCoachedShortcutCelebratesOnce() async {
        let (state, _, _) = makeState()
        await triggerDeleteByWordCard(state)
        await waitUntil(state.unreadCount == 1)
        #expect(state.unreadCount == 1)

        state.markRead("delete-by-word")

        // The user takes the coaching: ⌥⌫ (0x33 with ⌥ held).
        state.ingest(KeyEvent(timestamp: 10, keyCode: 0x33, modifiers: .option,
                              application: "com.apple.Terminal"))
        #expect(state.celebration == "delete-by-word")
        #expect(state.suggestionStates["delete-by-word"]?.status == .adopted)

        // Second use is just good habits — no second party.
        state.dismissCelebration()
        state.ingest(KeyEvent(timestamp: 11, keyCode: 0x33, modifiers: .option,
                              application: "com.apple.Terminal"))
        #expect(state.celebration == nil)
    }

    @Test func dismissSilencesACardForGood() async {
        let (state, _, _) = makeState()
        await triggerDeleteByWordCard(state)
        await waitUntil(state.unreadCount == 1)

        state.dismiss("delete-by-word")
        #expect(state.unreadCount == 0)

        // More bursts the same day: the card stays down.
        for i in 0..<5 {
            for j in 0..<5 {
                state.ingest(backspace(at: 100 + Double(i) * 10 + Double(j) * 0.2))
            }
        }
        await waitUntil(state.today.totalPatterns >= 8)
        #expect(state.unreadCount == 0)
        #expect(state.suggestionStates["delete-by-word"]?.status == .dismissed)
    }

    @Test func dayRollDoesNotCarryYesterdaysCounts() async {
        // Without a roll, yesterday's 4 + today's 1 would look like
        // "crossed the baseline" and celebrate by mistake.
        final class Clock: @unchecked Sendable {
            var date = Date(timeIntervalSince1970: 1_800_000_000)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let clock = Clock()
        let store = StatsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("lm-tests-\(UUID().uuidString)"),
            calendar: calendar,
            now: { clock.date })

        let (state, _, _) = makeState(store: store)

        for _ in 0..<4 {
            state.ingest(KeyEvent(timestamp: 1, keyCode: 0x33, modifiers: .option,
                                  application: "com.apple.Terminal"))
        }
        await triggerDeleteByWordCard(state)
        await waitUntil(state.unreadCount == 1)

        clock.date = clock.date.addingTimeInterval(86_400 + 3_600)
        state.ingest(KeyEvent(timestamp: 50, keyCode: 0x33, modifiers: .option,
                              application: "com.apple.Terminal"))
        #expect(state.celebration == nil)
    }
}
