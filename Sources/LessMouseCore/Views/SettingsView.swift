import SwiftUI
import AppKit

/// Settings. Rows change state the moment they are touched — this panel
/// closes on any outside click, so a form that needs a Save button is a
/// trap that eats edits.
struct SettingsView: View {
    let onBack: () -> Void

    @EnvironmentObject private var state: AppState
    @State private var confirmErase = false
    @State private var loginEnabled = LoginItemService.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(titleKey: "settings.title", symbol: "gearshape", onBack: onBack)
            MeasuredScrollBody(cap: Metrics.popoverMaxHeight) {
                VStack(alignment: .leading, spacing: Metrics.moduleGap) {
                    trackingModule
                    loginModule
                    exclusionsModule
                    languageModule
                    dataModule
                    Text(Loc.t("settings.privacyNote"))
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Metrics.gutter)
            }
        }
    }

    private var trackingModule: some View {
        Module {
            VStack(alignment: .leading, spacing: 0) {
                ModuleTitleRow("settings.tracking")
                ModuleRow(
                    title: Loc.t("settings.pauseTracking"),
                    subtitle: Loc.t("settings.pauseTracking.hint"),
                    subtitleLines: 2,
                    glyph: {
                        GlyphBadge(state.settings.isPaused ? .off : .on) {
                            Image(systemName: state.settings.isPaused ? "pause.fill" : "keyboard")
                                .font(.system(size: 12, weight: .medium))
                        }
                    },
                    trailing: {
                        Toggle("", isOn: Binding(
                            get: { state.settings.isPaused },
                            set: { state.settings.isPaused = $0 }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                )
            }
        }
    }

    private var loginModule: some View {
        Module {
            VStack(alignment: .leading, spacing: 0) {
                ModuleTitleRow("settings.startup")
                ModuleRow(
                    title: Loc.t("settings.launchAtLogin"),
                    subtitle: LoginItemService.isAvailable
                        ? Loc.t("settings.launchAtLogin.hint")
                        : Loc.t("settings.launchAtLogin.unavailable"),
                    subtitleLines: 2,
                    glyph: {
                        GlyphBadge(loginEnabled && LoginItemService.isAvailable ? .on : .off) {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                    },
                    trailing: {
                        Toggle("", isOn: Binding(
                            get: { loginEnabled },
                            set: { enabled in
                                loginEnabled = enabled
                                LoginItemService.setEnabled(enabled)
                            }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .disabled(!LoginItemService.isAvailable)
                    }
                )
            }
        }
    }

    private var exclusionsModule: some View {
        Module {
            VStack(alignment: .leading, spacing: 0) {
                ModuleTitleRow("settings.exclusions") {
                    Menu {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) {
                                state.settings.excludedApps.insert(app.bundleID)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                if state.settings.excludedApps.isEmpty {
                    Text(Loc.t("settings.exclusions.empty"))
                        .font(Typo.rowSubtitle)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, Metrics.rowPadding)
                        .padding(.vertical, Metrics.rowVertical)
                } else {
                    ForEach(state.settings.excludedApps.sorted(), id: \.self) { bundleID in
                        ModuleRow(
                            title: appName(bundleID),
                            subtitle: bundleID,
                            glyph: {
                                GlyphBadge(.off) {
                                    Image(systemName: "app.dashed")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            },
                            trailing: {
                                Button {
                                    state.settings.excludedApps.remove(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .buttonStyle(QuietButtonStyle())
                            }
                        )
                    }
                }
            }
        }
    }

    private var languageModule: some View {
        Module {
            VStack(alignment: .leading, spacing: 0) {
                ModuleTitleRow("settings.language")
                HStack(spacing: 8) {
                    languageChip(label: Loc.t("settings.language.system"), value: nil)
                    ForEach(Loc.available, id: \.self) { code in
                        languageChip(label: Loc.displayName(code), value: code)
                    }
                }
                .padding(.horizontal, Metrics.rowPadding)
                .padding(.vertical, Metrics.rowVertical)
            }
        }
    }

    /// One language option. The checked one wears the stronger chrome; the
    /// point of the row is telling the two apart at a glance.
    @ViewBuilder
    private func languageChip(label: String, value: String?) -> some View {
        let selected = Loc.override == value
        Button {
            Loc.override = value
            // Rebuild the popover's strings; sub-pages keep their state.
            state.objectWillChange.send()
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                }
                Text(label)
            }
        }
        .buttonStyle(AnyButtonStyle(selected ? SelectedChipStyle() : QuietButtonStyle()))
    }

    private var dataModule: some View {
        Module {
            VStack(alignment: .leading, spacing: 0) {
                ModuleTitleRow("settings.data")
                ModuleRow(
                    title: Loc.t("settings.dataLocation"),
                    subtitle: state.store.storageURL.path,
                    subtitleLines: 2,
                    glyph: {
                        GlyphBadge(.off) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 12, weight: .medium))
                        }
                    },
                    trailing: {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([state.store.storageURL])
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                )
                RowDivider()
                ModuleRow(
                    title: Loc.t("settings.eraseAll"),
                    subtitle: confirmErase
                        ? Loc.t("settings.eraseAll.confirm")
                        : Loc.t("settings.eraseAll.hint"),
                    subtitleTone: confirmErase ? Palette.danger : Palette.textTertiary,
                    subtitleLines: 2,
                    glyph: {
                        GlyphBadge(.off) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                        }
                    },
                    trailing: {
                        // Two taps, no system alert: a dialog sheet would take
                        // key window from the popover and close it.
                        Button(confirmErase ? Loc.t("common.confirm") : Loc.t("settings.eraseAll")) {
                            if confirmErase {
                                state.eraseAllData()
                                confirmErase = false
                            } else {
                                confirmErase = true
                            }
                        }
                        .buttonStyle(AnyButtonStyle(confirmErase ? DangerButtonStyle() : QuietButtonStyle()))
                    }
                )
            }
        }
    }

    // MARK: - Running-app names for exclusions

    private struct RunningApp {
        let bundleID: String
        let name: String
    }

    private var runningApps: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier else { return nil }
                return RunningApp(bundleID: bundleID,
                                  name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .localizedName
            ?? bundleID
    }
}

/// The selected language chip: quiet-button sizing with a surface + border so
/// it reads as the chosen one.
struct SelectedChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.captionStrong)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.surface,
                        in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Danger-tinted chip: the only place in the app danger gets to sit on a
/// control.
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.captionStrong)
            .foregroundStyle(Palette.danger)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.dangerSoft,
                        in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
