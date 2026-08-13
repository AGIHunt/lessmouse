import AppKit

/// The product mark in the menu bar.
///
/// The image is an alpha-only template: the system re-colors it for the light
/// or dark menu bar, exactly as it does its own icons, so the app never has to
/// guess. `assets/MenuBarIcon.svg` is the source of truth; the PNG at 18pt
/// (@1x/@2x) is derived from it (see assets/icon-derivation.md).
public enum ProductMark {
    /// 18pt is the slot macOS gives a menu bar glyph. A template image larger
    /// than that is scaled down and visually shrinks next to its neighbours.
    static let size: CGFloat = 18

    public static var menuBar: NSImage? {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: size, height: size)
        return image
    }
}
