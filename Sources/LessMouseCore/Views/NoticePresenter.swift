import AppKit
import Combine
import SwiftUI

/// Shows `AppState.notices` as a toast just under the menu bar icon.
///
/// A borderless, non-activating panel: it never takes focus from what the
/// user is doing, never needs a permission (unlike Notification Center), and
/// points at the icon the user would click next. One toast at a time; a burst
/// of arrivals (say, the day's first evaluation turning three cards unread)
/// is queued and shown in turn rather than stacked. Clicking a toast opens
/// the popover.
@MainActor
public final class NoticePresenter {
    private let state: AppState
    private var subscription: AnyCancellable?
    private var queue: [NoticeContent] = []
    private var panel: NSPanel?
    private var model: NoticeToastModel?
    private var dismissWork: DispatchWorkItem?
    private var isShowing = false

    /// Visible time before the toast leaves on its own.
    static let newSuggestionDuration: TimeInterval = 4.5
    static let adoptedDuration: TimeInterval = 5
    /// Arrivals beyond this wait for the next evaluation rather than pile up.
    static let maxQueued = 3

    public init(state: AppState) {
        self.state = state
        subscription = state.notices
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in self?.enqueue(notice) }
    }

    // MARK: - Queue

    private func enqueue(_ notice: CoachNotice) {
        guard let content = NoticeContent.make(for: notice, state: state) else { return }
        // An adoption outranks pending arrivals: it is the answer to them.
        if content.kind == .adopted {
            queue.insert(content, at: 0)
        } else if queue.count < Self.maxQueued, !queue.contains(content) {
            queue.append(content)
        }
        showNextIfIdle()
    }

    private func showNextIfIdle() {
        guard !isShowing, !queue.isEmpty else { return }
        show(queue.removeFirst())
    }

    // MARK: - Panel

    private func show(_ content: NoticeContent) {
        isShowing = true
        let model = NoticeToastModel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let root = NoticeToast(content: content, reduceMotion: reduceMotion,
                               onOpen: { [weak self] in self?.openPopover() },
                               model: model)
        let host = NSHostingView(rootView: root)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let panel = self.panel ?? Self.makePanel()
        panel.setContentSize(size)
        panel.contentView = host
        panel.setFrameOrigin(Self.origin(for: size))
        panel.orderFrontRegardless()
        self.panel = panel
        self.model = model

        // Next runloop turn, so the view is on screen in its "hidden" pose
        // before it animates to "shown".
        DispatchQueue.main.async { model.isShown = true }

        let duration = content.kind == .adopted ? Self.adoptedDuration : Self.newSuggestionDuration
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        guard isShowing else { return }
        model?.isShown = false
        // Let the out-animation play, then free the slot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.panel?.contentView = nil
            self.model = nil
            self.isShowing = false
            self.showNextIfIdle()
        }
    }

    private func openPopover() {
        queue.removeAll()
        dismiss()
        Self.statusItemButton()?.performClick(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    // MARK: - Where the icon is

    /// Under the icon when it can be found, else the top-right corner of the
    /// screen with the menu bar — where the icon would be.
    static func origin(for size: CGSize) -> CGPoint {
        let gap: CGFloat = 2
        if let window = statusItemButton()?.window, let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            var x = window.frame.midX - size.width / 2
            x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
            return CGPoint(x: x, y: window.frame.minY - gap - size.height)
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return CGPoint(x: visible.maxX - size.width - 8, y: visible.maxY - size.height - gap)
    }

    /// The MenuBarExtra's status-bar button. SwiftUI exposes no handle to it,
    /// so it is found the way AppKit lays it out: the button inside this
    /// process's status-bar window.
    static func statusItemButton() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = findButton(in: window.contentView) { return button }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews {
            if let button = findButton(in: sub) { return button }
        }
        return nil
    }
}
