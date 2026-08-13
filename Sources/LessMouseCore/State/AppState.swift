import Foundation
import SwiftUI
import Combine

/// Where the pipeline meets the UI. The monitor's events arrive here, get
/// filtered and counted, and whatever the popover needs to show is published
/// from here — one @MainActor object, no other shared state.
@MainActor
public final class AppState: ObservableObject {
    // Inputs (injectable for tests).
    public let store: StatsStore
    public let settings: SettingsStore
    private let monitor: KeyEventSource
    private let permission: PermissionChecking

    // Published UI state.
    @Published public private(set) var permissionPhase: PermissionPhase = .needsPermission
    @Published public private(set) var isTracking = false
    @Published public private(set) var today = DaySnapshot(dayKey: "", combos: [:], patterns: [:])
    @Published public private(set) var unreadCount = 0
    /// Placeholder type until the suggestion model exists.
    @Published public private(set) var celebration: String?

    public var language: String? { Loc.language }

    // Internals.
    private var cancellables: Set<AnyCancellable> = []
    private var permissionPoller: Timer?
    private var publishScheduled = false
    private var lastDayKey = ""
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
        self.publishDelay = publishDelay

        self.monitor.onEvent = { [weak self] event in
            // The tap thread hands off immediately; everything downstream is
            // main-actor. Typing volume is tiny next to a main-queue drain.
            Task { @MainActor [weak self] in self?.ingest(event) }
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
        lastDayKey = store.todaySnapshot().dayKey
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
                    self.store.flush()
                } else {
                    self.startMonitor()
                }
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

    // MARK: - The pipeline

    /// Single entry point for every keystroke — the tap calls it in
    /// production, tests call it directly.
    public func ingest(_ event: KeyEvent) {
        guard !settings.isPaused, isTracking else { return }
        guard !settings.isExcluded(event.application) else { return }
        guard let signature = KeySignatureFilter.signature(for: event) else { return }

        store.incrementCombo(signature.storageKey, app: event.application)
        schedulePublish()
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

    private func refreshToday() {
        let snapshot = store.todaySnapshot()

        // Day rollover: prune history and reset any per-day machinery.
        if snapshot.dayKey != lastDayKey {
            lastDayKey = snapshot.dayKey
            store.prune()
        }
        today = snapshot
        store.flushIfDue()
    }

    // MARK: - Popover hooks

    public func popoverDidOpen() {
        refreshToday()
    }

    public func popoverDidClose() {
        store.flush()
    }
}
