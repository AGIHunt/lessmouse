import SwiftUI
import AppKit

/// The ledger: what you actually press. Every number here is one the user
/// might audit against stats.json, so every number is monospaced.
struct StatsPageView: View {
    let onBack: () -> Void

    @EnvironmentObject private var state: AppState

    private var topCombos: [(signature: String, count: Int)] {
        state.store.topCombos(dayLimit: 7, limit: 8)
    }

    private var adoptedCount: Int {
        state.suggestionStates.values.count { $0.status == .adopted }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(titleKey: "stats.title", symbol: "chart.bar", onBack: onBack)
            MeasuredScrollBody(cap: Metrics.popoverMaxHeight) {
                VStack(alignment: .leading, spacing: Metrics.moduleGap) {
                    Module {
                        VStack(alignment: .leading, spacing: 0) {
                            ModuleTitleRow("stats.topCombos") {
                                Text(Loc.t("stats.topCombos.range"))
                                    .font(Typo.rowSubtitle)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            if topCombos.isEmpty {
                                Text(Loc.t("stats.empty"))
                                    .font(Typo.rowSubtitle)
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, Metrics.rowPadding)
                                    .padding(.vertical, Metrics.rowVertical)
                            } else {
                                let peak = topCombos.first?.count ?? 1
                                ForEach(Array(topCombos.enumerated()), id: \.offset) { index, entry in
                                    if index > 0 { RowDivider() }
                                    ModuleRow(
                                        title: Fmt.signatureDisplay(entry.signature),
                                        glyph: {
                                            GlyphBadge(.off) {
                                                Image(systemName: "command")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                        },
                                        trailing: {
                                            Text(Fmt.compactCount(entry.count)).font(Typo.numeric)
                                        },
                                        extra: {
                                            MeterBar(fraction: Double(entry.count) / Double(max(peak, 1)),
                                                     tint: Palette.accent)
                                                .padding(.top, 4)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    Module {
                        VStack(alignment: .leading, spacing: 0) {
                            ModuleTitleRow("stats.progress")
                            ModuleRow(
                                title: Loc.format("stats.adopted", adoptedCount, RuleLibrary.all.count),
                                subtitle: Loc.t("stats.adopted.hint"),
                                glyph: {
                                    GlyphBadge(adoptedCount > 0 ? .on : .off) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                },
                                trailing: {
                                    Text("\(adoptedCount)/\(RuleLibrary.all.count)").font(Typo.numeric)
                                },
                                extra: {
                                    MeterBar(fraction: Double(adoptedCount) / Double(RuleLibrary.all.count),
                                             tint: Palette.accent)
                                        .padding(.top, 4)
                                }
                            )
                            RowDivider()
                            ModuleRow(
                                title: Loc.format("stats.daysObserved", state.store.daysObserved()),
                                subtitle: Loc.t("stats.daysObserved.hint"),
                                glyph: {
                                    GlyphBadge(.off) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                }
                            )
                        }
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([state.store.storageURL])
                    } label: {
                        Label(Loc.t("stats.revealData"), systemImage: "folder")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.leading, 4)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Metrics.gutter)
            }
        }
    }
}
