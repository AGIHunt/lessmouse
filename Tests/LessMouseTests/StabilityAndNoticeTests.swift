import Foundation
import Combine
import CoreGraphics
import Testing
@testable import LessMouseCore

/// Regression tests for the stability pass after real-machine use, and for
/// the pop-up notices. Each test names the failure it pins down.
@MainActor
@Suite(.serialized)
struct StabilityAndNoticeTests {

    // MARK: - Fakes

    final class Tap: KeyEventSource, @unchecked Sendable {
        var onEvent: ((KeyEvent) -> Void)?
        var result: TapStartResult = .running
        var alive = true
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var mouseAtLastStart: Bool?
        private var mouse = false

        var watchesMouse: Bool {
            get { mouse }
            set { mouse = newValue }
        }
        var isAlive: Bool { alive }

        func start() -> TapStartResult {
            startCount += 1
            mouseAtLastStart = mouse
            return result
        }
        func stop() { stopCount += 1 }
    }

    final class Permission: PermissionChecking, @unchecked Sendable {
        var granted = true
        func isGranted() -> Bool { granted }
        func promptOnce() {}
        func openSettings() {}
    }

    private func defaults(_ configure: (UserDefaults) -> Void = { _ in }) -> UserDefaults {
        let suite = "lm-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        configure(defaults)
        return defaults
    }

    private func storeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lm-tests-\(UUID().uuidString)")
    }

    private func makeState(defaults: UserDefaults? = nil,
                           directory: URL? = nil,
                           tap: Tap = Tap(),
                           permission: Permission = Permission()) -> AppState {
        AppState(store: StatsStore(directory: directory ?? storeDirectory(),
                                   calendar: .current, now: Date.init),
                 settings: SettingsStore(defaults: defaults ?? self.defaults()),
                 monitor: tap,
                 permission: permission,
                 publishDelay: 0.01)
    }

    private func waitUntil(_ condition: @autoclosure @MainActor () -> Bool,
                           timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Three bursts of five backspaces: the delete-by-word card turns unread.
    private func triggerDeleteByWord(_ state: AppState) async {
        for i in 0..<3 {
            for j in 0..<5 {
                state.ingest(KeyEvent(timestamp: Double(i) * 10 + Double(j) * 0.2,
                                      keyCode: 0x33, modifiers: [], application: "com.apple.Terminal"))
            }
            await waitUntil(state.today.totalPatterns >= i + 1)
        }
        await waitUntil(state.unreadCount == 1)
    }

    private func pressOptionBackspace(_ state: AppState, at t: TimeInterval = 100) {
        state.ingest(KeyEvent(timestamp: t, keyCode: 0x33, modifiers: .option,
                              application: "com.apple.Terminal"))
    }

    // MARK: - Notices

    @Test func aNewCardAndItsAdoptionEachFireOneNotice() async {
        let state = makeState()
        var received: [CoachNotice] = []
        let sub = state.notices.sink { received.append($0) }
        defer { sub.cancel() }

        await triggerDeleteByWord(state)
        #expect(received == [.newSuggestion(ruleID: "delete-by-word")])

        pressOptionBackspace(state)
        #expect(received == [.newSuggestion(ruleID: "delete-by-word"),
                             .adopted(ruleID: "delete-by-word")])

        // Using it again is a habit, not news.
        pressOptionBackspace(state, at: 101)
        #expect(received.count == 2)
    }

    @Test func noticesStayQuietWhenTurnedOff() async {
        let state = makeState(defaults: defaults { $0.set(false, forKey: "lm.notices") })
        #expect(state.settings.showsNotices == false)
        var received: [CoachNotice] = []
        let sub = state.notices.sink { received.append($0) }
        defer { sub.cancel() }

        await triggerDeleteByWord(state)
        pressOptionBackspace(state)
        #expect(received.isEmpty)
    }

    @Test func noticesDefaultOn() {
        #expect(SettingsStore(defaults: defaults()).showsNotices)
    }

    @Test func noticeContentResolvesForBookAndMenuCards() {
        let state = makeState()
        let book = NoticeContent.make(for: .newSuggestion(ruleID: "delete-by-word"), state: state)
        #expect(book?.kind == .newSuggestion)
        #expect(book?.caps.isEmpty == false)
        let adopted = NoticeContent.make(for: .adopted(ruleID: "delete-by-word"), state: state)
        #expect(adopted?.kind == .adopted)
        #expect(adopted?.title.contains("⌥⌫") == true)
        #expect(NoticeContent.make(for: .newSuggestion(ruleID: "no-such-card"), state: state) == nil)
    }

    // MARK: - Celebrations are never lost

    @Test func anAdoptionCelebratesAfterARelaunch() async {
        let directory = storeDirectory()
        let settings = defaults()
        let first = makeState(defaults: settings, directory: directory)
        await triggerDeleteByWord(first)
        pressOptionBackspace(first)
        #expect(first.celebration == "delete-by-word")
        first.store.flush()

        // Quit before dismissing the banner, then relaunch.
        let second = makeState(defaults: settings, directory: directory)
        #expect(second.celebration == "delete-by-word")
        second.dismissCelebration()
        #expect(second.celebration == nil)

        let third = makeState(defaults: settings, directory: directory)
        #expect(third.celebration == nil, "celebrated once, ever")
    }

    // MARK: - Settings sinks see the new value

    @Test func turningTheCoachOnAtRuntimeReachesTheTap() async {
        let tap = Tap()
        let state = makeState(tap: tap)
        #expect(tap.mouseAtLastStart == false)

        state.settings.isMenuCoachEnabled = true
        await waitUntil(tap.startCount == 2)
        #expect(tap.mouseAtLastStart == true,
                "the tap must be rebuilt watching the mouse — the sink used to read the old value")

        state.settings.isMenuCoachEnabled = false
        await waitUntil(tap.startCount == 3)
        #expect(tap.mouseAtLastStart == false)
    }

    // MARK: - The tap recovers on its own

    @Test func aRevokedPermissionStopsTheTapAndAReGrantRestartsIt() async {
        let tap = Tap()
        let permission = Permission()
        let state = makeState(tap: tap, permission: permission)
        #expect(state.isTracking)

        permission.granted = false
        state.checkMonitorHealth()
        #expect(state.permissionPhase == .needsPermission)
        #expect(state.isTracking == false)
        #expect(tap.stopCount >= 1)

        // Re-granted: the permission poller builds a fresh tap.
        permission.granted = true
        await waitUntil(state.permissionPhase == .granted)
        #expect(state.permissionPhase == .granted)
        #expect(state.isTracking)
        #expect(tap.startCount == 2)
    }

    @Test func aTapTheSystemDisabledIsRebuilt() {
        let tap = Tap()
        let state = makeState(tap: tap)
        tap.alive = false
        state.checkMonitorHealth()
        #expect(tap.startCount == 2)
        tap.alive = true
        state.checkMonitorHealth()
        #expect(tap.startCount == 2, "a healthy tap is left alone")
    }

    @Test func aRefusedTapIsRetriedOnceTheSystemLetsGo() {
        let tap = Tap()
        tap.result = .failed("refused")
        let state = makeState(tap: tap)
        #expect(state.permissionPhase == .tapFailed("refused"))

        tap.result = .running
        state.checkMonitorHealth()
        #expect(state.permissionPhase == .granted)
        #expect(state.isTracking)
    }

    @Test func pausedMeansTheWatchdogLeavesTheTapAlone() async {
        let tap = Tap()
        let state = makeState(tap: tap)
        state.settings.isPaused = true
        await waitUntil(state.isTracking == false)
        tap.alive = false
        let starts = tap.startCount
        state.checkMonitorHealth()
        #expect(tap.startCount == starts)
    }
}

