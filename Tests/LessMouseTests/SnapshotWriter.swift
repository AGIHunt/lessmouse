import AppKit
import SwiftUI

/// Writes review PNGs of a SwiftUI view through AppKit's own drawing path.
///
/// `ImageRenderer` cannot rasterise NSView-backed controls — every `Toggle`,
/// `Picker` and `Menu` comes out as a placeholder square — and a screenshot
/// with unexplained artifacts in it cannot be judged. Hosting the view in a
/// real (if offscreen) window and asking AppKit to cache its display draws
/// the genuine controls.
///
/// Set `LM_SNAPSHOT_DIR` to export PNGs for design review.
@MainActor
enum SnapshotWriter {
    static var directory: String? {
        ProcessInfo.processInfo.environment["LM_SNAPSHOT_DIR"]
    }

    static func write(_ view: some View, width: CGFloat, name: String) {
        guard let directory else { return }

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 100)

        // Controls only draw once the view belongs to a window. Park it far
        // off any display and make it key there: the process never activates,
        // so nothing steals focus from whoever runs the tests.
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        // Two passes: first give the hosting view a real width, then read
        // the height that width produced.
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        let size = NSSize(width: width, height: max(fitted.height, 1))
        window.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard size.height > 1,
              let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let root = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? png.write(to: root.appendingPathComponent("\(name).png"))
    }
}
