import Foundation

/// One detectable habit: "N presses of this signature family within T
/// seconds". Families let ← and → mix — a user correcting position with
/// ←←→→ is doing one thing, not two.
public struct PatternSpec: Identifiable, Hashable, Codable {
    public let id: String
    public let signatures: Set<String>
    public let count: Int
    public let window: TimeInterval

    public init(id: String, signatures: Set<String>, count: Int, window: TimeInterval) {
        self.id = id
        self.signatures = signatures
        self.count = count
        self.window = window
    }
}

/// The v1 rule book. Thresholds are daily-experience numbers, not research:
/// five backspaces in two seconds is unmistakably word-fixing by hand, while
/// three would fire on ordinary typing corrections.
public enum PatternLibrary {
    public static let defaults: [PatternSpec] = [
        PatternSpec(id: "backspace-burst", signatures: ["backspace"], count: 5, window: 2),
        PatternSpec(id: "harrow-burst", signatures: ["left", "right"], count: 4, window: 2),
        PatternSpec(id: "shift-arrow-burst", signatures: ["shift+left", "shift+right"], count: 4, window: 2),
        PatternSpec(id: "varrow-burst", signatures: ["up", "down"], count: 12, window: 3),
    ]
}
