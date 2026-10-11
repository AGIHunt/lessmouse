import Foundation
import SwiftUI
import Combine

/// Where the pipeline meets the UI. Keystrokes arrive here, get filtered,
/// counted, pattern-matched and coached; whatever the popover and the menu
/// bar need to show is published from here — one @MainActor object, no other
/// shared state.
@MainActor
public final class AppState: ObservableObject {
    // Inputs (injectable for tests).
    public let store: StatsStore
    public let settings: SettingsStore
    private let monitor: KeyEventSource
    private let permission: PermissionChecking
    private let detector: PatternDetector
    private let engine: SuggestionEngine
    private let menuTracker: MenuClickTracker

    // Published UI state.
    @Published public private(set) var permissionPhase: PermissionPhase = .needsPermission
    @Published public private(set) var isTracking = false
    @Published public private(set) var today = DaySnapshot(dayKey: "", combos: [:], patterns: [:])
    @Published public private(set) var suggestionStates: [String: SuggestionState] = [:]
    @Published public private(set) var unreadCount = 0
    /// Rule id of a just-adopted shortcut, for the celebration banner.
    @Published public private(set) var celebration: String?
    /// Fires once per transition worth a pop-up: a card arriving, a card
    /// adopted. Silent while the user has turned notices off in Settings.
    /// Main-actor only; subscribers present, they don't decide.
    public let notices = PassthroughSubject<CoachNotice, Never>()
    /// App activations today — the "behavior" ledger the ratio triggers read.
    @Published public private(set) var todayAppSwitches = 0
    /// Days of coarse activity signals the unused-while-active triggers read.
    @Published public private(set) var activityDays = ActivityDays()
    /// Every card the UI may show: the book, plus the menu coach's
    /// runtime-generated cards for the commands the user's own apps have
    /// revealed. Equal to the book alone while the coach is off.
    @Published public private(set) var rules: [SuggestionRule] = RuleLibrary.all
    /// Whether the menu coach can read menus right now. False with the coach
    /// on means "Accessibility was never granted" — the coach is dormant, and
    /// Settings offers the door to it.
    @Published public private(set) var isMenuCoachAvailable = false

    /// Browser-frontmost days and multi-app days, as one published fact.
    public struct ActivityDays: Equatable {
        public var browser = 0
        public var multiApp = 0
        public init() {}
    }

    public var language: String? { Loc.language }

    // Internals.
    private var cancellables: Set<AnyCancellable> = []
    private var permissionPoller: Timer?
    /// Watches for the Accessibility grant the menu coach needs, but only
    /// while the coach is on *and* missing it — the poller's whole job is to
    /// notice the user coming back from System Settings.
    private var menuCoachPoller: Timer?
    /// Checks every few seconds that the tap the app believes is running is
    /// still alive and still permitted — the system can switch it off (an
    /// Input Monitoring revoke, a disable it would not take back) without
    /// telling anyone. See `checkMonitorHealth()`.
    private var healthTimer: Timer?
    private var tapRetries = 0
    private var publishScheduled = false
    private var lastDayKey = ""
    /// Today's counts, kept incrementally for the event-driven adoption path
    /// (the store is authoritative for everything else).
    private var todayComboCounts: [String: Int] = [:]
    /// Publish debounce; 1s in production, ~0 in tests.
    private let publishDelay: TimeInterval

    /// The phase drives the popover's first screen: granted shows the
    /// overview, anything else shows the permission page.
    public enum PermissionPhase: Equatable {
        case granted
        case needsPermission
        case tapFailed(String)
    }

