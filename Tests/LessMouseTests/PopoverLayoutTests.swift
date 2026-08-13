import AppKit
import SwiftUI
import Testing
@testable import LessMouseCore

/// Layout regression tests for the popover.
///
/// These exist because a `MenuBarExtra(.window)` sizes its window to the
/// content's *ideal* height, and a ScrollView has none — a structural change
/// can collapse the body while every unit test stays green. So these render
/// the real views off-screen and assert on their size. `LM_SNAPSHOT_DIR`
/// additionally writes PNGs for human review.
@MainActor
@Suite(.serialized)
struct PopoverLayoutTests {
    // Same stubs as AppStateTests, kept local so each suite reads standalone.
    final class StubEventSource: KeyEventSource, @unchecked Sendable {
        var onEvent: ((KeyEvent) -> Void)?
        func start() -> TapStartResult { .running }
        func stop() {}
    }

    final class StubPermission: PermissionChecking, @unchecked Sendable {
        var granted = true
        func isGranted() -> Bool { granted }
        func promptOnce() {}
        func openSettings() {}
    }

    private func makeState() -> AppState {
        let suite = "lm-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = StatsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("lm-tests-\(UUID().uuidString)"),
            calendar: .current,
            now: Date.init)
        return AppState(store: store,
                        settings: SettingsStore(defaults: defaults),
                        monitor: StubEventSource(),
                        permission: StubPermission(),
                        publishDelay: 0.01)
    }

    /// A state with something to show: counts, one unread card.
    private func populatedState() async -> AppState {
        let state = makeState()
        // Three bursts of five backspaces → the delete-by-word card.
        for i in 0..<3 {
            for j in 0..<5 {
                state.ingest(KeyEvent(timestamp: Double(i) * 10 + Double(j) * 0.2,
                                      keyCode: 0x33, modifiers: [],
                                      application: "com.apple.Terminal"))
            }
        }
        // A few real combos for the stats page.
        for _ in 0..<7 { state.ingest(KeyEvent(timestamp: 50, keyCode: 0x08, modifiers: .command, application: nil)) }
        for _ in 0..<3 { state.ingest(KeyEvent(timestamp: 60, keyCode: 0x33, modifiers: .option, application: nil)) }
        try? await Task.sleep(for: .milliseconds(120))
        return state
    }

    private func render(_ view: some View, name: String) -> CGSize {
        let sized = view.frame(width: Metrics.popoverWidth)
        SnapshotWriter.write(sized, width: Metrics.popoverWidth, name: name)
        let renderer = ImageRenderer(content: sized)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return .zero }
        return image.size
    }

    @Test func populatedPopoverRendersItsSections() async {
        let state = await populatedState()
        #expect(state.unreadCount == 1)

        let size = render(MainView(openSuggestion: { _ in }).environmentObject(state),
                          name: "main-populated")
        #expect(size.width == Metrics.popoverWidth)
        // The content column alone (no popover chrome): three ledger rows,
        // an inbox title and a card row. Well above the ~60pt a collapsed
        // body produces, below whatever chrome adds.
        #expect(size.height > 200,
                "main page rendered \(size.height)pt tall — the body has collapsed")
    }

    @Test func emptyStateStillRendersAUsablePanel() async {
        let state = makeState()
        let size = render(MainView(openSuggestion: { _ in }).environmentObject(state),
                          name: "main-empty")
        #expect(size.height > 150, "empty main rendered \(size.height)pt tall")
    }

    @Test func permissionPageRenders() {
        let state = makeState()
        // Force the permission branch without a real permission check.
        let monitor = StubEventSource()
        _ = monitor
        let size = render(PermissionView().environmentObject(state), name: "permission")
        #expect(size.height > 140, "permission page rendered \(size.height)pt tall")
    }

    @Test func everySubPageDrawsSomething() async {
        let state = await populatedState()
        let cases: [(String, AnyView)] = [
            ("page-detail", AnyView(SuggestionDetailView(ruleID: "delete-by-word", onBack: {})
                .environmentObject(state))),
            ("page-stats", AnyView(StatsPageView(onBack: {}).environmentObject(state))),
            ("page-settings", AnyView(SettingsView(onBack: {}).environmentObject(state))),
            ("banner-celebration", AnyView(CelebrationBanner(ruleID: "hop-by-word")
                .environmentObject(state))),
            ("header-tracking", AnyView(TrackingHeader().environmentObject(state))),
        ]
        for (name, view) in cases {
            let size = render(view, name: name)
            #expect(size.height > 40, "\(name) rendered \(size.height)pt tall — it draws nothing")
        }
    }

    @Test func keycapsRenderAtCapSize() {
        let row = KeyCapRow(caps: [.modifier(.option), .key("⌫")])
            .padding(10)
        let size = render(row, name: "keycap-row")
        // Two caps side by side: wider than tall, taller than one cap alone.
        #expect(size.height >= 22 && size.width > 44,
                "keycap row rendered \(size.width)x\(size.height)")
    }

    /// The formatter the ledger depends on: storage keys must survive the
    /// round trip to glyphs and back to *something readable*.
    @Test func signatureDisplayForms() {
        #expect(Fmt.signatureDisplay("cmd+c") == "⌘C")
        #expect(Fmt.signatureDisplay("cmd+shift+right") == "⇧⌘→")
        #expect(Fmt.signatureDisplay("opt+backspace") == "⌥⌫")
        #expect(Fmt.signatureDisplay("ctrl+a") == "⌃A")
        #expect(Fmt.signatureDisplay("backspace") == "⌫")
        #expect(Fmt.signatureDisplay("cmd+grave") == "⌘`")
    }

    @Test func compactCounts() {
        #expect(Fmt.compactCount(9) == "9")
        #expect(Fmt.compactCount(999) == "999")
        #expect(Fmt.compactCount(1_204) == "1.2k")
        #expect(Fmt.compactCount(25_000) == "25k")
    }
}
