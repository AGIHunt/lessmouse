import SwiftUI

/// The popover's main content: the overview when tracking works, the
/// permission page when it cannot. (The status header above is always shown.)
struct MainView: View {
    var openSuggestion: (String) -> Void
    var openStats: () -> Void

    @EnvironmentObject private var state: AppState

    var body: some View {
        switch state.permissionPhase {
        case .granted:
            VStack(alignment: .leading, spacing: Metrics.moduleGap) {
                TodayOverview(openStats: openStats)
            }
        case .needsPermission, .tapFailed:
            PermissionView()
        }
    }
}

/// Status line: dot + "tracking / paused / needs permission", with today's
/// headline number riding underneath.
struct TrackingHeader: View {
    @EnvironmentObject private var state: AppState

    private var dot: Color {
        switch state.permissionPhase {
        case .granted: return state.isTracking ? Palette.accent : Palette.textTertiary
        case .needsPermission: return Palette.warning
        case .tapFailed: return Palette.warning
        }
    }

    private var headline: String {
        switch state.permissionPhase {
        case .granted: return state.isTracking
            ? Loc.t("tracking.active")
            : Loc.t("tracking.paused")
        case .needsPermission: return Loc.t("tracking.needsPermission")
        case .tapFailed: return Loc.t("tracking.needsPermission")
        }
    }

    private var subline: String? {
        guard case .granted = state.permissionPhase else { return nil }
        return Loc.format("tracking.todaySummary", state.today.totalEvents,
                          state.today.combos.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(dot.opacity(0.25), lineWidth: 4))
                Text(headline)
                    .font(Typo.title)
                    .foregroundStyle(Palette.text)
            }
            if let subline {
                Text(subline)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, Metrics.rowVerticalLoose)
        .padding(.bottom, Metrics.rowVertical)
    }
}

/// Today's ledger: three rows, three numbers, all monospaced. Green is spent
/// on the tracking dot above — these glyphs stay off, counts carry the screen.
struct TodayOverview: View {
    var openStats: () -> Void
    @EnvironmentObject private var state: AppState

    var body: some View {
        Module {
            ModuleRow(
                title: Loc.t("today.events"),
                subtitle: Loc.t("today.events.hint"),
                glyph: { GlyphBadge(.off) { Image(systemName: "keyboard") } },
                trailing: { Text("\(state.today.totalEvents)").font(Typo.rowMetric) }
            )
            RowDivider()
            ModuleRow(
                title: Loc.t("today.patterns"),
                subtitle: Loc.t("today.patterns.hint"),
                glyph: { GlyphBadge(.off) { Image(systemName: "bolt.slash") } },
                trailing: { Text("\(state.today.totalPatterns)").font(Typo.rowMetric) }
            )
            RowDivider()
            ModuleRow(
                title: Loc.t("today.combos"),
                subtitle: Loc.t("today.combos.hint"),
                glyph: { GlyphBadge(.off) { Image(systemName: "command") } },
                trailing: { Text("\(state.today.combos.count)").font(Typo.rowMetric) }
            )
        }
    }
}