    public init(store: StatsStore? = nil,
                settings: SettingsStore? = nil,
                monitor: KeyEventSource? = nil,
                permission: PermissionChecking? = nil,
                detector: PatternDetector? = nil,
                engine: SuggestionEngine? = nil,
                menuTracker: MenuClickTracker? = nil,
                publishDelay: TimeInterval = 1) {
        let settings = settings ?? SettingsStore()
        self.store = store ?? StatsStore(
            directory: Self.defaultDirectory(),
            calendar: .current,
            now: Date.init)
        self.settings = settings
        self.permission = permission ?? PermissionGateway()
        let appContext = AppContextProvider()
        appContext.start()
        self.monitor = monitor ?? KeyboardMonitor(
            permission: self.permission,
            appContext: appContext)
        self.detector = detector ?? PatternDetector(specs: PatternLibrary.defaults)
        self.engine = engine ?? SuggestionEngine(
            rules: RuleLibrary.all,
            dynamicRuleFor: { MenuRuleFactory.rule(for: $0) })
        // The menu coach's half of the pipeline. Its accessibility reader is
        // the real one unless a test hands over a fake.
        self.menuTracker = menuTracker ?? MenuClickTracker(accessibility: AXMenuAccessibility())
        self.publishDelay = publishDelay

        // Wired after every stored property is set: the closure captures
        // self, which is only legal past that point.
        appContext.onActivation = { [weak self] bundleID in
            Task { @MainActor [weak self] in self?.noteAppActivation(bundleID) }
        }

        self.monitor.onEvent = { [weak self] event in
            // Dispatch directly to main queue without spawning a new Task per keystroke.
            DispatchQueue.main.async { [weak self] in self?.ingest(event) }
        }

        self.monitor.onMenuClick = { [weak self] click in
            DispatchQueue.main.async { [weak self] in self?.ingestMenuClick(click) }
        }

        // The keyboard-layout map the menu coach reads characters through
        // is built here, on the main thread, where the TIS API must run.
        KeyboardLayoutKeys.prepare()

        observeSettings()
        bootstrap()
        startHealthWatch()

        // Up to `flushInterval` of counts live only in memory; a sleep that
        // turns into a shutdown would lose them.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.store.flush() }
            .store(in: &cancellables)
    }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LessMouse", isDirectory: true)
    }

    // MARK: - Lifecycle

    /// Decide the initial tracking state: honour the pause switch, start the
    /// tap, and fall into the permission page when needed.
    private func bootstrap() {
        let snapshot = store.todaySnapshot()
        lastDayKey = snapshot.dayKey
        todayComboCounts = snapshot.combos
        suggestionStates = store.loadSuggestionStates()
        celebration = pendingCelebration()
        refreshRules()
        refreshUnreadCount()
        refreshMenuCoachAvailability()
        refreshToday()

        guard !settings.isPaused else {
            permissionPhase = .granted
            return
        }
        startMonitor()
    }

    /// - Parameter watchMouse: pass the coach's new value when called from a
    ///   settings sink — `@Published` notifies *before* storing, so reading
    ///   `settings.isMenuCoachEnabled` there still returns the old value.
    private func startMonitor(watchMouse: Bool? = nil) {
        // The tap only watches the mouse while the menu coach is on, so a
        // user who never wants it is watched for the keyboard alone.
        monitor.watchesMouse = watchMouse ?? settings.isMenuCoachEnabled
        let result = monitor.start()
        switch result {
        case .running:
            permissionPhase = .granted
            isTracking = true
            tapRetries = 0
            stopPermissionPolling()
        case .needsPermission:
            permissionPhase = .needsPermission
            isTracking = false
            startPermissionPolling()
        case .failed(let detail):
            permissionPhase = .tapFailed(detail)
            isTracking = false
        }
    }

    private func observeSettings() {
        settings.$isPaused
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] paused in
                guard let self else { return }
                if paused {
                    self.monitor.stop()
                    self.isTracking = false
                    self.detector.resetAll()
                    self.store.flush()
                } else {
                    self.startMonitor()
                }
            }
            .store(in: &cancellables)

        // Nothing is recorded for an excluded app, and bursts must not be
        // stitched across the exclusion boundary either.
        settings.$excludedApps
            .dropFirst()
            .sink { [weak self] _ in self?.detector.resetAll() }
            .store(in: &cancellables)

        // Turning the coach on or off changes what the tap watches, so the tap
        // is rebuilt — the same restart the pause switch already performs.
        settings.$isMenuCoachEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                // `enabled` is the new value; the property still holds the
                // old one until this sink returns.
                self.refreshMenuCoachAvailability(enabled: enabled)
                if !self.settings.isPaused { self.startMonitor(watchMouse: enabled) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Permission

    public func recheckPermission() {
        startMonitor()
    }

    public func openPermissionSettings() {
        permission.openSettings()
        permission.promptOnce()
    }

    /// Walk the user to the Accessibility pane — the permission the menu coach
    /// reads menus with.
    ///
    /// A door, not a knock: nothing is requested from here, so a user who
    /// never opens Settings is never asked about a permission the keyboard
    /// half of the app does not need.
    public func openAccessibilitySettings() {
        let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: accessibility) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Poll while ungranted; the user grants in System Settings, not here.
    private func startPermissionPolling() {
        stopPermissionPolling()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.permissionPhase == .needsPermission else { return }
                if self.permission.isGranted() {
                    self.startMonitor()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPoller = timer
    }

    private func stopPermissionPolling() {
        permissionPoller?.invalidate()
        permissionPoller = nil
    }

    private func startHealthWatch() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkMonitorHealth() }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    /// Recover from the states the tap can fall into without anyone saying so:
    ///
    /// - Input Monitoring revoked while running → stop, show the permission
    ///   page, and let the permission poller restart the tap on re-grant. (A
    ///   tap that lived through a revoke does not resume on re-grant; only a
    ///   fresh one records again.)
    /// - The system disabled or invalidated the tap and re-enabling did not
    ///   take → rebuild it.
    /// - The tap was refused despite the grant (macOS caches a refusal for a
    ///   while after the grant lands) → retry, quickly at first, then rarely.
    func checkMonitorHealth() {
        guard !settings.isPaused else { return }
        switch permissionPhase {
        case .granted:
            guard isTracking else { return }
            if !permission.isGranted() {
                monitor.stop()
                isTracking = false
                permissionPhase = .needsPermission
                startPermissionPolling()
            } else if !monitor.isAlive {
                startMonitor()
            }
        case .tapFailed:
            tapRetries += 1
            // ~every 2s for the first 10s, then every ~20s.
            if permission.isGranted(), tapRetries <= 5 || tapRetries % 10 == 0 {
                startMonitor()
            }
        case .needsPermission:
            break
        }
    }

    /// Re-read whether menus are readable, and keep watching only while they
    /// are not. Self-limiting: the moment the grant lands the timer stops.
    private func refreshMenuCoachAvailability(enabled: Bool? = nil) {
        // Off means off, all the way down: not even the trust check runs, so a
        // user who never turns the coach on is never asked about another app's
        // UI by anything LessMouse does.
        guard enabled ?? settings.isMenuCoachEnabled else {
            isMenuCoachAvailable = false
            stopMenuCoachPolling()
            return
        }
        isMenuCoachAvailable = menuTracker.canReadMenus
        let shouldPoll = !isMenuCoachAvailable
        if shouldPoll, menuCoachPoller == nil {
            let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.settings.isMenuCoachEnabled else {
                        self?.stopMenuCoachPolling()
                        return
                    }
                    self.refreshMenuCoachAvailability()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            menuCoachPoller = timer
        } else if !shouldPoll {
            stopMenuCoachPolling()
        }
    }

    private func stopMenuCoachPolling() {
        menuCoachPoller?.invalidate()
        menuCoachPoller = nil
    }

    // MARK: - Behavior signals

    /// An app came to the front. Counted even while "paused": app switching
    /// is not keyboard input, and the ⌘Tab card's argument is about the
    /// mouse, not the keys.
    public func noteAppActivation(_ bundleID: String?) {
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return }
        guard !settings.isExcluded(bundleID) else { return }
        store.recordAppActivation(bundleID)
        schedulePublish()
    }

    /// Coarse activity facts the engine and the card summaries read:
    /// how many days a browser was frontmost, how many days 2+ apps were.
    private func computeActivityDays() -> ActivityDays {
        let ownBundleID = Bundle.main.bundleIdentifier
        var days = ActivityDays()
        for day in store.daySummaries().values {
            let fronted = day.apps.filter { $0.value.activations > 0 }.map(\.key)
            if fronted.contains(where: BrowserCatalog.isBrowser) {
                days.browser += 1
            }
            if fronted.filter({ $0 != ownBundleID }).count >= 2 {
                days.multiApp += 1
            }
        }
        return days
    }

    // MARK: - The pipeline

    /// Single entry point for every keystroke — the tap calls it in
    /// production, tests call it directly.
    ///
    /// Order matters: the privacy filter runs before anything is kept, the
    /// adoption check runs on the fresh count (so coaching closes the loop
    /// within one keystroke), and the expensive bookkeeping is deferred to
    /// the throttled publish.
    public func ingest(_ event: KeyEvent) {
        guard !settings.isPaused, isTracking else { return }
        if settings.isExcluded(event.application) {
            detector.resetAll()
            lastEventApp = event.application
            return
        }
        guard let signature = KeySignatureFilter.signature(for: event) else { return }

        rollDayIfNeeded()

        // Bursts belong to one app at a time: switching frontmost apps ends
        // any window in progress.
        if event.application != lastEventApp {
            detector.resetAll()
            lastEventApp = event.application
        }

        let storageKey = signature.storageKey
        store.incrementCombo(storageKey, app: event.application)
        todayComboCounts[storageKey, default: 0] += 1

        // Adoption first — using the coached shortcut is the one event worth
        // reacting to instantly.
        if let adoptedRuleID = engine.onComboObserved(
            signature: storageKey,
            todayCount: todayComboCounts[storageKey] ?? 0,
            states: &suggestionStates) {
            // One banner at a time; a second adoption waits its turn rather
            // than overwrite the first (see `dismissCelebration`).
            if celebration == nil { celebration = adoptedRuleID }
            refreshUnreadCount()
            store.saveSuggestionStates(suggestionStates)
            notify(.adopted(ruleID: adoptedRuleID))
        }

        // Then pattern detection on the same stroke.
        let hits = detector.feed(signature: storageKey, at: event.timestamp)
        for hit in hits {
            store.recordPatternHit(hit.id, app: event.application)
        }

        schedulePublish()
    }

    private var lastEventApp: String?

    /// Single entry point for left mouse presses — the menu coach's half of
    /// the pipeline.
    ///
    /// Everything interesting happens inside the tracker: it decides whether
    /// the press chose a menu command. Reading a menu costs nothing at all for
    /// a click that was not in the menu bar, and the read itself happens off
    /// the main actor — this returns at once, and the signature comes back on
    /// the main actor when the app being read has answered.
    public func ingestMenuClick(_ click: MenuClick) {
        guard settings.isMenuCoachEnabled, !settings.isPaused, isTracking else { return }
        // Our own popover and our own menu bar hold nothing to coach.
        guard click.application != Bundle.main.bundleIdentifier,
              !settings.isExcluded(click.application) else { return }
        menuTracker.click(at: click.point, app: click.application, pid: click.pid) {
            [weak self] signature in
            guard let self, let signature else { return }
            self.rollDayIfNeeded()
            self.store.recordMenuCommand(signature, app: click.application)
            self.schedulePublish()
        }
    }

    /// UI publishes are throttled to one per second — a fast typist should
    /// not re-render the popover a dozen times a second it isn't looking at.
    private func schedulePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        let delay = publishDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.publishScheduled = false
            self.refreshToday()
        }
    }

    /// Day rollover: prune history, reset per-day machinery, re-derive the
    /// incremental counts. Runs on every stroke so the first key after
    /// midnight is judged against today's (empty) baseline rather than
    /// yesterday's — but only the key comparison is on the hot path; the
    /// flattened snapshot is taken once, when the day actually changed.
    private func rollDayIfNeeded() {
        let dayKey = store.todayKey()
        guard dayKey != lastDayKey else { return }
        lastDayKey = dayKey
        store.prune()
        todayComboCounts = store.todaySnapshot().combos
        detector.resetAll()
    }

    private func refreshToday() {
        rollDayIfNeeded()
        today = store.todaySnapshot()
        let activationSummary = store.todayActivationSummary()
        todayAppSwitches = activationSummary.total
        activityDays = computeActivityDays()
        evaluateSuggestions()
        store.flushIfDue()
    }

    /// The engine only ever sees a snapshot — no store access, no clock
    /// reads it can't be given, which is what makes it fully testable.
    private func evaluateSuggestions() {
        refreshRules()

        var allTime: [String: Int] = [:]
        for rule in rules {
            for signature in rule.watchForAdoption {
                allTime[signature] = store.comboCount(signature, dayLimit: nil)
            }
        }
        let context = EngineContext(
            dayKey: today.dayKey,
            patternHitsToday: today.patterns,
            comboCountsToday: today.combos,
            comboCountsAllTime: allTime,
            appSwitchesToday: todayAppSwitches,
            browserActiveDays: activityDays.browser,
            multiAppActiveDays: activityDays.multiApp,
            menuClicksToday: approvedMenuClicks())

        let changes = engine.evaluate(context, states: &suggestionStates)
        if !changes.isEmpty {
            refreshUnreadCount()
            store.saveSuggestionStates(suggestionStates)
        }
        for change in changes {
            switch change {
            case .becameUnread(let id), .promotedAgain(let id):
                notify(.newSuggestion(ruleID: id))
            case .adopted(let id):
                notify(.adopted(ruleID: id))
            }
        }
    }

    /// Today's menu clicks, limited to the signatures `refreshRules()` put on
    /// the shelf. The engine turns every key it is handed into a card, so
    /// handing it the raw counts let it mint cards the factory had refused —
    /// past the daily limit, under the keyboard-share bar, or with the coach
    /// switched off.
    private func approvedMenuClicks() -> [String: Int] {
        guard settings.isMenuCoachEnabled else { return [:] }
        let shelved = Set(rules.map(\.id)
            .filter { $0.hasPrefix(MenuRuleFactory.idPrefix) }
            .map { String($0.dropFirst(MenuRuleFactory.idPrefix.count)) })
        return today.menuCommands.filter { shelved.contains($0.key) }
    }

    private func notify(_ notice: CoachNotice) {
        guard settings.showsNotices else { return }
        notices.send(notice)
    }

    /// The newest adopted card whose celebration never ran — the banner is
    /// memory-only and `celebrated` flips only when it is dismissed, so an
    /// adoption followed by a quit would otherwise never be celebrated.
    private func pendingCelebration() -> String? {
        suggestionStates.values
            .filter { $0.status == .adopted && !$0.celebrated }
            .max { ($0.generatedAt ?? .distantPast) < ($1.generatedAt ?? .distantPast) }?
            .ruleID
    }

    /// The shelf the UI reads: the book, plus one card per menu command worth
    /// keeping there. A command qualifies either because it is being clicked
    /// today, or because the user already has a card for it — an adopted menu
    /// card must not disappear from the list (or from the stats) the day the
    /// habit ends.
    private func refreshRules() {
        var signatures = Set<String>()
        if settings.isMenuCoachEnabled {
            signatures.formUnion(MenuRuleFactory.candidates(
                menuClicks: today.menuCommands,
                keyboardUses: today.combos))
        }
        signatures.formUnion(suggestionStates.keys
            .filter { $0.hasPrefix(MenuRuleFactory.idPrefix) }
            .map { String($0.dropFirst(MenuRuleFactory.idPrefix.count)) })
        let next = RuleLibrary.all + MenuRuleFactory.rules(for: signatures.sorted())
        // Assigning an equal list still fires objectWillChange, and the
        // popover's hierarchy is alive (and re-evaluated) even while closed.
        if next.map(\.id) != rules.map(\.id) { rules = next }
    }

    /// The card a rule id names, whether it shipped with the book or was
    /// generated from a menu the user actually clicked.
    public func rule(withID id: String) -> SuggestionRule? {
        rules.first { $0.id == id }
    }

    private func refreshUnreadCount() {
        unreadCount = suggestionStates.values.count { $0.status == .unread }
    }

    // MARK: - User actions on cards

    public func markRead(_ ruleID: String) {
        engine.markRead(ruleID, states: &suggestionStates)
        refreshUnreadCount()
        store.saveSuggestionStates(suggestionStates)
    }

    public func dismiss(_ ruleID: String) {
        engine.dismiss(ruleID, states: &suggestionStates)
        refreshUnreadCount()
        store.saveSuggestionStates(suggestionStates)
    }

    public func dismissCelebration() {
        // Celebrated exactly once, ever, per rule.
        if let ruleID = celebration {
            suggestionStates[ruleID]?.celebrated = true
            store.saveSuggestionStates(suggestionStates)
        }
        celebration = pendingCelebration()
    }

    /// Settings' erase button: wipe the store and every derived piece of UI
    /// state, so the panel never shows numbers the disk no longer has.
    public func eraseAllData() {
        store.eraseAll()
        store.flush()
        suggestionStates = [:]
        todayComboCounts = [:]
        detector.resetAll()
        celebration = nil
        refreshToday()
        refreshUnreadCount()
    }

    // MARK: - Popover hooks

    public func popoverDidOpen() {
        refreshToday()
        // The one moment the user is most likely to have just granted
        // Accessibility, so this is where it is re-read.
        refreshMenuCoachAvailability()
    }

    public func popoverDidClose() {
        store.flush()
    }
}
