import AppKit
import SwiftUI

// Design tokens — the house language: "ink, signal green, and clean paper".
//
// Borrowed verbatim from the sibling project UseMyAgents (which mirrors its
// web console's tokens.css), so both apps read as products of the same hand.
// Identity: near-black ink on clean neutral surfaces with ONE vivid green
// accent (#2CDB5C) spent only where emphasis is earned — "on" states, focus,
// positive status, the single primary highlight of a screen. Chrome is ink
// and neutral grays; monospace for anything a user might audit.
//
// #2CDB5C is a fill/indicator color, NOT a text color — text-sized green uses
// accentInk. Light/dark follow `NSApp.effectiveAppearance`: no forced theme.

public enum Palette {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    public static let background = dynamic(light: hex(0xF7F8F7), dark: hex(0x0B0D0B))
    public static let surface = dynamic(light: hex(0xFFFFFF), dark: hex(0x141714))
    public static let surfaceAlt = dynamic(light: hex(0xEFF1EF), dark: hex(0x1C201C))
    public static let border = dynamic(light: hex(0xE3E6E3), dark: hex(0x272C28))
    public static let borderStrong = dynamic(light: hex(0xC6CCC7), dark: hex(0x3B423C))
    public static let text = dynamic(light: hex(0x0B0F0C), dark: hex(0xF2F4F2))
    public static let textSecondary = dynamic(light: hex(0x3E463F), dark: hex(0xC2C9C3))
    public static let textTertiary = dynamic(light: hex(0x6D766E), dark: hex(0x838D85))
    /// The brand green, for fills/rings/dots/"on" states.
    public static let accent = dynamic(light: hex(0x2CDB5C), dark: hex(0x2CDB5C))
    public static let accentHover = dynamic(light: hex(0x22C24E), dark: hex(0x4FE47A))
    /// Readable green for text sitting on bg/surface.
    public static let accentInk = dynamic(light: hex(0x128A38), dark: hex(0x4FE47A))
    public static let accentSoft = dynamic(light: hex(0xDFF8E7), dark: hex(0x11361D))
    /// Default strong-action fill (black button, white label).
    public static let ink = dynamic(light: hex(0x111511), dark: hex(0xF2F4F2))
    public static let inkHover = dynamic(light: hex(0x2A2F2A), dark: hex(0xD9DDD9))
    public static let onInk = dynamic(light: hex(0xFFFFFF), dark: hex(0x0B0D0B))
    public static let positive = dynamic(light: hex(0x128A38), dark: hex(0x4FE47A))
    public static let warning = dynamic(light: hex(0xA16207), dark: hex(0xEAB308))
    public static let danger = dynamic(light: hex(0xD92D20), dark: hex(0xF87171))

    /// Badge fills: semantic hue at 15% (light) / 25% (dark).
    public static let positiveSoft = dynamic(light: hex(0x128A38, alpha: 0.15), dark: hex(0x4FE47A, alpha: 0.25))
    public static let warningSoft = dynamic(light: hex(0xA16207, alpha: 0.15), dark: hex(0xEAB308, alpha: 0.25))
    public static let dangerSoft = dynamic(light: hex(0xD92D20, alpha: 0.15), dark: hex(0xF87171, alpha: 0.25))
    /// Text on top of the accent fill: ink — white on #2CDB5C fails contrast.
    public static let onAccent = Color(nsColor: hex(0x07230F))

    /// A module's fill inside the popover, where the panel is a live material.
    ///
    /// `surface` is opaque by design: it is the fill for anything drawn on a
    /// solid background, and it stays that way. But the popover's own
    /// background is the system menu material (`PanelMaterial`), and an
    /// opaque white block on translucent glass is exactly what makes a panel
    /// look painted-on next to Wi-Fi or Control Center. Tinted white instead,
    /// so the module reads as a lighter part of the same glass rather than as
    /// paper laid over it.
    public static let moduleFill = dynamic(light: hex(0xFFFFFF, alpha: 0.55),
                                           dark: hex(0xFFFFFF, alpha: 0.07))
    /// The hairline that goes with `moduleFill`: light enough to describe an
    /// edge without drawing a box, since the fill now carries the separation.
    public static let moduleBorder = dynamic(light: hex(0xFFFFFF, alpha: 0.65),
                                             dark: hex(0xFFFFFF, alpha: 0.10))
}

