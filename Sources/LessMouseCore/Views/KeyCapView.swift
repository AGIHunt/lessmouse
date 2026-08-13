import SwiftUI

/// One keycap. The look is the house language applied to hardware: surface
/// fill, one strong hairline, no shadow, mono type — a flat key, not a
/// glossy 3-D key render (this panel has exactly zero shadows to spend).
struct KeyCapView: View {
    let cap: KeyCap

    var body: some View {
        Text(cap.label)
            .font(Typo.mono)
            .foregroundStyle(Palette.text)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(Palette.surface,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 1)
            )
    }
}

/// One shortcut as a row of caps: ⌥ ⌫. Modifier caps lead, in display order.
struct KeyCapRow: View {
    let caps: [KeyCap]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                KeyCapView(cap: cap)
            }
        }
    }
}
