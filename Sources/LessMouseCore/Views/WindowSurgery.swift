import AppKit
import SwiftUI

// The four pieces of AppKit plumbing a `MenuBarExtra(.window)` panel needs to
// look and behave like a system menu bar panel. Every one of them exists
// because the plain SwiftUI path failed in a specific, reproducible way —
// notes below, at the site of each failure.

/// The panel's background: the same material every system menu bar panel uses.
///
/// A flat opaque fill is the one thing that reads as "not a Mac panel" next to
/// Wi-Fi or Control Center, which are translucent and pick up whatever is
/// behind them. `.menu` is the material AppKit gives menus and menu bar
/// extras, and `.behindWindow` is what makes it sample the desktop rather than
/// the window's own content — which needs the window to stay non-opaque with a
/// clear background, as the popover's `styleWindow` leaves it.
///
/// Nothing here handles Reduce Transparency: `NSVisualEffectView` already
/// falls back to a solid fill when that is on.
struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .menu
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

/// Hands the hosting NSWindow to SwiftUI code that needs to talk to AppKit
/// about it. Zero-sized, draws nothing.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

// MARK: - Body sizing

/// Scrollable body whose reported size is always min(content's natural height,
/// cap) — computed by this layout itself, so it cannot be miscalculated by a
/// host that proposes nothing (ideal-size pass) or something unexpected.
///
/// A `MenuBarExtra(.window)` sizes its window to the content's *ideal*
/// height, and a ScrollView has no ideal height of its own — left to itself it
/// reports something tiny, which collapses the whole popover into a sliver
/// that the user has to scroll forever.
///
/// Two subviews over the same content: the plain sections (index 0, doubling
/// as the measuring copy) and a ScrollView wrapping them (index 1). Content
/// that fits under the cap is shown plain; content that overflows shows the
/// scrolling copy at exactly the cap. Either way exactly one copy is placed in
/// bounds and the other is parked far off-canvas, where the window never draws
/// it.
struct MeasuredScrollBody<Content: View>: View {
    let cap: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        CappedByFirstChild(cap: cap) {
            content()
            ScrollView(.vertical) { content() }
                .scrollIndicators(.automatic)
        }
    }
}

struct CappedByFirstChild: Layout {
    let cap: CGFloat

    private static let offscreen = CGPoint(x: -100_000, y: -100_000)

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = subviews[0].sizeThatFits(
            ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: natural.width, height: min(natural.height, cap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let natural = subviews[0].sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil))
        if natural.height <= cap {
            subviews[0].place(at: bounds.origin,
                              proposal: ProposedViewSize(width: bounds.width, height: natural.height))
            subviews[1].place(at: Self.offscreen, proposal: .zero)
        } else {
            subviews[0].place(at: Self.offscreen,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(at: bounds.origin,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}
