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
    // Bold at 16pt in the 18pt slot. Regular weight at 14.5pt read as a
    // thin line next to the blocky icons it sits beside — menu bar neighbours
    // are mostly solid fills, so the mark earns its place with weight.
    let attributed = CFAttributedStringCreateMutable(nil, 0)!
    CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), "\u{2318}" as CFString)
    let range = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
    CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName,
                                    CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 16 * scale, nil))
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
    // Optical-bounds centering, minX/minY included — halving alone leaves
    // the glyph offset by whatever its origin insets are.
    context.textPosition = CGPoint(
        x: cap.midX - bounds.width / 2 - bounds.minX,
        y: cap.midY - bounds.height / 2 - bounds.minY)
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

// MARK: - Structural check
//
// Both icons are font-rendered (CoreText), so byte-exact comparison is not
// stable across machines — GitHub's runners rasterize Helvetica Neue
// slightly differently than a dev laptop, and the first CI run failed on
// exactly that. The check therefore compares structure: same pixel
// dimensions, and alpha maps that agree within tolerance after
// downsampling. A stale committed PNG (someone changed the geometry without
// regenerating) still fails loudly; a different machine's antialiasing
// does not.

func alphaMap(of png: Data, sample: Int) -> (size: CGSize, coverage: Double, map: [Double])? {
    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

    let width = image.width
    let height = image.height
    let context = CGContext(data: nil, width: sample, height: sample,
                            bitsPerComponent: 8, bytesPerRow: sample * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: sample, height: sample))

    guard let data = context.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: sample * sample * 4)
    var map = [Double]()
    map.reserveCapacity(sample * sample)
    var covered = 0
    for i in 0..<(sample * sample) {
        let alpha = Double(pixels[i * 4 + 3]) / 255
        map.append(alpha)
        if alpha > 0.35 { covered += 1 }
    }
    return (CGSize(width: width, height: height),
            Double(covered) / Double(sample * sample),
            map)
}

/// True when both PNGs describe the same picture within tolerance.
func structurallyEqual(_ committed: Data, _ fresh: Data, name: String) -> Bool {
    let sample = 64
    guard let committedMap = alphaMap(of: committed, sample: sample),
          let freshMap = alphaMap(of: fresh, sample: sample) else {
        print("✗ \(name): cannot decode for comparison")
        return false
    }
    guard committedMap.size == freshMap.size else {
        print("✗ \(name): pixel size \(committedMap.size) ≠ \(freshMap.size) — run scripts/make-icons.swift")
        return false
    }
    // Geometry changes move ink coverage far more than font rasterization
    // does; 4pp separates the two comfortably.
    let coverageDelta = abs(committedMap.coverage - freshMap.coverage)
    guard coverageDelta <= 0.04 else {
        print(String(format: "✗ %@: ink coverage %.1f%% vs %.1f%% — run scripts/make-icons.swift",
                     name, committedMap.coverage * 100, freshMap.coverage * 100))
        return false
    }
    let meanDiff = zip(committedMap.map, freshMap.map).reduce(0.0) { $0 + abs($1.0 - $1.1) }
        / Double(committedMap.map.count)
    guard meanDiff <= 0.08 else {
        print(String(format: "✗ %@: alpha maps differ by %.3f mean — run scripts/make-icons.swift",
                     name, meanDiff))
        return false
    }
    return true
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
        if structurallyEqual(onDiskMenuBar, menuBar, name: "MenuBarIcon.png") {
            print("✓ MenuBarIcon.png matches the geometry")
        } else {
            failures += 1
        }
        if structurallyEqual(onDiskAppIcon, appIcon, name: "AppIcon-1024.png") {
            print("✓ AppIcon-1024.png matches the geometry")
        } else {
            failures += 1
        }
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
