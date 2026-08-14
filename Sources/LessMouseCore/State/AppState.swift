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

    // Published UI state.
    @Published public private(set) var permissionPhase: PermissionPhase = .needsPermission
    @Published public private(set) var isTracking = false
    @Published public private(set) var today = DaySnapshot(dayKey: "", combos: [:], patterns: [:])
    @Published public private(set) var suggestionStates: [String: SuggestionState] = [:]
    @Published public private(set) var unreadCount = 0
    /// Rule id of a just-adopted shortcut, for the celebration banner.
    @Published public private(set) var celebration: String?
    /// App activations today — the "behavior" ledger the ratio triggers read.
    @Published public private(set) var todayAppSwitches = 0
    /// Days of coarse activity signals the unused-while-active triggers read.
    @Published public private(set) var activityDays = ActivityDays()

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
        self.engine = engine ?? SuggestionEngine(rules: RuleLibrary.all)
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

        observeSettings()
        bootstrap()
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
        refreshUnreadCount()
        refreshToday()

        guard !settings.isPaused else {
            permissionPhase = .granted
            return
        }
        startMonitor()
    }

    private func startMonitor() {
        let result = monitor.start()
        switch result {
        case .running:
            permissionPhase = .granted
            isTracking = true
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
    }

    // MARK: - Permission

    public func recheckPermission() {
        startMonitor()
    }

    public func openPermissionSettings() {
        permission.openSettings()
        permission.promptOnce()
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
            celebration = adoptedRuleID
            refreshUnreadCount()
            store.saveSuggestionStates(suggestionStates)
        }

        // Then pattern detection on the same stroke.
        let hits = detector.feed(signature: storageKey, at: event.timestamp)
        for hit in hits {
            store.recordPatternHit(hit.id, app: event.application)
        }

        schedulePublish()
    }

    private var lastEventApp: String?

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

    private func rollDayIfNeeded() {
        let snapshot = store.todaySnapshot()
        guard snapshot.dayKey != lastDayKey else { return }
        lastDayKey = snapshot.dayKey
        store.prune()
        todayComboCounts = snapshot.combos
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
        var allTime: [String: Int] = [:]
        for rule in RuleLibrary.all {
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
            multiAppActiveDays: activityDays.multiApp)

        let changes = engine.evaluate(context, states: &suggestionStates)
        if !changes.isEmpty {
            refreshUnreadCount()
            store.saveSuggestionStates(suggestionStates)
        }
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
        celebration = nil
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
    }

    public func popoverDidClose() {
        store.flush()
    }
}
