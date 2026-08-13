import Foundation

/// Turns an EngineContext plus persisted states into card transitions.
///
/// The rules, in order of authority:
///
/// - **Dismissed is forever.** evaluate() skips it; nothing resurrects it.
/// - **Adopted is forever** too (celebration happens once, on the transition).
/// - A dormant/read rule whose trigger is met becomes unread — that is the
///   menu bar dot. A rule already unread stays unread; re-triggering only
///   refreshes its "last nagged" stamp so the cooldown clock is honest.
/// - A read-but-not-adopted rule waits `cooldownDays` before it may nag
///   again. Coaching that outpaces patience trains the reflex of dismissing.
public final class SuggestionEngine {
    private let rules: [SuggestionRule]
    private let calendar: Calendar
    private let now: () -> Date

    public init(rules: [SuggestionRule],
                calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init) {
        self.rules = rules
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Evaluate

    public func evaluate(_ context: EngineContext,
                         states: inout [String: SuggestionState]) -> [SuggestionChange] {
        var changes: [SuggestionChange] = []
        for rule in rules where isTriggered(rule, context: context) {
            let status = states[rule.id]?.status ?? .dormant
            switch status {
            case .dismissed, .adopted:
                continue

            case .dormant:
                states[rule.id] = SuggestionState(
                    ruleID: rule.id,
                    status: .unread,
                    generatedAt: now(),
                    adoptionBaseline: baseline(for: rule, context: context),
                    lastNotifiedDayKey: context.dayKey)
                changes.append(.becameUnread(rule.id))

            case .unread:
                if var state = states[rule.id] {
                    state.lastNotifiedDayKey = context.dayKey
                    states[rule.id] = state
                }

            case .read:
                guard let state = states[rule.id],
                      shouldRenag(state, dayKey: context.dayKey, cooldownDays: rule.cooldownDays)
                else { continue }
                states[rule.id]?.status = .unread
                states[rule.id]?.lastNotifiedDayKey = context.dayKey
                changes.append(.promotedAgain(rule.id))
            }
        }
        return changes
    }

    private func isTriggered(_ rule: SuggestionRule, context: EngineContext) -> Bool {
        switch rule.trigger {
        case .patternBursts(let id, let dailyMinimum):
            return (context.patternHitsToday[id] ?? 0) >= dailyMinimum

        case .comboUsage(let signatures, let dailyMinimum):
            let total = signatures.reduce(0) { $0 + (context.comboCountsToday[$1] ?? 0) }
            return total >= dailyMinimum

        case .unusedWhileActive(let signature, let activity, let minimumDays):
            guard (context.comboCountsAllTime[signature] ?? 0) == 0 else { return false }
            switch activity {
            case .browserUse: return context.browserActiveDays >= minimumDays
            case .multiAppUse: return context.multiAppActiveDays >= minimumDays
            case .appSwitching: return false
            }

        case .activityShare(let signature, let activity, let dailyMinimum, let maxShare):
            let volume: Int
            switch activity {
            case .browserUse, .multiAppUse: return false
            case .appSwitching: volume = context.appSwitchesToday
            }
            guard volume >= dailyMinimum else { return false }
            let viaShortcut = context.comboCountsToday[signature] ?? 0
            return Double(viaShortcut) < maxShare * Double(volume)
        }
    }

    private func baseline(for rule: SuggestionRule, context: EngineContext) -> [String: Int] {
        var baseline: [String: Int] = [:]
        for signature in rule.watchForAdoption {
            baseline[signature] = context.comboCountsToday[signature] ?? 0
        }
        return baseline
    }

    private func shouldRenag(_ state: SuggestionState,
                             dayKey: String,
                             cooldownDays: Int) -> Bool {
        guard let last = state.lastNotifiedDayKey else { return true }
        return daysBetween(last, dayKey) >= cooldownDays
    }

    /// Calendar-day distance between two day keys (negative if `to` is
    /// before `from`, which callers treat as "still cooling down").
    private func daysBetween(_ from: String, _ to: String) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let fromDate = formatter.date(from: from),
              let toDate = formatter.date(from: to) else { return .max }
        return calendar.dateComponents([.day], from: fromDate, to: toDate).day ?? .max
    }

    // MARK: - Adoption

    /// Event path: the pipeline just counted `signature`, bringing today to
    /// `todayCount`. If that crosses a live card's baseline, the card is
    /// adopted. Returns the rule worth celebrating.
    public func onComboObserved(signature: String,
                                todayCount: Int,
                                states: inout [String: SuggestionState]) -> String? {
        for rule in rules where rule.watchForAdoption.contains(signature) {
            guard let state = states[rule.id],
                  state.status == .unread || state.status == .read else { continue }
            let baseline = state.adoptionBaseline[signature] ?? 0
            if todayCount > baseline {
                states[rule.id]?.status = .adopted
                states[rule.id]?.celebrated = false
                return rule.id
            }
        }
        return nil
    }

    // MARK: - User actions

    public func markRead(_ ruleID: String, states: inout [String: SuggestionState]) {
        guard states[ruleID]?.status == .unread else { return }
        states[ruleID]?.status = .read
    }

    public func dismiss(_ ruleID: String, states: inout [String: SuggestionState]) {
        states[ruleID]?.status = .dismissed
    }
}
