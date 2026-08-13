import SwiftUI

/// Scaffold placeholder — replaced by the full settings page in the views step.
struct SettingsView: View {
    let onBack: () -> Void

    var body: some View {
        PageHeader(titleKey: "settings.title", symbol: "gearshape", onBack: onBack)
    }
}
