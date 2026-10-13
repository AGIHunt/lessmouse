import Foundation
import Testing
@testable import LessMouseCore

/// The menu coach's back half: the cards generated from what the user's own
/// menus revealed, the trigger that wakes them, the counts that feed them, and
/// the whole loop from a mouse click to a celebration.
@MainActor
@Suite(.serialized)
struct MenuSuggestionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func context(dayKey: String = "2027-01-15",
                         combos: [String: Int] = [:],
                         menuClicks: [String: Int] = [:]) -> EngineContext {
        EngineContext(dayKey: dayKey,
                      comboCountsToday: combos,
                      menuClicksToday: menuClicks)
    }

    /// An engine with an empty book: the only card that can fire is one the
    /// menu coach generates.
    private func engine() -> SuggestionEngine {
        SuggestionEngine(rules: [],
                         dynamicRuleFor: { MenuRuleFactory.rule(for: $0) },
                         calendar: calendar,
                         now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    // MARK: - Which commands get a card

    @Test func candidatesAreMostClickedFirstAndCapped() {
        let clicks = ["cmd+s": 9, "cmd+shift+p": 4, "cmd+w": 4, "cmd+n": 2, "cmd+z": 1]
        let picked = MenuRuleFactory.candidates(menuClicks: clicks)

        #expect(picked.count == MenuRuleFactory.limit)
        #expect(picked.first == "cmd+s")
        // Ties break on the signature, so the shelf never reshuffles between
        // evaluations of the same day.
        #expect(picked.dropFirst().prefix(2) == ["cmd+shift+p", "cmd+w"])
        #expect(!picked.contains("cmd+z"), "one click is someone exploring a menu")
    }

    @Test func aShortcutAlreadyInUseIsNotCoached() {
        // Three clicks, two of them covered by the keyboard: knows the way.
        #expect(MenuRuleFactory.candidates(
            menuClicks: ["cmd+s": 3], keyboardUses: ["cmd+s": 2]).isEmpty)

        // One keyboard use out of three is still mostly a mouse habit.
        #expect(MenuRuleFactory.candidates(
            menuClicks: ["cmd+s": 3], keyboardUses: ["cmd+s": 1]) == ["cmd+s"])
    }

    @Test func anUndrawableShortcutGetsNoCard() {
        // ⌘ with an unmapped keycode: there is no keycap to show, so there is
        // nothing to teach.
        #expect(MenuRuleFactory.candidates(menuClicks: ["cmd+k103": 9]).isEmpty)
        #expect(MenuRuleFactory.rule(for: "cmd+k103") == nil)
    }

    @Test func aGestureTheKeyboardHalfWouldNeverRecordGetsNoCard() {
        // What an earlier build wrote into stats.json: a menu shortcut that
        // carried no ⌘/⌥/⌃ — the fn (🌐) family, whose globe key never reaches
        // accessibility, and menus that print a bare shifted letter. The
        // keyboard half never counts those, so no card can be adopted by
        // pressing them, and a bare letter is typing this app does not keep.
        #expect(MenuRuleFactory.candidates(menuClicks: ["f": 9]).isEmpty)
        #expect(MenuRuleFactory.candidates(menuClicks: ["a": 9]).isEmpty)
        #expect(MenuRuleFactory.candidates(menuClicks: ["shift+a": 9]).isEmpty)
        #expect(MenuRuleFactory.candidates(menuClicks: ["shift+f": 9]).isEmpty)
        #expect(MenuRuleFactory.rule(for: "f") == nil)
        #expect(MenuRuleFactory.rule(for: "a") == nil)
        #expect(MenuRuleFactory.rule(for: "shift+a") == nil)

        // The same counts under a shortcut that *is* a command still get one:
        // the filter is on the modifiers, not on the key.
        #expect(MenuRuleFactory.candidates(menuClicks: ["cmd+f": 9]) == ["cmd+f"])
        #expect(MenuRuleFactory.candidates(menuClicks: ["ctrl+c": 9]) == ["ctrl+c"])
        #expect(MenuRuleFactory.candidates(menuClicks: ["esc": 9]) == ["esc"])
    }

    @Test func theCardsIDIsStableSoItsStateSurvivesRelaunches() {
        let rule = MenuRuleFactory.rule(for: "cmd+s")
        #expect(rule?.id == "menu-click:cmd+s")
        #expect(MenuRuleFactory.rule(for: "cmd+s")?.id == rule?.id)
        #expect(MenuRuleFactory.idPrefix == "menu-click:")
        #expect(rule?.watchForAdoption == ["cmd+s"])
        #expect(rule?.symbol == "cursorarrow.click")
        #expect(rule?.keyCaps == [[.modifier(.command), .key("S")]])
        #expect(rule?.primaryShortcutLabel == "⌘S")
    }

    @Test func everyCardNamesTheSameGenericStrings() {
        // The copy is one card's worth, not one per command: the shortcut
        // itself is the argument the summary formats in.
        let rule = MenuRuleFactory.rule(for: "opt+shift+left")
        #expect(rule?.titleKey == "rule.menuClick.title")
        #expect(rule?.bodyKey == "rule.menuClick.body")
        #expect(rule?.summaryKey == "rule.menuClick.summary")
    }

    // MARK: - The trigger

    @Test func threeMouseClicksWakeTheCard() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        #expect(engine.evaluate(context(menuClicks: ["cmd+s": 2]), states: &states).isEmpty)

        var changes = engine.evaluate(context(menuClicks: ["cmd+s": 3]), states: &states)
        #expect(changes == [.becameUnread("menu-click:cmd+s")])
        #expect(states["menu-click:cmd+s"]?.status == .unread)

        // Already unread: re-triggering refreshes nothing visible.
        changes = engine.evaluate(context(menuClicks: ["cmd+s": 9]), states: &states)
        #expect(changes.isEmpty)
        #expect(states["menu-click:cmd+s"]?.status == .unread)
    }

    @Test func theKeyboardHalfOfTheSameSignatureHoldsTheCardDown() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        let changes = engine.evaluate(
            context(combos: ["cmd+s": 2], menuClicks: ["cmd+s": 3]),
            states: &states)
        #expect(changes.isEmpty,
                "someone pressing ⌘S for two of three Saves is already there")
    }

    @Test func aMenuClickFeedsNoOtherCard() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]

        // Mouse clicks are a currency of their own: a day of menu clicking
        // with no keystrokes at all wakes nothing from the book.
        let changes = engine.evaluate(context(menuClicks: ["cmd+s": 40]), states: &states)
        #expect(changes == [.becameUnread("menu-click:cmd+s")])
    }

    // MARK: - Adoption

    @Test func pressingTheTaughtShortcutAdoptsTheMenuCard() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        _ = engine.evaluate(context(menuClicks: ["cmd+s": 4]), states: &states)

        // The baseline is the keyboard half at generation time — zero here.
        #expect(states["menu-click:cmd+s"]?.adoptionBaseline["cmd+s"] == 0)

        let adopted = engine.onComboObserved(signature: "cmd+s", todayCount: 1, states: &states)
        #expect(adopted == "menu-click:cmd+s")
        #expect(states["menu-click:cmd+s"]?.status == .adopted)
    }

    @Test func aCardThatWasAlreadyAdoptedDoesNotCelebrateAgain() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        _ = engine.evaluate(context(menuClicks: ["cmd+s": 4]), states: &states)
        _ = engine.onComboObserved(signature: "cmd+s", todayCount: 1, states: &states)

        let again = engine.onComboObserved(signature: "cmd+s", todayCount: 2, states: &states)
        #expect(again == nil)
    }

    @Test func dismissingAMenuCardIsForever() {
        let engine = engine()
        var states: [String: SuggestionState] = [:]
        _ = engine.evaluate(context(menuClicks: ["cmd+s": 4]), states: &states)
        engine.dismiss("menu-click:cmd+s", states: &states)

        let changes = engine.evaluate(context(dayKey: "2027-02-01",
                                             menuClicks: ["cmd+s": 30]),
                                      states: &states)
        #expect(changes.isEmpty)
        #expect(states["menu-click:cmd+s"]?.status == .dismissed)
    }
}