// MARK: - Menu reading

@Suite struct MenuReadingHardeningTests {

    private final class Menus: MenuAccessibilityReading, @unchecked Sendable {
        let items: [MenuItemSnapshot]
        init(_ items: [MenuItemSnapshot]) { self.items = items }
        var isAvailable: Bool { true }
        func menuBarItems(pid: pid_t) -> [MenuItemSnapshot]? { items }
    }

    /// A bar the way a secondary display above the main one reports it:
    /// negative y in global top-left coordinates.
    private func secondaryDisplayBar() -> [MenuItemSnapshot] {
        let save = MenuItemSnapshot(frame: CGRect(x: 30, y: -1050, width: 160, height: 22),
                                    shortcut: MenuShortcut(signature: "cmd+shift+b"))
        return [MenuItemSnapshot(frame: CGRect(x: 30, y: -1080, width: 47, height: 30),
                                 shortcut: nil, openMenu: { [save] })]
    }

    @Test func aMenuBarOnASecondaryDisplayIsAMenuBar() async {
        let main = CGRect(x: 0, y: 0, width: 1496, height: 28)
        let secondary = CGRect(x: -84, y: -1080, width: 1920, height: 30)
        let tracker = MenuClickTracker(accessibility: Menus(secondaryDisplayBar()),
                                       menuBarStrips: { [main, secondary] })
        #expect(await tracker.click(at: CGPoint(x: 50, y: -1065), app: "com.google.Chrome", pid: 7) == nil)
        #expect(await tracker.click(at: CGPoint(x: 60, y: -1040), app: "com.google.Chrome", pid: 7)
                == "cmd+shift+b")
    }

    @Test func onlyTheMainDisplayStripMissesIt() async {
        // What the app did before: the secondary bar is not "the menu bar".
        let tracker = MenuClickTracker(accessibility: Menus(secondaryDisplayBar()),
                                       menuBarStrip: { CGRect(x: 0, y: 0, width: 1496, height: 28) })
        _ = await tracker.click(at: CGPoint(x: 50, y: -1065), app: "com.google.Chrome", pid: 7)
        #expect(await tracker.click(at: CGPoint(x: 60, y: -1040), app: "com.google.Chrome", pid: 7) == nil)
    }

    @Test func aClickThatWaitedTooLongIsDropped() async {
        // Each reading of the clock is 2s later than the last: by the time the
        // reader gets to a click, it is older than the 1.5s limit.
        final class Clock: @unchecked Sendable { var t: TimeInterval = 0 }
        let clock = Clock()
        let main = CGRect(x: 0, y: 0, width: 1496, height: 28)
        let bar = [MenuItemSnapshot(frame: CGRect(x: 8, y: 0, width: 40, height: 24), shortcut: nil,
                                    openMenu: { [MenuItemSnapshot(frame: CGRect(x: 8, y: 24, width: 140, height: 22),
                                                                  shortcut: MenuShortcut(signature: "cmd+s"))] })]
        let tracker = MenuClickTracker(accessibility: Menus(bar), menuBarStrips: { [main] },
                                       now: { clock.t += 2; return Date(timeIntervalSince1970: clock.t) })
        _ = await tracker.click(at: CGPoint(x: 20, y: 10), app: "a", pid: 1)
        #expect(await tracker.click(at: CGPoint(x: 60, y: 30), app: "a", pid: 1) == nil)
    }

    @Test func anotherAppsOutOfRangeNumbersDecodeToNothingRatherThanTrap() {
        #expect(AXMenuAccessibility.shortcut(fromKeyCode: -1, character: nil, modifierMask: 0) == nil)
        #expect(AXMenuAccessibility.shortcut(fromKeyCode: 70_000, character: nil, modifierMask: 0) == nil)
        #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: -1))
        #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: (1 << 32) | 1))
        #expect(AXMenuAccessibility.carriesAnUnverifiableModifier(mask: 16), "fn/globe")
        #expect(!AXMenuAccessibility.carriesAnUnverifiableModifier(mask: 0b1111))
        #expect(AXMenuAccessibility.shortcut(fromKeyCode: nil, character: "C", modifierMask: 28) == nil,
                "🌐⌃C is not taught as ⌃C")
    }

    @Test func theLayoutMapIsReadableFromABackgroundQueue() async {
        // The reader queue looks characters up; the map must be built on main
        // and merely read here — this used to call TIS off the main thread.
        let answer = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: KeyboardLayoutKeys.key(forCharacter: "S") != nil)
            }
        }
        #expect(answer)
    }
}

