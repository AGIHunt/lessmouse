// Composes the GitHub social preview (1280×640) in the house language:
// clean paper, one ink keycap with the white ⌘, one green dot, ink wordmark.
//
// Usage: swift scripts/make-social-preview.swift   → assets/SocialPreview.png

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let width = 1280
let height = 640

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws `string` with its optical bounds CENTERED on `center` — for
/// single glyphs placed inside a shape (the ⌘ in the keycap).
func drawGlyphCentered(_ string: String, font: String, size: CGFloat,
                       at center: CGPoint, color: CGColor) {
    let line = makeLine(string, font: font, size: size, color: color)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: center.x - bounds.width / 2 - bounds.minX,
        y: center.y - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, context)
}

/// Draws `string` with its optical TOP-LEFT at `topLeft` — for text blocks
/// laid out by hand. (One draw function used to do both jobs and its
/// semantics flip mid-flight is exactly how the wordmark ended up on top
/// of the keycap.)
func drawText(_ string: String, font: String, size: CGFloat,
              at topLeft: CGPoint, color: CGColor) {
    let line = makeLine(string, font: font, size: size, color: color)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: topLeft.x - bounds.minX,
        y: topLeft.y - bounds.minY)
    CTLineDraw(line, context)
}

private func makeLine(_ string: String, font: String, size: CGFloat,
                      color: CGColor) -> CTLine {
    let attributed = CFAttributedStringCreateMutable(nil, 0)!
    CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), string as CFString)
    let range = CFRange(location: 0, length: CFAttributedStringGetLength(attributed))
    CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName,
                                    CTFontCreateWithName(font as CFString, size, nil))
    CFAttributedStringSetAttribute(attributed, range, kCTForegroundColorAttributeName, color)
    return CTLineCreateWithAttributedString(attributed)
}

let context = CGContext(data: nil, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Paper field.
context.setFillColor(color(0xF7F8F7))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

// The keycap, scaled to sit large on the left (app-icon geometry × 0.55).
let unit: CGFloat = 0.55
let cap = CGRect(x: 140, y: 640 - 500, width: 620 * unit, height: 480 * unit)
context.addPath(CGPath(roundedRect: cap, cornerWidth: 120 * unit, cornerHeight: 120 * unit, transform: nil))
context.setFillColor(color(0x0B0F0C))
context.fillPath()

// ⌘ truly centered in the cap, white.
drawGlyphCentered("\u{2318}", font: "HelveticaNeue", size: 240 * unit,
                  at: CGPoint(x: cap.midX, y: cap.midY),
                  color: color(0xFFFFFF))

// The green: exactly one dot, top-right of the cap.
context.setFillColor(color(0x2CDB5C))
context.fillEllipse(in: CGRect(x: cap.maxX - 96 * unit, y: cap.maxY - 96 * unit,
                               width: 192 * unit, height: 192 * unit))

// Wordmark and tagline, top-left anchored, clear of the cap (right edge at
// x=481): everything starts at x=560, and the block is vertically centered
// on the canvas.
drawText("LessMouse", font: "HelveticaNeue-Bold", size: 96,
         at: CGPoint(x: 560, y: 410), color: color(0x0B0F0C))
drawText("Your keyboard coach on the menu bar.", font: "HelveticaNeue", size: 34,
         at: CGPoint(x: 564, y: 310), color: color(0x6D766E))
drawText("100% local · zero network · open source", font: "HelveticaNeue", size: 30,
         at: CGPoint(x: 564, y: 250), color: color(0x6D766E))

let image = context.makeImage()!
let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("assets/SocialPreview.png")
let output = NSMutableData()
let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
try! (output as Data).write(to: url)
print("✓ wrote \(url.path)")
