import Foundation
import SwiftUI

/// Scaffold skeleton of the app state — the pipeline (ingest → filter →
/// store/detect/suggest) is filled in by the detection step; only what the
/// menu bar label and popover chrome need is here.
@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var unreadCount: Int = 0
    /// Placeholder type until the suggestion model exists.
    @Published public private(set) var celebration: String?

    public var language: String? { Loc.language }

    public init() {}

    public func popoverDidOpen() {}
    public func popoverDidClose() {}
}
