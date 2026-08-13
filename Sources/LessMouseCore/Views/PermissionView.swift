import SwiftUI

/// The first screen a fresh install sees. Its one job: get the user to grant,
/// while being extremely clear about what is and is not being asked for.
struct PermissionView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Loc.t("permission.body"))
                        .font(Typo.body)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // What actually gets stored, shown as what actually gets stored:
            // signature tokens, not prose promises.
            HStack(spacing: 6) {
                Text(Loc.t("permission.onlyRecords"))
                    .font(Typo.mono)
                    .foregroundStyle(Palette.text)
                Text("cmd+c ×12")
                    .font(Typo.mono)
                    .foregroundStyle(Palette.textTertiary)
                Text("·")
                    .font(Typo.mono)
                    .foregroundStyle(Palette.textTertiary)
                Text("⌫ ×87")
                    .font(Typo.mono)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Palette.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))

            if case .tapFailed(let detail) = state.permissionPhase {
                Text(Loc.format("permission.failedHint", detail))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(Loc.t("permission.relaunchHint"))
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(Loc.t("permission.openSettings")) {
                    state.openPermissionSettings()
                }
                .buttonStyle(AccentButtonStyle())

                Button(Loc.t("permission.recheck")) {
                    state.recheckPermission()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.gutter)
        .background(Palette.moduleFill,
                    in: RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
                .strokeBorder(Palette.moduleBorder, lineWidth: 1)
        )
    }
}
