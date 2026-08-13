import SwiftUI

/// The one moment the app gets to be delighted: the user pressed the thing
/// the card taught. Green disc, the shortcut itself in the title, one line
/// of warmth, and a quiet way out — confetti would survive exactly one
/// screenshot before becoming embarrassing.
struct CelebrationBanner: View {
    let ruleID: String

    @EnvironmentObject private var state: AppState

    private var rule: SuggestionRule? { RuleLibrary.rule(withID: ruleID) }

    var body: some View {
        if let rule {
            Module {
                ModuleRow(
                    title: Loc.format("celebration.title", rule.primaryShortcutLabel),
                    subtitle: Loc.t(rule.titleKey),
                    glyph: {
                        GlyphBadge(.on) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    },
                    trailing: {
                        Button(Loc.t("common.knowIt")) {
                            state.dismissCelebration()
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                )
            }
        }
    }
}
