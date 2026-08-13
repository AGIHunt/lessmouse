import AppKit
import SwiftUI

/// The whole menu bar popover.
///
/// Information order follows the product's own priority: tracking status first
/// (is it even watching?), then today's ledger, then the suggestion inbox —
/// the screen the whole app exists for. Sub-screens are pages inside the
/// popover, never `.sheet`s.
public struct PopoverView: View {
    @EnvironmentObject private var state: AppState
    @State private var route: Route = .main
    /// The MenuBarExtra panel hosting this view — see fitWindowToContent.
    @State private var hostWindow: NSWindow?
    /// Natural height of the current page, measured by SwiftUI itself.
    @State private var naturalHeight: CGFloat = 0

    /// Sub-screens are pages inside the popover, never `.sheet`s. A sheet is a
    /// separate window, and the moment it becomes key the MenuBarExtra window
    /// resigns key and auto-dismisses — the popover vanished under the user's
    /// click and the sheet was left floating alone under the menu bar.
    enum Route: Equatable {
        case main
        case suggestion(String)
        case stats
        case settings
    }

    public init() {}

    /// The sections, laid out at their natural height.
    ///
    /// Kept separate because `body` needs this exact subtree twice — see
    /// MeasuredScrollBody, which measures one copy and scrolls the other.
    @ViewBuilder
    private var sections: some View {
        VStack(alignment: .leading, spacing: Metrics.moduleGap) {
            MainView(openSuggestion: { route = .suggestion($0) })
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 4)
        .padding(.bottom, Metrics.gutter)
    }

