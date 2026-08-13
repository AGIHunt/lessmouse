import SwiftUI

/// Status line: dot + "tracking / paused / needs permission", with today's
/// headline number riding underneath. The dot's colour is the whole story —
/// green live, gray paused, amber waiting on the user.
struct TrackingHeader: View {
    @EnvironmentObject private var state: AppState

    private var dot: Color {
        switch state.permissionPhase {
        case .granted: return state.isTracking ? Palette.accent : Palette.textTertiary
        case .needsPermission, .tapFailed: return Palette.warning
        }
    }

    private var headline: String {
        switch state.permissionPhase {
        case .granted: return state.isTracking
            ? Loc.t("tracking.active")
            : Loc.t("tracking.paused")
        case .needsPermission, .tapFailed: return Loc.t("tracking.needsPermission")
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