/// The counts behind the cards: what the store keeps, and for how long.
@Suite(.serialized)
struct MenuCommandStoreTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
        func advance(days: Int) { date = date.addingTimeInterval(Double(days) * 86_400) }
    }

    private func makeStore(_ clock: Clock) -> StatsStore {
        StatsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("lm-tests-\(UUID().uuidString)"),
            calendar: calendar,
            now: { clock.date })
    }

    @Test func menuClicksCountBySignatureAndByDay() {
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(clock)

        store.recordMenuCommand("cmd+s", app: "com.apple.TextEdit")
        store.recordMenuCommand("cmd+s", app: "com.apple.TextEdit")
        store.recordMenuCommand("cmd+shift+o", app: "com.apple.TextEdit")
        store.flush()

        let today = store.todaySnapshot()
        #expect(today.menuCommands["cmd+s"] == 2)
        #expect(today.menuCommands["cmd+shift+o"] == 1)
        #expect(today.totalMenuCommands == 3)
        #expect(store.menuCommandCount("cmd+s") == 3 - 1)
        #expect(store.menuCommandCount("cmd+shift+o") == 1)
        #expect(store.daysObserved() == 1)

        // Yesterday's clicks are history, not today's.
        clock.advance(days: 1)
        store.recordMenuCommand("cmd+s", app: "com.apple.TextEdit")
        store.flush()
        #expect(store.todaySnapshot().totalMenuCommands == 1)
        #expect(store.menuCommandCount("cmd+s", dayLimit: nil) == 3)
        #expect(store.menuCommandCount("cmd+s", dayLimit: 1) == 1)
    }

    @Test func menuClicksAndKeystrokesStaySeparateCurrencies() {
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(clock)

        store.incrementCombo("cmd+s", app: nil)
        store.recordMenuCommand("cmd+s", app: nil)
        store.flush()

        // Same signature, two halves: one press, one click.
        #expect(store.comboCount("cmd+s") == 1)
        #expect(store.menuCommandCount("cmd+s") == 1)
        #expect(store.todaySnapshot().totalEvents == 1)
        #expect(store.todaySnapshot().totalMenuCommands == 1)
    }

    @Test func oldFilesWithoutMenuCommandsStillDecode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lm-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A file from before the coach existed: no "menuCommands" anywhere.
        let legacy = """
        {"version":1,"days":{"2027-01-15":{"apps":{"com.apple.Terminal":
        {"combos":{"cmd+c":2},"patterns":{},"activations":1}}}}}
        """
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("stats.json"))

        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = StatsStore(directory: directory, calendar: calendar, now: { clock.date })

        #expect(store.comboCount("cmd+c") == 2)
        #expect(store.menuCommandCount("cmd+s") == 0)
        #expect(store.todaySnapshot().totalMenuCommands == 0)
        #expect(store.daysObserved() == 1,
                "a day of keystrokes is still an observed day")
    }

    @Test func aDayOfOnlyMenuClicksStillCountsAsObserved() {
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(clock)

        store.recordMenuCommand("cmd+s", app: "com.apple.TextEdit")
        store.flush()
        #expect(store.daysObserved() == 1)
    }
}