    public var body: some View {
        Group {
            switch route {
            case .main:
                // Rebuilt outright when the language changes, so every string
                // on it is re-read. Deliberately scoped to this branch: the
                // sub-pages hold state (a half-configured exclusion list) and
                // the language switch lives on one of them, so re-identifying
                // those would discard what someone is in the middle of.
                main.id(state.language ?? "system")
            case .suggestion(let ruleID):
                SuggestionDetailView(ruleID: ruleID) { route = .main }
            case .stats:
                StatsPageView { route = .main }
            case .settings:
                SettingsView { route = .main }
            }
        }
        .frame(width: Metrics.popoverWidth)
        // Measure the page's NATURAL height here — inside the flexible frame
        // below, so the probe reports the content's own size, never the
        // window's. This measurement, not AppKit's fittingSize (which just
        // parrots the current window size back), is what drives the window.
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear {
                    naturalHeight = proxy.size.height
                    fitWindowToContent()
                }
                .onChange(of: proxy.size.height) { _, height in
                    naturalHeight = height
                    fitWindowToContent()
                }
        })
        // Between a route switch and the fitWindowToContent snap, the window is
        // briefly taller than the page. Without this, SwiftUI centers the
        // content and everything above and below it is a transparent band with
        // the desktop showing through. Fill whatever height the window has,
        // pin the content to the top, and paint background over all of it.
        .frame(maxHeight: .infinity, alignment: .top)
        // Deliberately square: the panel's corners are the window's corners,
        // rounded once in `styleWindow`. Rounding the content as well is what
        // put white in the corners — see `roundWindowItself`.
        .background(PanelMaterial())
        .foregroundStyle(Palette.text)
        .tint(Palette.accent)
        .onAppear { state.popoverDidOpen() }
        .onDisappear {
            state.popoverDidClose()
            // Reopening the popover should land on the overview, not a page
            // someone left open yesterday.
            route = .main
        }
        .onChange(of: route) { _, newRoute in
            // The popover window can take clicks without the app being active,
            // but text fields only take *keystrokes* in the active app. The
            // sub-pages are exactly the screens with controls.
            if newRoute != .main {
                NSApp.activate(ignoringOtherApps: true)
            }
            fitWindowToContent()
        }
        .background(WindowAccessor { window in
            // Restyled on every callback, not only when the window changes
            // identity: a MenuBarExtra may hand back the same window each time
            // it opens, and re-applying is idempotent and cheap, whereas
            // missing it once leaves the panel with square corners.
            if let window { styleWindow(window) }
            if hostWindow !== window {
                hostWindow = window
                fitWindowToContent()
            }
        })
    }

    private var main: some View {
        VStack(spacing: 0) {
            TrackingHeader()

            // The body has to be sized deliberately, and synchronously —
            // see MeasuredScrollBody for why a bare ScrollView cannot be
            // trusted to size the window.
            MeasuredScrollBody(cap: Metrics.popoverMaxHeight) { sections }

            FooterBar(openSettings: { route = .settings },
                      openStats: { route = .stats })
        }
    }

    /// Give the panel one shape, owned by the window.
    ///
    /// Takes the window directly rather than reading `hostWindow`: that is
    /// `@State`, and reading it back in the same closure that just assigned it
    /// is not guaranteed to see the new value.
    ///
    /// The window is made transparent so nothing of AppKit's own shows around
    /// the content; the shadow is then derived from the content's alpha
    /// channel, which is why it has to be invalidated once the window has
    /// stopped being opaque.
    private func styleWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        Self.roundWindowItself(window)
        window.invalidateShadow()
    }

    /// Round the window, not just what is inside it.
    ///
    /// The white the corners keep comes from neither the window's background
    /// colour nor any view: modern macOS shapes a menu bar panel with a corner
    /// mask of its own — `NSWindow._cornerMask` on this window is a 13×13
    /// image, i.e. a 6pt radius — and fills that shape with the system menu
    /// material out of process, behind everything AppKit hands us. Our content
    /// is rounded at 16, so the ring between the two arcs is the system's own
    /// near-white backdrop, which is why clipping views and hiding backdrops
    /// never reaches it.
    ///
    /// Telling the window to use our radius makes the two shapes the same one.
    /// `_setCornerRadius:` is private, hence the `responds(to:)` guard and the
    /// message send by IMP: if a future macOS drops it the panel simply keeps
    /// AppKit's radius, and the worst case is the cosmetic ring coming back —
    /// nothing crashes and nothing is unreachable.
    private static func roundWindowItself(_ window: NSWindow) {
        let selector = Selector(("_setCornerRadius:"))
        guard window.responds(to: selector),
              let method = class_getInstanceMethod(type(of: window), selector) else { return }
        typealias SetRadius = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        let send = unsafeBitCast(method_getImplementation(method), to: SetRadius.self)
        send(window, selector, Metrics.panelRadius)
        // The radius alone leaves AppKit holding the mask image it built for
        // its own; this is the nudge that makes it draw a new one.
        let invalidate = Selector(("_cornerMaskChanged"))
        if window.responds(to: invalidate) {
            window.perform(invalidate)
        }
    }

    /// Snap the popover window to the measured content height, top edge pinned.
    ///
    /// The MenuBarExtra window grows when SwiftUI content grows, but it does
    /// not shrink back: navigate from the tall overview to a shorter page and
    /// the window keeps the old height, and the page floats between
    /// transparent bands. AppKit is the only party who can fix that. The height
    /// used is the GeometryReader measurement above — asking the window's
    /// contentView for `fittingSize` answers with the current window size,
    /// which makes the whole exercise a no-op.
    private func fitWindowToContent() {
        DispatchQueue.main.async {
            guard let window = hostWindow else { return }
            let targetHeight = naturalHeight
            guard targetHeight > 1 else { return }
            var frame = window.frame
            guard abs(frame.height - targetHeight) > 0.5 else { return }
            let topY = frame.maxY
            frame.size.height = targetHeight
            frame.origin.y = topY - targetHeight
            window.setFrame(frame, display: true, animate: false)
            // A transparent window's shadow is cast from its content's alpha,
            // and AppKit does not recompute it on resize — without this the
            // panel keeps the shadow of whatever height it had before.
            window.invalidateShadow()
        }
    }
}

// MARK: - Footer

struct FooterBar: View {
    @EnvironmentObject private var state: AppState
    let openSettings: () -> Void
    let openStats: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                openStats()
            } label: {
                Label(Loc.t("menu.stats"), systemImage: "chart.bar")
            }
            .buttonStyle(QuietButtonStyle())

            Button {
                openSettings()
            } label: {
                Label(Loc.t("menu.settings"), systemImage: "gearshape")
            }
            .buttonStyle(QuietButtonStyle())

            Spacer(minLength: 0)

            Button(Loc.t("menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(QuietButtonStyle())
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
