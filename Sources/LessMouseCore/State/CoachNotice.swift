import Foundation

/// A moment worth interrupting for, briefly: a card just arrived, or a card
/// the user was taught has just been put to use.
///
/// The inbox and the menu bar dot already *record* both facts, but only for
/// someone who opens the popover. A notice is the part that reaches a user
/// who doesn't — fired once, at the transition, never re-fired for a state
/// that merely persists.
public enum CoachNotice: Equatable, Sendable {
    /// A card became unread: first time, or again after its cooldown.
    case newSuggestion(ruleID: String)
    /// The taught shortcut was pressed — the card flipped to adopted.
    case adopted(ruleID: String)

    public var ruleID: String {
        switch self {
        case .newSuggestion(let id), .adopted(let id): return id
        }
    }
}
