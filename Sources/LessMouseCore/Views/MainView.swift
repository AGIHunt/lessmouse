import SwiftUI

/// The popover's main content: the overview when tracking works, the
/// permission page when it cannot. (The status header above is always shown.)
struct MainView: View {
    var openSuggestion: (String) -> Void

    @EnvironmentObject private var state: AppState

    /// Inbox rows: unread first, then read, then adopted — each still worth
    /// one look as proof of progress. Dormant and dismissed never appear.
    private var inboxRules: [SuggestionRule] {
        let order: [SuggestionStatus] = [.unread, .read, .adopted]
        return RuleLibrary.all.filter { rule in
            if let ruleState = state.suggestionStates[rule.id] {
                return order.contains(ruleState.status)
            }
            return false
        }
        .sorted { lhs, rhs in
            let lhsIndex = order.firstIndex(of: state.suggestionStates[lhs.id]?.status ?? .dormant) ?? 99
            let rhsIndex = order.firstIndex(of: state.suggestionStates[rhs.id]?.status ?? .dormant) ?? 99
            return lhsIndex < rhsIndex
        }
    }

    var body: some View {
        switch state.permissionPhase {
        case .granted:
            VStack(alignment: .leading, spacing: Metrics.moduleGap) {
                if let celebration = state.celebration {
                    CelebrationBanner(ruleID: celebration)
                }
                TodayOverview()
                SuggestionInbox(rules: inboxRules, openSuggestion: openSuggestion)
            }
        case .needsPermission, .tapFailed:
            PermissionView()
        }
    }
}

/// Today's ledger: three rows, three numbers, all monospaced. Green is spent
/// on the tracking dot above — these glyphs stay off, counts carry the screen.
struct TodayOverview: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Module {
            ModuleRow(
                title: Loc.t("today.events"),
                subtitle: Loc.t("today.events.hint"),
                glyph: {
                    GlyphBadge(.off) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12, weight: .medium))
                    }
                },
                trailing: { Text("\(state.today.totalEvents)").font(Typo.rowMetric) }
            )
            RowDivider()
            ModuleRow(
                title: Loc.t("today.patterns"),
                subtitle: Loc.t("today.patterns.hint"),
                glyph: {
                    GlyphBadge(.off) {
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 12, weight: .medium))
                    }
                },
                trailing: { Text("\(state.today.totalPatterns)").font(Typo.rowMetric) }
            )
            RowDivider()
            ModuleRow(
                title: Loc.t("today.combos"),
                subtitle: Loc.t("today.combos.hint"),
                glyph: {
                    GlyphBadge(.off) {
                        Image(systemName: "command")
                            .font(.system(size: 12, weight: .medium))
                    }
                },
                trailing: { Text("\(state.today.combos.count)").font(Typo.rowMetric) }
            )
        }
    }
}

/// The inbox: one row per coaching card, unread ones carrying the green disc
/// and a "new" pill, every row opening its card.
struct SuggestionInbox: View {
    let rules: [SuggestionRule]
    let openSuggestion: (String) -> Void

    @EnvironmentObject private var state: AppState

    var body: some View {
        Module {
            VStack(alignment: .leading, spacing: 0) {
                ModuleTitleRow("inbox.title") {
                    if state.unreadCount > 0 {
                        Pill(Loc.format("inbox.unread", state.unreadCount), tone: .accent)
                    }
                }
                if rules.isEmpty {
                    Text(Loc.t("inbox.empty"))
                        .font(Typo.rowSubtitle)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.rowPadding)
                        .padding(.vertical, Metrics.rowVertical)
                } else {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { RowDivider() }
                        inboxRow(rule)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inboxRow(_ rule: SuggestionRule) -> some View {
        let ruleState = state.suggestionStates[rule.id]
        let status = ruleState?.status ?? .dormant

        Button {
            openSuggestion(rule.id)
        } label: {
            ModuleRow(
                title: Loc.t(rule.titleKey),
                subtitle: summary(for: rule),
                glyph: {
                    GlyphBadge(status == .unread ? .on : .off) {
                        Image(systemName: rule.symbol)
                            .font(.system(size: 12, weight: .medium))
                    }
                },
                trailing: {
                    if status == .unread {
                        Pill(Loc.t("common.new"), tone: .accent)
                    } else if status == .adopted {
                        Pill(Loc.t("common.adopted"), tone: .positive)
                    }
                }
            )
        }
        .buttonStyle(RowButtonStyle())
    }

    /// The evidence line, same computation the card's own page shows.
    private func summary(for rule: SuggestionRule) -> String {
        switch rule.trigger {
        case .patternBursts(let id, _):
            return Loc.format(rule.summaryKey, state.today.patterns[id] ?? 0)
        case .comboUsage(let signatures, _):
            let total = signatures.reduce(0) { $0 + (state.today.combos[$1] ?? 0) }
            return Loc.format(rule.summaryKey, total)
        case .comboUnusedAfterDays:
            return Loc.format(rule.summaryKey, state.store.daysObserved())
        }
    }
}
