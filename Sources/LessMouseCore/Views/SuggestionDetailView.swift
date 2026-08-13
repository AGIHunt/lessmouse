import SwiftUI

/// Scaffold placeholder — replaced by the full detail page in the views step.
struct SuggestionDetailView: View {
    let ruleID: String
    let onBack: () -> Void

    var body: some View {
        PageHeader(titleKey: "suggestion.title", symbol: "lightbulb", onBack: onBack)
    }
}
