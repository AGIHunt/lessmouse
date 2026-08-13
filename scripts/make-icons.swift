// Derives the binary art from the SVG sources' geometry.
//
// Why not render the SVGs directly? Keeping the build free of external tools
// (rsvg, Inkscape, qlmanage roundtrips) means `make-app.sh` works on a clean
// macOS + Swift toolchain and nothing else. The shapes are four lines of
// geometry, so the duplication is small and the SVGs stay the readable
// reference for humans.
//
// Usage: swift scripts/make-icons.swift [--check]
//   --check: re-derive in memory and compare bytes; exits non-zero if the
//   committed art no longer matches the geometry (CI guard).

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - PNG writing

func writePNG(_ image: CGImage, size: Int, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-icons", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot create PNG destination \(url)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make-icons", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "cannot finalize PNG \(url)"])
    }
}

func makeContext(pixels: Int) -> CGContext {
    CGContext(data: nil, width: pixels, height: pixels,
              bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// MARK: - Menu bar mark (alpha-only template)

/// The ⌘ mark at 18pt. The first design was a keycap outline with a small
/// notification dot — at menu bar size the outline read as an empty box, so
/// the mark is now the command glyph itself, matching the app icon. (The
/// unread dot is a SwiftUI overlay in App.swift, not part of this art.)
///
/// Alpha only: the fill color is irrelevant, the glyph shape is the icon.
func drawMenuBarMark(into context: CGContext, scale: CGFloat) {
    // 14.5pt of glyph inside the 18pt slot: the optical size SF Symbols
    // occupy next door. Bigger than that and ⌘ crowds the neighbours.
    let attributed = CFAttributedStringCreateMutable(nil, 0)!
    CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), "\u{2318}" as CFString)
    let range = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
    CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName,
                                    CTFontCreateWithName("HelveticaNeue" as CFString, 14.5 * scale, nil))
    CFAttributedStringSetAttribute(attributed, range, kCTForegroundColorAttributeName,
                                    CGColor(gray: 1, alpha: 1))
    let line = CTLineCreateWithAttributedString(attributed)

    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: (18 * scale - bounds.width) / 2 - bounds.minX,
        y: (18 * scale - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line, context)
}

func menuBarIconPNG() throws -> Data {
    let pixels = 36  // 18pt @2x
    let context = makeContext(pixels: pixels)
    context.setFillColor(CGColor(gray: 0, alpha: 0))
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    drawMenuBarMark(into: context, scale: 2)
    let image = context.makeImage()!

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-icons", code: 3)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

// MARK: - App icon

/// Paper field, ink keycap, white ⌘, one green dot — the house language in
/// one 1024 square.
func drawAppIcon(into context: CGContext, size: CGFloat) {
    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    context.setFillColor(color(0xF7F8F7))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    let unit = size / 1024
    let cap = CGRect(x: 202 * unit, y: 272 * unit, width: 620 * unit, height: 480 * unit)
    let capPath = CGPath(roundedRect: cap, cornerWidth: 120 * unit, cornerHeight: 120 * unit, transform: nil)
    context.addPath(capPath)
    context.setFillColor(color(0x0B0F0C))
    context.fillPath()

    // The ⌘ glyph through CoreText — the system font owns this shape.
    let glyph = "\u{2318}" as CFString
    let attributed = CFAttributedStringCreateMutable(nil, 0)!
    CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), glyph)
    let glyphRange = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
    CFAttributedStringSetAttribute(attributed, glyphRange, kCTFontAttributeName,
                                    CTFontCreateWithName("HelveticaNeue" as CFString, 430 * unit, nil))
    CFAttributedStringSetAttribute(attributed, glyphRange, kCTForegroundColorAttributeName,
                                    color(0xFFFFFF))
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: cap.midX - bounds.width / 2,
        y: cap.midY - bounds.height / 2)
    CTLineDraw(line, context)

    // The green: exactly one dot, exactly where the accent always lives.
    context.setFillColor(color(0x2CDB5C))
    context.fillEllipse(in: CGRect(x: 790 * unit - 96 * unit, y: 254 * unit - 96 * unit,
                                   width: 192 * unit, height: 192 * unit))
}

func appIconPNG() throws -> Data {
    let pixels = 1024
    let context = makeContext(pixels: pixels)
    drawAppIcon(into: context, size: CGFloat(pixels))
    let image = context.makeImage()!

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-icons", code: 4)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

// MARK: - main

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let check = CommandLine.arguments.contains("--check")

var failures = 0

let menuBarURL = repoRoot.appendingPathComponent("Sources/LessMouseCore/Resources/MenuBarIcon.png")
let appIconURL = repoRoot.appendingPathComponent("assets/AppIcon-1024.png")

do {
    let menuBar = try menuBarIconPNG()
    let appIcon = try appIconPNG()
    if check {
        let onDiskMenuBar = (try? Data(contentsOf: menuBarURL)) ?? Data()
        let onDiskAppIcon = (try? Data(contentsOf: appIconURL)) ?? Data()
        if onDiskMenuBar != menuBar {
            print("✗ MenuBarIcon.png does not match the geometry — run scripts/make-icons.swift")
            failures += 1
        }
        if onDiskAppIcon != appIcon {
            print("✗ AppIcon-1024.png does not match the geometry — run scripts/make-icons.swift")
            failures += 1
        }
        if failures == 0 { print("✓ derived art matches the geometry") }
    } else {
        try menuBar.write(to: menuBarURL)
        try appIcon.write(to: appIconURL)
        print("✓ wrote \(menuBarURL.path)")
        print("✓ wrote \(appIconURL.path)")
    }
} catch {
    FileHandle.standardError.write("make-icons failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

exit(failures == 0 ? 0 : 1)