/// Body never drops below 13pt; every counted number is monospace with
/// tabular figures ("what makes a number feel counted, not decorated").
public enum Typo {
    public static let title = Font.system(size: 15, weight: .semibold)
    /// Title of a module row — the "Wi-Fi" line of a Control Center block.
    ///
    /// 13pt, which is macOS's Headline/Body size. It was briefly 14, on the
    /// theory that a bigger label would feel less cramped; 14 is not a macOS
    /// text style at all (the scale goes 13 Headline → 15 Title 3), and
    /// off-system type sizes are a large part of what makes a Mac app look
    /// not-quite-right. The room came from cutting lines, not from setting
    /// them larger.
    public static let rowTitle = Font.system(size: 13, weight: .medium)
    /// Second line of a module row — 11pt = macOS Subheadline.
    public static let rowSubtitle = Font.system(size: 11, weight: .regular)
    public static let body = Font.system(size: 13, weight: .regular)
    public static let bodyStrong = Font.system(size: 13, weight: .medium)
    public static let caption = Font.system(size: 11, weight: .regular)
    public static let captionStrong = Font.system(size: 11, weight: .medium)
    /// Row-level ledger figure: big enough to be the point of its line.
    public static let rowMetric = Font.system(size: 15, weight: .semibold, design: .monospaced).monospacedDigit()
    /// Inline ledger numbers: counts inside a row.
    public static let numeric = Font.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit()
    /// Commands, ids, keys.
    public static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
}

public enum Metrics {
    /// A Control Center block needs horizontal room for a glyph, two lines of
    /// text and a trailing control without any of them truncating.
    public static let popoverWidth: CGFloat = 360
    /// Corner radius of the popover window itself.
    ///
    /// Not the same decision as the module radius, and much larger: system menu
    /// bar panels (the battery and Wi-Fi popovers) are generously rounded, and
    /// AppKit's default for a `MenuBarExtra(.window)` is visibly tighter than
    /// they are, which made this panel look mean next to them. The modules stay
    /// at 10 — a big outer curve wrapping small inner ones is the normal
    /// relationship; it is small-inside-small that reads as timid.
    public static let panelRadius: CGFloat = 16
    /// Body cap. With header and footer (~90pt) the window stays under
    /// ~740pt, which fits the smallest laptop display Apple ships.
    public static let popoverMaxHeight: CGFloat = 640
    /// Floor for the scrolling body, so a popover that is still loading is
    /// obviously a popover rather than a sliver.
    public static let popoverMinBodyHeight: CGFloat = 120
    // Everything below is on a 4px grid. It briefly was not — 9pt row padding,
    // a 10pt glyph gap, a 14pt gutter — each picked to match some measurement
    // of a reference. Borrowed numbers are not worth breaking your own grid
    // for, especially when the borrowed ones turned out to be other people's
    // eyeball estimates rather than published values.
    public static let gutter: CGFloat = 12
    public static let radiusSmall: CGFloat = 6
    /// Also the module radius: the value three independent open-source Control
    /// Center reimplementations converge on by eye happens to be exactly 10.
    ///
    /// (Apple publishes nothing here — Control Center draws its blocks
    /// procedurally, ships no module artwork to measure, and has no component
    /// in Apple's own macOS Figma library. Started at 18, which on a ~48pt row
    /// read as a pill and turned the column into iOS widgets.)
    public static let radiusMedium: CGFloat = 10
    /// Gap between modules. Tight on purpose — modules carry their own padding,
    /// and a wide gap lets them drift apart into separate cards instead of
    /// tiling into one panel.
    public static let moduleGap: CGFloat = 8
    /// Diameter of the circular state glyph that leads every module row.
    /// Unpublished by Apple; the reimplementations say 26 or 28, so the grid
    /// breaks the tie.
    public static let glyph: CGFloat = 28
    /// Left inset of a divider between module rows: it starts where the text
    /// starts, so the glyph column reads as one continuous rail.
    public static var rowDividerInset: CGFloat { rowPadding + glyph + rowGlyphGap }
    public static let rowPadding: CGFloat = 12
    public static let rowGlyphGap: CGFloat = 8
    /// Vertical padding of a standard two-line row, and of a block of prose.
    public static let rowVertical: CGFloat = 8
    public static let rowVerticalLoose: CGFloat = 12
}

// MARK: - Reusable chrome

/// Header for a sub-page inside the popover (detail, stats, settings): back
/// chevron, icon, title, optional trailing accessory. Pages replaced `.sheet`s
/// — a sheet is a separate window and a MenuBarExtra window dismisses itself
/// when any other window becomes key — so the way back must live inside the
/// popover.
public struct PageHeader<Icon: View, Accessory: View>: View {
    private let titleKey: String
    private let onBack: () -> Void
    private let icon: Icon
    private let accessory: Accessory

