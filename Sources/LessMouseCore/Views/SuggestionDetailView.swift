import SwiftUI

/// A coaching card, opened: what was seen, what to do instead, the shortcuts
/// drawn as keycaps, and the two ways to be done with it.
struct SuggestionDetailView: View {
    let ruleID: String
    let onBack: () -> Void

    @EnvironmentObject private var state: AppState

    private var rule: SuggestionRule? { RuleLibrary.rule(withID: ruleID) }

    /// The number the summary line shows — today's count of whatever woke
    /// the rule, so the card opens on evidence, not a cold pitch.
    private var triggerCount: Int {
        guard let rule else { return 0 }
        switch rule.trigger {
        case .patternBursts(let id, _):
            return state.today.patterns[id] ?? 0
        case .comboUsage(let signatures, _):
            return signatures.reduce(0) { $0 + (state.today.combos[$1] ?? 0) }
        case .unusedWhileActive(_, let activity, _):
            switch activity {
            case .browserUse: return state.activityDays.browser
            case .multiAppUse: return state.activityDays.multiApp
            case .appSwitching: return 0
            }
        case .activityShare:
            return state.todayAppSwitches
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let rule {
                PageHeader(titleKey: rule.titleKey, symbol: rule.symbol, onBack: onBack)
                MeasuredScrollBody(cap: Metrics.popoverMaxHeight) {
                    VStack(alignment: .leading, spacing: Metrics.moduleGap) {
                        Module {
                            VStack(alignment: .leading, spacing: 0) {
                                // The evidence line. A card that opens with
                                // "you did this 4 times today" teaches; one
                                // that opens with "try this" nags.
                                HStack(spacing: 8) {
                                    GlyphBadge(.on) {
                                        Image(systemName: rule.symbol)
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Loc.format(rule.summaryKey, triggerCount))
                                            .font(Typo.rowSubtitle)
                                            .foregroundStyle(Palette.textTertiary)
                                        KeyCapRow(caps: rule.keyCaps.first ?? [])
                                            .padding(.top, 6)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(Metrics.rowPadding)
                            }
                        }

                        Module {
                            Text(Loc.t(rule.bodyKey))
                                .font(Typo.body)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(Metrics.rowPadding)
                        }

                        // The full menu of alternatives, one row each. More
                        // than one way in is the difference between coaching
                        // and prescribing.
                        if rule.keyCaps.count > 1 {
                            Module {
                                VStack(alignment: .leading, spacing: 0) {
                                    ModuleTitleRow("suggestion.alternatives")
                                    ForEach(Array(rule.keyCaps.dropFirst().enumerated()), id: \.offset) { _, caps in
                                        KeyCapRow(caps: caps)
                                            .padding(.horizontal, Metrics.rowPadding)
                                            .padding(.vertical, Metrics.rowVertical)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button(Loc.t("common.knowIt")) {
                                state.markRead(rule.id)
                                onBack()
                            }
                            .buttonStyle(AccentButtonStyle())

                            Button(Loc.t("common.neverAgain")) {
                                state.dismiss(rule.id)
                                onBack()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, Metrics.gutter)
                }
            } else {
                // A rule id the library no longer knows (older data file):
                // say so and go home rather than drawing a blank page.
                PageHeader(titleKey: "suggestion.title", symbol: "lightbulb", onBack: onBack)
                Text(Loc.t("suggestion.missing"))
                    .font(Typo.body)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(Metrics.gutter)
            }
        }
    }
}
