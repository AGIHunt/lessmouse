import LessMouseCore
import AppKit
import SwiftUI

/// Menu bar entry point. All logic lives in LessMouseCore so it stays unit
/// testable; this file only owns the Scene and the shared AppState instance.
@main
struct LessMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(delegate.state)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The product mark, plus an unread dot while there is a suggestion waiting —
/// "there is a faster shortcut for what you keep doing" stays visible without
/// opening anything.
private struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let mark = ProductMark.menuBar {
            Image(nsImage: mark)
                .overlay(alignment: .topTrailing) {
                    if state.unreadCount > 0 || state.celebration != nil {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -1)
                    }
                }
        } else {
            Image(systemName: state.isTracking ? "keyboard" : "keyboard.badge.ellipsis")
        }
    }
}

/// Owns the one AppState and the notice presenter. The state lives here rather
/// than in a `@StateObject` because the presenter must exist from launch, not
/// from the first time the popover's content is built.
///
/// SwiftPM builds a plain executable (no Info.plist we can set LSUIElement in),
/// so the Dock icon is suppressed at launch instead: this is a menu bar app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var presenter: NoticePresenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        presenter = NoticePresenter(state: state)
    }

    /// Counts are flushed on a 30s debounce; quitting must not drop the tail.
    func applicationWillTerminate(_ notification: Notification) {
        state.store.flush()
    }
}