    public init(titleKey: String, onBack: @escaping () -> Void,
                @ViewBuilder icon: () -> Icon,
                @ViewBuilder accessory: () -> Accessory) {
        self.titleKey = titleKey
        self.onBack = onBack
        self.icon = icon()
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(QuietButtonStyle())
            .help(Loc.t("common.back"))
            icon.foregroundStyle(Palette.accent)
            Text(Loc.t(titleKey)).font(Typo.title)
            Spacer()
            accessory
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

extension PageHeader where Accessory == EmptyView {
    public init(titleKey: String, onBack: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.init(titleKey: titleKey, onBack: onBack, icon: icon) { EmptyView() }
    }
}

extension PageHeader where Icon == Image, Accessory == EmptyView {
    public init(titleKey: String, symbol: String, onBack: @escaping () -> Void) {
        self.init(titleKey: titleKey, onBack: onBack) { Image(systemName: symbol) }
    }
}

// MARK: - Modules
//
// The popover is built from modules, borrowed structurally from the macOS
// Control Center: one rounded block per subject, rows of at most two lines
// inside it, a circular glyph on the left carrying on/off state by fill, and
// everything else pushed behind a drill-down. What is deliberately NOT
// borrowed is the system's material and palette — no vibrancy, no
// glassmorphism, no system grays. Ink, paper and the one green do all the
// work; only the geometry and the information budget are Apple's.

/// One Control Center block: a rounded surface holding rows.
///
/// A module has no eyebrow above it. Modules that genuinely need naming carry
/// a `ModuleTitleRow` inside instead, the way the battery panel puts "电池" on
/// its own first line.
public struct Module<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// Fill and a hairline, and no shadow at all.
    ///
    /// Giving each module its own drop shadow is what makes a panel read as a
    /// stack of floating cards rather than one surface. On macOS the popover
    /// *window* carries the only shadow in the picture; everything inside it is
    /// flat and separates by fill contrast against the panel background.
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.moduleFill)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
                    .strokeBorder(Palette.moduleBorder, lineWidth: 1)
            )
    }
}

/// Naming line inside a module. Sentence case at row-title size, not a tracked
/// uppercase eyebrow: it is a heading the user reads, not a label on a filing
/// cabinet.
public struct ModuleTitleRow<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    public init(_ titleKey: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Loc.t(titleKey)
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Typo.rowTitle)
                .foregroundStyle(Palette.text)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.top, Metrics.rowVerticalLoose)
        .padding(.bottom, Metrics.rowVertical)
    }
}

extension ModuleTitleRow where Trailing == EmptyView {
    public init(_ titleKey: String) {
        self.init(titleKey) { EmptyView() }
    }
}

/// Fill of a circular state glyph. Exactly two cases, and that is the point.
///
/// Five were tried once, including a "keep the glyph's own colour" case; the
/// result was four layers arguing and it read as a mistake rather than as a
/// state. Control Center's circle grammar is one layer and binary: solid fill
/// plus a mono glyph, on or off, nothing else. So is this one.
///
/// Top-level rather than nested in `GlyphBadge`, because a type nested inside
/// a generic is parameterised by it: `GlyphBadge<Image>.Fill` and
/// `GlyphBadge<Text>.Fill` would be different types and no caller could store
/// one and pass it to the other.
public enum GlyphFill {
    /// On/live — accent fill, glyph in `onAccent`.
    case on
    /// Off/idle/neutral. Every non-live state uses this, including warnings:
    /// severity is carried by the row's title colour, not by tinting the disc
    /// as well. Two things saying "warning" in two different ways is how a
    /// layout gets loud.
    case off
}

/// Circular state glyph: the Control Center tell where a filled circle means
/// "on" and a flat gray one means "off".
public struct GlyphBadge<Content: View>: View {
    private let fill: GlyphFill
    private let size: CGFloat
    private let content: Content

    public init(_ fill: GlyphFill, size: CGFloat = Metrics.glyph, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.size = size
        self.content = content()
    }

    /// No ring, no border, no shadow — a flat disc. `onAccent` rather than the
    /// white a system badge would use, because white on #2CDB5C fails
    /// contrast and this green is much lighter than the system blue that
    /// convention comes from.
    public var body: some View {
        ZStack {
            Circle().fill(fill == .on ? Palette.accent : Palette.surfaceAlt)
            content.foregroundStyle(fill == .on ? Palette.onAccent : Palette.textSecondary)
        }
        .frame(width: size, height: size)
    }
}

/// A two-line module row: glyph, title, one line of status, optional trailing
/// control. The two-line ceiling is the whole discipline of this layout — if a
/// fact does not fit here it belongs in the drill-down, not squeezed into a
/// third line.
public struct ModuleRow<Glyph: View, Trailing: View, Extra: View>: View {
    private let title: String
    private let subtitle: String?
    private let subtitleTone: Color
    private let subtitleLines: Int
    private let glyph: Glyph
    private let trailing: Trailing
    private let extra: Extra

