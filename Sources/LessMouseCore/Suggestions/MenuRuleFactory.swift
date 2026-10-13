import Foundation

/// The coaching cards that can only exist at runtime.
///
/// Every card in RuleLibrary names a shortcut somebody already knew to look
/// for. This one teaches a shortcut *the user's own apps* know: LessMouse
/// cannot ship a table of every menu command on the Mac — it would be wrong
/// the week after it was written, and it would only ever cover the apps its
/// author happened to open. So instead of a table, the card is built when the
/// evidence shows up: a signature read out of a live menu bar becomes a
/// `SuggestionRule` with the same shape as any other, and from there the
/// engine, the inbox, the celebration and the adoption baseline treat it
/// exactly like a rule that shipped.
///
/// The id is derived from the signature (`menu-click:cmd+s`), so the card for
/// a command keeps its state — read, adopted, dismissed — across relaunches,
/// and two different commands never collide.
public enum MenuRuleFactory {
    /// Distinguishes a generated card's id from the book's, which also means
    /// "every suggestion state with this prefix came from here".
    public static let idPrefix = "menu-click:"

    /// Clicks in one day before a command is worth mentioning. Three is the
    /// line at which the mouse is a habit rather than a slip; a single click
    /// is someone exploring a menu.
    public static let dailyMinimum = 3

    /// How much of the clicking the keyboard may already cover. At the
    /// threshold this allows one keyboard use out of every three clicks, so a
    /// user who knows the shortcut and sometimes reaches for the mouse anyway
    /// is left alone.
    public static let maxKeyboardShare = 0.34

    /// Cards on offer at once. The inbox is a reading list, not a feed; past
    /// three the numbers stop being worth reading.
    public static let limit = 3

    public static func id(for signature: String) -> String {
        idPrefix + signature
    }

    /// Which signatures are worth a card right now, most-clicked first, ties
    /// broken by signature so the order never wobbles between evaluations.
    ///
    /// `keyboardUses` is today's signature counts from the keyboard path. It
    /// enters here rather than only in the engine's trigger because the cap
    /// also has to leave room: a command the user is *already* pressing should
    /// not take one of the three slots from one they are not.
    public static func candidates(menuClicks: [String: Int],
                                  keyboardUses: [String: Int] = [:],
                                  dailyMinimum: Int = Self.dailyMinimum,
                                  maxKeyboardShare: Double = Self.maxKeyboardShare,
                                  limit: Int = Self.limit) -> [String] {
        menuClicks
            .filter { signature, clicks in
                guard clicks >= dailyMinimum,
                      // A keycap we cannot draw cannot be taught.
                      let shortcut = MenuShortcut(signature: signature),
                      // Nor can a gesture the keyboard half would never record.
                      // A signature that fails this is typing, and teaching it
                      // would name a bare key the user cannot adopt — which is
                      // also what retires the ones an earlier build wrote.
                      shortcut.isRecordableGesture
                else { return false }
                let presses = keyboardUses[signature] ?? 0
                return Double(presses) <= maxKeyboardShare * Double(clicks)
            }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)
    }

    /// The card for one signature, or nil when nothing could be drawn for it
    /// (an unmapped keycode, or a signature that is not a shortcut at all).
    ///
    /// Stateless on purpose: the engine asks this from a bare signature on the
    /// event path, where there is no EngineContext to hand.
    public static func rule(for signature: String,
                            dailyMinimum: Int = Self.dailyMinimum,
                            maxKeyboardShare: Double = Self.maxKeyboardShare) -> SuggestionRule? {
        guard let shortcut = MenuShortcut(signature: signature),
              shortcut.isRecordableGesture
        else { return nil }
        return SuggestionRule(
            id: id(for: signature),
            trigger: .menuCommandClicks(signature: signature,
                                        dailyMinimum: dailyMinimum,
                                        maxKeyboardShare: maxKeyboardShare),
            watchForAdoption: [signature],
            titleKey: "rule.menuClick.title",
            bodyKey: "rule.menuClick.body",
            summaryKey: "rule.menuClick.summary",
            keyCaps: [shortcut.keyCaps],
            symbol: "cursorarrow.click",
            cooldownDays: 5
        )
    }

    /// Cards for several signatures, in the given order.
    public static func rules(for signatures: [String]) -> [SuggestionRule] {
        signatures.compactMap { rule(for: $0) }
    }
}
