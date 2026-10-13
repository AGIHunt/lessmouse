import SwiftUI

/// What a toast needs to draw — resolved once, so the view never reaches back
/// into AppState while it animates out.
public struct NoticeContent: Equatable {
    public enum Kind: Equatable { case newSuggestion, adopted }

    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let caps: [KeyCap]

    public init(kind: Kind, title: String, subtitle: String, symbol: String, caps: [KeyCap]) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.caps = caps
    }

    /// nil when the rule is unknown (a card for a shortcut the store no
    /// longer has) — nothing to say, so nothing is shown.
    @MainActor
    public static func make(for notice: CoachNotice, state: AppState) -> NoticeContent? {
        guard let rule = state.rule(withID: notice.ruleID) else { return nil }
        switch notice {
        case .newSuggestion:
            return NoticeContent(kind: .newSuggestion,
                                 title: Loc.t("notice.new.title"),
                                 subtitle: Loc.t(rule.titleKey),
                                 symbol: rule.symbol,
                                 caps: rule.keyCaps.first ?? [])
        case .adopted:
            return NoticeContent(kind: .adopted,
                                 title: Loc.format("notice.adopted.title", rule.primaryShortcutLabel),
                                 subtitle: Loc.t(rule.titleKey),
                                 symbol: "checkmark",
                                 caps: [])
        }
    }
}

/// Drives the in/out animation from outside the view: the presenter flips
/// `isShown` and waits for the out-animation before closing the panel.
@MainActor
final class NoticeToastModel: ObservableObject {
    @Published var isShown = false
}

/// The pop-up itself: one module-shaped block under the menu bar icon.
///
/// Motion is the message here, so it is spent deliberately: the block drops
/// in on a spring; a new card pulses its glyph twice ("something arrived"),
/// an adoption pops a check with a single ring and a few sparks ("done").
/// Under Reduce Motion all of it collapses to a fade.
struct NoticeToast: View {
    let content: NoticeContent
    let reduceMotion: Bool
    let onOpen: () -> Void
    @ObservedObject var model: NoticeToastModel

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Metrics.rowGlyphGap + 2) {
                glyph
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(Typo.rowTitle)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(content.subtitle)
                        .font(Typo.rowSubtitle)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if !content.caps.isEmpty {
                    KeyCapRow(caps: content.caps)
                }
            }
            .padding(.horizontal, Metrics.rowPadding)
            .padding(.vertical, Metrics.rowVerticalLoose)
            .frame(width: NoticeToast.width)
            .background(PanelMaterial())
            .background(Palette.moduleFill)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius - 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.panelRadius - 4, style: .continuous)
                    .strokeBorder(Palette.moduleBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(model.isShown ? 1 : 0)
        .offset(y: model.isShown || reduceMotion ? 0 : -14)
        .scaleEffect(model.isShown || reduceMotion ? 1 : 0.96, anchor: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.42, dampingFraction: 0.78),
                   value: model.isShown)
        .padding(NoticeToast.shadowInset)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    static let width: CGFloat = 320
    /// Room around the block for the window shadow and the spark burst.
    static let shadowInset: CGFloat = 14

    @ViewBuilder private var glyph: some View {
        switch content.kind {
        case .newSuggestion:
            PulsingGlyph(symbol: content.symbol, animate: !reduceMotion && model.isShown)
        case .adopted:
            AdoptedGlyph(animate: !reduceMotion && model.isShown)
        }
    }
}

/// A new card: the glyph with a ring that ripples outward twice.
private struct PulsingGlyph: View {
    let symbol: String
    let animate: Bool
    @State private var ripple = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(Palette.accent, lineWidth: 2)
                    .frame(width: Metrics.glyph, height: Metrics.glyph)
                    .scaleEffect(ripple ? 1.9 : 1)
                    .opacity(ripple ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.1).delay(Double(i) * 0.45), value: ripple)
            }
            GlyphBadge(.on) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            }
        }
        .frame(width: Metrics.glyph, height: Metrics.glyph)
        .onChange(of: animate) { _, now in if now { ripple = true } }
        .onAppear { if animate { ripple = true } }
    }
}

/// An adoption: a check that pops in, one ring, and a handful of sparks —
/// a moment, not confetti.
private struct AdoptedGlyph: View {
    let animate: Bool
    @State private var burst = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.accent, lineWidth: 2)
                .frame(width: Metrics.glyph, height: Metrics.glyph)
                .scaleEffect(burst ? 2.1 : 1)
                .opacity(burst ? 0 : 0.8)
                .animation(.easeOut(duration: 0.9), value: burst)
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 4, height: 4)
                    .offset(x: burst ? cos(angle) * 24 : 0, y: burst ? sin(angle) * 24 : 0)
                    .opacity(burst ? 0 : 1)
                    .animation(.easeOut(duration: 0.7).delay(0.08), value: burst)
            }
            GlyphBadge(.on) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
            }
            .scaleEffect(burst || !animate ? 1 : 0.4)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: burst)
        }
        .frame(width: Metrics.glyph, height: Metrics.glyph)
        .onChange(of: animate) { _, now in if now { burst = true } }
        .onAppear { if animate { burst = true } }
    }
}
