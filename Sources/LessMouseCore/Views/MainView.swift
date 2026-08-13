import SwiftUI

/// Scaffold placeholder — replaced by the full overview in the views step.
struct MainView: View {
    var openSuggestion: (String) -> Void
    var openStats: () -> Void

    var body: some View {
        Text(Loc.t("app.name"))
            .font(Typo.title)
            .padding()
    }
}

/// Scaffold placeholder.
struct TrackingHeader: View {
    var body: some View {
        EmptyView()
    }
}