    /// `subtitleLines` defaults to 1 — the status line of an overview row must
    /// not wrap, or the two-line discipline stops meaning anything. Settings
    /// rows pass 2, because an explanation of what a switch does is worth a
    /// second line and clipping one mid-sentence is worse than the extra
    /// height.
    public init(title: String,
                subtitle: String? = nil,
                subtitleTone: Color = Palette.textTertiary,
                subtitleLines: Int = 1,
                @ViewBuilder glyph: () -> Glyph,
                @ViewBuilder trailing: () -> Trailing,
                @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleTone = subtitleTone
        self.subtitleLines = subtitleLines
        self.glyph = glyph()
        self.trailing = trailing()
        self.extra = extra()
    }

    public var body: some View {
        HStack(spacing: Metrics.rowGlyphGap) {
            glyph
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typo.rowTitle)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.rowSubtitle)
                        .foregroundStyle(subtitleTone)
                        .lineLimit(subtitleLines)
                        .fixedSize(horizontal: false, vertical: subtitleLines > 1)
                }
                extra
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.vertical, Metrics.rowVertical)
    }
}

extension ModuleRow where Extra == EmptyView {
    public init(title: String,
                subtitle: String? = nil,
                subtitleTone: Color = Palette.textTertiary,
                subtitleLines: Int = 1,
                @ViewBuilder glyph: () -> Glyph,
                @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, subtitleTone: subtitleTone,
                  subtitleLines: subtitleLines,
                  glyph: glyph, trailing: trailing) { EmptyView() }
    }
}

extension ModuleRow where Trailing == EmptyView, Extra == EmptyView {
    public init(title: String,
                subtitle: String? = nil,
                subtitleTone: Color = Palette.textTertiary,
                subtitleLines: Int = 1,
                @ViewBuilder glyph: () -> Glyph) {
        self.init(title: title, subtitle: subtitle, subtitleTone: subtitleTone,
                  subtitleLines: subtitleLines,
                  glyph: glyph) { EmptyView() } extra: { EmptyView() }
    }
}

/// Hairline between module rows, inset to the text column.
public struct RowDivider: View {
    private let inset: CGFloat

    public init(inset: CGFloat = Metrics.rowDividerInset) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Read-only progress rail — the Control Center slider's shape used to show a
/// proportion rather than to set one.
public struct MeterBar: View {
    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = min(max(fraction, 0), 1)
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceAlt)
                Capsule()
                    .fill(tint)
                    // A zero-width capsule reads as "no bar drawn" rather than
                    // "nothing used yet", so keep a visible nub at 0%.
                    .frame(width: max(3, proxy.size.width * fraction))
            }
        }
        .frame(height: 4)
    }
}

/// Press feedback for a whole row that acts as a link into a sub-page. No fill
/// of its own: the row already sits on a surface, and a second background would
/// put a box inside a box.
public struct RowButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Status pill: small caps, tight tracking, tinted fill + 35% border.
public struct Pill: View {
    public enum Tone { case neutral, positive, warning, danger, accent }

    private let text: String
    private let tone: Tone
    /// Small caps is the house style, but literal values (key signatures,
    /// thresholds) must be shown exactly as they are.
    private let uppercased: Bool

    public init(_ text: String, tone: Tone = .neutral, uppercased: Bool = true) {
        self.text = text
        self.tone = tone
        self.uppercased = uppercased
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Palette.textTertiary
        case .positive: return Palette.positive
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        case .accent: return Palette.accentInk
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return Palette.surfaceAlt
        case .positive: return Palette.positiveSoft
        case .warning: return Palette.warningSoft
        case .danger: return Palette.dangerSoft
        case .accent: return Palette.accentSoft
        }
    }

    private var stroke: Color {
        tone == .neutral ? Palette.border : foreground.opacity(0.35)
    }

    public var body: some View {
        Text(uppercased ? text.uppercased() : text)
            .font(uppercased ? Typo.captionStrong : Typo.numeric)
            .kerning(0.4)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
            .lineLimit(1)
    }
}

/// Primary action: ink fill — the green accent is for states, not chrome.
public struct AccentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.bodyStrong)
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Palette.inkHover : Palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
            .offset(y: configuration.isPressed ? 1 : 0)
            .contentShape(Rectangle())
    }
}

/// Secondary action: surface fill and a strong border, no ink slab. A page
/// gets exactly one ink-filled button, so anything else that needs to look
/// like a button uses this instead of competing for the eye.
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.bodyStrong)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Palette.surfaceAlt : Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

/// Ghost/tertiary action: no border, muted ink, surfaceAlt on press.
public struct QuietButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.captionStrong)
            .foregroundStyle(configuration.isPressed ? Palette.text : Palette.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(configuration.isPressed ? Palette.surfaceAlt : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Type eraser for picking a button style at runtime ("selected vs not")
/// without if/else-ing the whole view.
public struct AnyButtonStyle: ButtonStyle {
    private let base: any ButtonStyle

    public init(_ base: any ButtonStyle) {
        self.base = base
    }

    public func makeBody(configuration: Configuration) -> some View {
        AnyView(base.makeBody(configuration: configuration))
    }
}