// MARK: - Every format string is safe in every language

@Suite struct LocalizedFormatTests {

    /// Conversion types of a format string, by argument position.
    private func types(_ format: String) -> [Int: Character]? {
        let pattern = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(?:l{0,2}|h{0,2}|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSp])")
        var result: [Int: Character] = [:]
        var next = 1
        let ns = format as NSString
        for match in pattern.matches(in: format, range: NSRange(location: 0, length: ns.length)) {
            let positional = match.range(at: 1).location != NSNotFound
                ? Int(ns.substring(with: match.range(at: 1))) : nil
            let raw = Character(ns.substring(with: match.range(at: 2)))
            let kind: Character = "dDiuUxXoOcC".contains(raw) ? "i" : ("fFeEgG".contains(raw) ? "f" : "@")
            let index = positional ?? next
            if let existing = result[index], existing != kind { return nil }
            result[index] = kind
            next = index + 1
        }
        return result
    }

    private func table(_ language: String) throws -> [String: String] {
        let bundle = try #require(Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)))
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// The crash this guards against: zh "%ld 次 %@" against code passing
    /// (String, Int) — `%@` dereferenced an Int and the inbox took the app down.
    @Test func everyTranslationTakesTheSameArgumentsAsEnglish() throws {
        let en = try table("en")
        let zh = try table("zh-Hans")
        var mismatches: [String] = []
        for (key, english) in en {
            guard let chinese = zh[key] else { continue }
            if types(english) != types(chinese) { mismatches.append(key) }
        }
        #expect(mismatches.isEmpty, "argument types differ by language: \(mismatches.sorted())")
        #expect(Set(en.keys) == Set(zh.keys), "both languages carry the same keys")
    }
}