/// The whole loop, with everything outside the menu fake stubbed: mouse clicks
/// go in one end, a card and a celebration come out the other.
@MainActor
@Suite(.serialized)
struct MenuCoachPipelineTests {
    private let strip = CGRect(x: 0, y: 0, width: 1200, height: 24)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A clock the test can wind forward, so a "next day" is a line away.
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
        func advance(days: Int) { date = date.addingTimeInterval(Double(days) * 86_400) }
    }

    private final class StubEventSource: KeyEventSource, @unchecked Sendable {
        var onEvent: ((KeyEvent) -> Void)?
        func start() -> TapStartResult { .running }
        func stop() {}
    }

    private final class StubPermission: PermissionChecking, @unchecked Sendable {
        func isGranted() -> Bool { true }
        func promptOnce() {}
        func openSettings() {}
    }

    /// A menu bar with one command that prints ⌘S.
    private final class FakeMenus: MenuAccessibilityReading, @unchecked Sendable {
        var isAvailable: Bool { true }
        func menuBarItems(pid: pid_t) -> [MenuItemSnapshot]? {
            let save = MenuItemSnapshot(
                frame: CGRect(x: 8, y: 24, width: 140, height: 22),
                shortcut: MenuShortcut(signature: "cmd+s"))
            return [MenuItemSnapshot(frame: CGRect(x: 8, y: 0, width: 40, height: 24),
                                     shortcut: nil,
                                     openMenu: { [save] })]
        }
    }

    private func makeState(_ settings: SettingsStore,
                           store: StatsStore,
                           menus: MenuAccessibilityReading = FakeMenus()) -> AppState {
        let tracker = MenuClickTracker(accessibility: menus,
                                       menuBarStrip: { CGRect(x: 0, y: 0, width: 1200, height: 24) })
        return AppState(store: store,
                        settings: settings,
                        monitor: StubEventSource(),
                        permission: StubPermission(),
                        menuTracker: tracker,
                        publishDelay: 0.01)
    }

    private func settingsDomain() -> (UserDefaults, String) {
        let suite = "lm-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    /// Settings with the coach switched on. Off by default, so a test that
    /// exercises the mouse half says so rather than leaning on a default —
    /// the default itself is pinned by its own test below.
    private func coachOn(_ defaults: UserDefaults) -> SettingsStore {
        let settings = SettingsStore(defaults: defaults)
        settings.isMenuCoachEnabled = true
        return settings
    }

    private func makeStore() -> StatsStore {
        StatsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("lm-tests-\(UUID().uuidString)"),
            calendar: .current,
            now: Date.init)
    }

    private func makeStore(_ clock: Clock) -> StatsStore {
        StatsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("lm-tests-\(UUID().uuidString)"),
            calendar: calendar,
            now: { clock.date })
    }

    /// Menu clicks are resolved off the main actor, so how long that takes
    /// depends on the machine; a fixed sleep that fits a laptop is too short
    /// on a CI runner. Wait for the outcome instead, with a generous cap.
    private func waitUntil(_ condition: @autoclosure @MainActor () -> Bool,
                           timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// One "opened the File menu, picked Save" gesture.
    private func clickSave(_ state: AppState, app: String? = "com.apple.TextEdit") {
        state.ingestMenuClick(MenuClick(point: CGPoint(x: 20, y: 10), application: app, pid: 42))
        state.ingestMenuClick(MenuClick(point: CGPoint(x: 60, y: 30), application: app, pid: 42))
    }

    @Test func threeMenuClicksMakeACardAndTheShortcutAdoptsIt() async {
        let (defaults, _) = settingsDomain()
        let state = makeState(coachOn(defaults), store: makeStore())
        #expect(state.isMenuCoachAvailable, "the fake menus answer, so the coach is live")

        // Two gestures: not yet a habit.
        clickSave(state); clickSave(state)
        await waitUntil(state.today.totalMenuCommands == 2)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(state.unreadCount == 0)

        // The third is.
        clickSave(state)
        await waitUntil(state.unreadCount == 1)

        let cardID = MenuRuleFactory.id(for: "cmd+s")
        #expect(state.unreadCount == 1)
        #expect(state.suggestionStates[cardID]?.status == .unread)
        #expect(state.today.totalMenuCommands == 3)
        // The card is on the shelf the UI reads, and resolves by id.
        #expect(state.rules.contains { $0.id == cardID })
        #expect(state.rule(withID: cardID)?.primaryShortcutLabel == "⌘S")

        // Pressing the shortcut it taught celebrates it — the same keystroke
        // path the rest of the book uses.
        state.ingest(KeyEvent(timestamp: 1, keyCode: 0x01, modifiers: .command,
                              application: "com.apple.TextEdit"))
        #expect(state.celebration == cardID)
        #expect(state.suggestionStates[cardID]?.status == .adopted)
    }

    @Test func anAdoptedCardKeepsItsPlaceAfterTheHabitEnds() async throws {
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = makeStore(clock)
        let (defaults, _) = settingsDomain()
        let state = makeState(coachOn(defaults), store: store)

        clickSave(state); clickSave(state); clickSave(state)
        let cardID = MenuRuleFactory.id(for: "cmd+s")
        await waitUntil(state.suggestionStates[cardID]?.status == .unread)
        #expect(state.suggestionStates[cardID]?.status == .unread)

        state.ingest(KeyEvent(timestamp: 1, keyCode: 0x01, modifiers: .command,
                              application: "com.apple.TextEdit"))
        #expect(state.suggestionStates[cardID]?.status == .adopted)

        // The next day the user opens no menus at all. The card is no longer
        // *triggered*, but it is not deleted from under someone who already
        // took it up — that is what keeps the stats page's denominator stable.
        clock.advance(days: 1)
        state.popoverDidOpen()
        #expect(state.today.totalMenuCommands == 0)
        #expect(state.rule(withID: cardID) != nil)
        #expect(state.rules.contains { $0.id == cardID })
    }

    @Test func erasingRemovesTheMenuCardAlongWithItsState() async {
        let (defaults, _) = settingsDomain()
        let state = makeState(coachOn(defaults), store: makeStore())
        clickSave(state); clickSave(state); clickSave(state)
        await waitUntil(state.rules.contains { $0.id == MenuRuleFactory.id(for: "cmd+s") })
        #expect(state.rules.contains { $0.id == MenuRuleFactory.id(for: "cmd+s") })

        state.eraseAllData()
        #expect(state.rules.count == RuleLibrary.all.count,
                "with no menu history the shelf is the book alone")
    }

    @Test func pausedRecordsNoMenuClicks() async {
        let (defaults, _) = settingsDomain()
        let settings = SettingsStore(defaults: defaults)
        let state = makeState(settings, store: makeStore())

        settings.isPaused = true
        try? await Task.sleep(for: .milliseconds(50))
        clickSave(state); clickSave(state); clickSave(state)
        try? await Task.sleep(for: .milliseconds(120))

        #expect(state.today.totalMenuCommands == 0)
        #expect(state.unreadCount == 0)
    }

    @Test func anExcludedAppIsNeverCoached() async {
        let (defaults, _) = settingsDomain()
        let settings = SettingsStore(defaults: defaults)
        settings.excludedApps = ["com.apple.TextEdit"]
        let state = makeState(settings, store: makeStore())

        clickSave(state); clickSave(state); clickSave(state)
        try? await Task.sleep(for: .milliseconds(120))

        #expect(state.today.totalMenuCommands == 0)
        #expect(state.unreadCount == 0)
    }

    /// Off until the user turns it on. A default that watches every mouse
    /// press in the system asks every user to decline a feature they never
    /// asked for — and a user who never granted Accessibility is watched for
    /// nothing at all, which is most of them.
    @Test func theCoachIsOffUntilTheUserTurnsItOn() async {
        let (defaults, _) = settingsDomain()
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.isMenuCoachEnabled == false)

        let state = makeState(settings, store: makeStore())
        // Off means off, all the way down: not even the trust check runs.
        #expect(state.isMenuCoachAvailable == false)
        clickSave(state); clickSave(state); clickSave(state)
        try? await Task.sleep(for: .milliseconds(120))

        #expect(state.today.totalMenuCommands == 0)
        #expect(state.unreadCount == 0)

        // And the tap is not watching the mouse either — see the mask tests
        // in MenuCoachTests.
    }

    @Test func turningTheCoachOffStopsTheClicks() async {
        let (defaults, _) = settingsDomain()
        let settings = SettingsStore(defaults: defaults)
        let state = makeState(settings, store: makeStore())

        settings.isMenuCoachEnabled = false
        try? await Task.sleep(for: .milliseconds(50))
        clickSave(state); clickSave(state); clickSave(state)
        try? await Task.sleep(for: .milliseconds(120))

        #expect(state.today.totalMenuCommands == 0)
        #expect(state.unreadCount == 0)

        // Turning it back on picks the habit up again from the next click.
        settings.isMenuCoachEnabled = true
        try? await Task.sleep(for: .milliseconds(50))
        clickSave(state); clickSave(state); clickSave(state)
        await waitUntil(state.today.totalMenuCommands == 3 && state.unreadCount == 1)
        #expect(state.today.totalMenuCommands == 3)
        #expect(state.unreadCount == 1)
    }
}
