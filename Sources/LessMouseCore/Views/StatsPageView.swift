import SwiftUI

/// Scaffold placeholder — replaced by the full stats page in the views step.
struct StatsPageView: View {
    let onBack: () -> Void

    var body: some View {
        PageHeader(titleKey: "stats.title", symbol: "chart.bar", onBack: onBack)
    }
}
