import Foundation

/// The coaching book. Data, not code: every card names its strings keys,
/// its trigger, its keycaps, and how adoption will be recognized.
public enum RuleLibrary {
    public static let all: [SuggestionRule] = [
        SuggestionRule(
            id: "delete-by-word",
            trigger: .patternBursts(id: "backspace-burst", dailyMinimum: 3),
            watchForAdoption: ["opt+backspace", "cmd+backspace"],
            titleKey: "rule.deleteByWord.title",
            bodyKey: "rule.deleteByWord.body",
            summaryKey: "rule.deleteByWord.summary",
            keyCaps: [[.modifier(.option), "⌫"], [.modifier(.command), "⌫"]],
            symbol: "delete.left",
            cooldownDays: 3
        ),
        SuggestionRule(
            id: "hop-by-word",
            trigger: .patternBursts(id: "harrow-burst", dailyMinimum: 3),
            watchForAdoption: ["opt+left", "opt+right", "cmd+left", "cmd+right"],
            titleKey: "rule.hopByWord.title",
            bodyKey: "rule.hopByWord.body",
            summaryKey: "rule.hopByWord.summary",
            keyCaps: [[.modifier(.option), "←"], [.modifier(.option), "→"],
                      [.modifier(.command), "←"], [.modifier(.command), "→"]],
            symbol: "arrow.left.arrow.right",
            cooldownDays: 3
        ),
        SuggestionRule(
            id: "select-by-word",
            trigger: .patternBursts(id: "shift-arrow-burst", dailyMinimum: 2),
            watchForAdoption: ["opt+shift+left", "opt+shift+right", "cmd+shift+right"],
            titleKey: "rule.selectByWord.title",
            bodyKey: "rule.selectByWord.body",
            summaryKey: "rule.selectByWord.summary",
            keyCaps: [[.modifier(.shift), .modifier(.option), "←"],
                      [.modifier(.shift), .modifier(.option), "→"],
                      [.modifier(.shift), .modifier(.command), "→"]],
            symbol: "textformat",
            cooldownDays: 4
        ),
        SuggestionRule(
            id: "doc-start-end",
            trigger: .patternBursts(id: "varrow-burst", dailyMinimum: 2),
            watchForAdoption: ["cmd+up", "cmd+down"],
            titleKey: "rule.docStartEnd.title",
            bodyKey: "rule.docStartEnd.body",
            summaryKey: "rule.docStartEnd.summary",
            keyCaps: [[.modifier(.command), "↑"], [.modifier(.command), "↓"]],
            symbol: "arrow.up.arrow.down",
            cooldownDays: 5
        ),
        SuggestionRule(
            id: "home-end-mac",
            trigger: .comboUsage(signatures: ["home", "end"], dailyMinimum: 3),
            watchForAdoption: ["cmd+left", "cmd+right"],
            titleKey: "rule.homeEndMac.title",
            bodyKey: "rule.homeEndMac.body",
            summaryKey: "rule.homeEndMac.summary",
            keyCaps: [[.modifier(.command), "←"], [.modifier(.command), "→"]],
            symbol: "arrow.right.to.line",
            cooldownDays: 5
        ),
        SuggestionRule(
            id: "same-app-windows",
            trigger: .unusedWhileActive(signature: "cmd+grave",
                                        activity: .multiAppUse,
                                        minimumDays: 3),
            watchForAdoption: ["cmd+grave"],
            titleKey: "rule.sameAppWindows.title",
            bodyKey: "rule.sameAppWindows.body",
            summaryKey: "rule.sameAppWindows.summary",
            keyCaps: [[.modifier(.command), "`"]],
            symbol: "macwindow.on.rectangle",
            cooldownDays: 30
        ),
        SuggestionRule(
            id: "emacs-keys",
            trigger: .patternBursts(id: "harrow-burst", dailyMinimum: 6),
            watchForAdoption: ["ctrl+a", "ctrl+e"],
            titleKey: "rule.emacsKeys.title",
            bodyKey: "rule.emacsKeys.body",
            summaryKey: "rule.emacsKeys.summary",
            keyCaps: [[.modifier(.control), "A"], [.modifier(.control), "E"],
                      [.modifier(.control), "N"], [.modifier(.control), "P"]],
            symbol: "text.cursor",
            cooldownDays: 30
        ),
        SuggestionRule(
            id: "app-switching",
            trigger: .activityShare(signature: "cmd+tab",
                                    activity: .appSwitching,
                                    dailyMinimum: 15,
                                    maxShare: 0.2),
            watchForAdoption: ["cmd+tab"],
            titleKey: "rule.appSwitching.title",
            bodyKey: "rule.appSwitching.body",
            summaryKey: "rule.appSwitching.summary",
            keyCaps: [[.modifier(.command), "⇥"]],
            symbol: "arrow.2.squarepath",
            cooldownDays: 30
        ),
        SuggestionRule(
            id: "tab-switching",
            trigger: .unusedWhileActive(signature: "ctrl+tab",
                                        activity: .browserUse,
                                        minimumDays: 3),
            watchForAdoption: ["ctrl+tab", "ctrl+shift+tab"],
            titleKey: "rule.tabSwitching.title",
            bodyKey: "rule.tabSwitching.body",
            summaryKey: "rule.tabSwitching.summary",
            keyCaps: [[.modifier(.control), "⇥"],
                      [.modifier(.control), .modifier(.shift), "⇥"]],
            symbol: "chevron.left.chevron.right",
            cooldownDays: 30
        ),
    ]

    public static func rule(withID id: String) -> SuggestionRule? {
        all.first { $0.id == id }
    }
}
