import LessMouseCore
import AppKit
import SwiftUI

/// Menu bar entry point. All logic lives in LessMouseCore so it stays unit
/// testable; this file only owns the Scene and the shared AppState instance.
@main
struct LessMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(state)
        } label: {
            // The product mark, plus an unread dot while there is a suggestion
            // waiting — "there is a faster shortcut for what you keep doing"
            // stays visible without opening anything.
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
        .menuBarExtraStyle(.window)
    }
}

/// SwiftPM builds a plain executable (no Info.plist we can set LSUIElement in),
/// so the Dock icon is suppressed at launch instead: this is a menu bar app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
