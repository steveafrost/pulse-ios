import Foundation

/// Validates what an on-device model said about placement.
///
/// **Why this is not inside `OnDevicePlacementAdvisor`.** The advisor needs iOS 26
/// because it talks to `SystemLanguageModel`. This validation does not: it is pure
/// arithmetic over `PlacementAdvice` and string work. Keeping it here means the
/// rules that decide whether a model's answer is trustworthy can be tested on the
/// macOS/iOS floor, in CI, and on a machine with no Apple Intelligence at all --
/// which is the only way the guardrails get real coverage instead of being exercised
/// by hand on one device.
///
/// Every rule below exists because a model can be confidently wrong. None of them
/// is a formatting preference.
public enum PlacementValidation {
    /// The longest reason shown on a card. A runaway sentence would wreck the row.
    public static let maxReasonLength = 90

    /// One raw answer from the model, before it has been checked against anything.
    ///
    /// Deliberately dumb: an index, a bucket string that may be nonsense, and a
    /// reason string that may be empty. Turning it into something safe is this
    /// type's whole job.
    public struct RawVerdict: Sendable, Hashable {
        public var index: Int
        public var horizon: String
        public var reason: String

        public init(index: Int, horizon: String, reason: String) {
            self.index = index
            self.horizon = horizon
            self.reason = reason
        }
    }

    /// Turns raw verdicts into advice that is safe to apply.
    ///
    /// Dropped, with the reason:
    ///   * an index that names no candidate -- it is about no real item;
    ///   * a second verdict for the same index -- the first one stands, so the
    ///     result cannot depend on the model's ordering;
    ///   * a bucket that is not one of the four;
    ///   * `niceToKnow` -- that is a classification decision (is this `fyi`?), not a
    ///     placement one, and honouring it would hide the item;
    ///   * a verdict identical to the rule -- there is nothing to apply;
    ///   * a move further than one bucket toward Now (see `isReachable`).
    public static func sanitize(
        _ verdicts: [RawVerdict],
        against batch: [PlacementCandidate]
    ) -> [PlacementAdvice] {
        let byIndex = Dictionary(uniqueKeysWithValues: batch.map { ($0.index, $0) })
        var seen = Set<Int>()
        var advice: [PlacementAdvice] = []

        for verdict in verdicts {
            guard let candidate = byIndex[verdict.index], !seen.contains(verdict.index) else { continue }
            seen.insert(verdict.index)

            guard let horizon = Horizon(rawValue: verdict.horizon.lowercased()) else { continue }
            // `niceToKnow` is not a placement: it is a claim that the item is
            // informational, and honouring it would take a real task off the board.
            guard horizon != .niceToKnow, horizon != candidate.ruleHorizon, isReachable(
                horizon,
                from: candidate.ruleHorizon
            ) else { continue }

            advice.append(PlacementAdvice(
                itemID: candidate.itemID,
                horizon: horizon,
                reason: bound(verdict.reason, horizon: horizon)
            ))
        }
        return advice
    }

    /// How far a model may move an item in one step.
    ///
    /// Deferring is always allowed: it can only reduce noise, which is the whole
    /// point. Promoting is capped at one bucket, so a model cannot pull something
    /// weeks away into Now on the strength of its title alone. The asymmetry is
    /// deliberate -- being wrong upward displaces what genuinely needs the user.
    public static func isReachable(_ target: Horizon, from rule: Horizon) -> Bool {
        if target.sortIndex > rule.sortIndex {
            return true
        }
        return rule.sortIndex - target.sortIndex == 1
    }

    /// Bounds the reason so a runaway sentence cannot wreck a card.
    public static func bound(_ reason: String, horizon: Horizon) -> String {
        let trimmed = reason
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackReason(for: horizon) }
        guard trimmed.count > maxReasonLength else { return trimmed }
        let cut = trimmed.prefix(maxReasonLength)
        if let space = cut.lastIndex(of: " ") {
            return String(cut[..<space]) + "..."
        }
        return String(cut) + "..."
    }

    /// The batched question put to the model.
    ///
    /// **Contains no item id, by construction.** The model is given the batch index
    /// and nothing that could be echoed back as an identifier: the mapping from
    /// index to item is applied afterwards, from data the model never saw. That is
    /// why this lives here rather than being assembled ad hoc at the call site -- a
    /// future edit that "helpfully" adds the id for traceability would silently
    /// create a way for the model to write to the wrong item, and the test below it
    /// exists to fail if that happens.
    public static func prompt(for batch: [PlacementCandidate]) -> String {
        let lines = batch.map { candidate -> String in
            let due = candidate.dueInDays.map { days -> String in
                switch days {
                case 0: "due today"
                case 1: "due tomorrow"
                case let d where d < 0: "\(-d) days overdue"
                default: "due in \(days) days"
                }
            } ?? "no due date"
            return """
            [\(candidate.index)] kind=\(candidate.kind.rawValue) \
            priority=\(candidate.priority.rawValue) \(due) \
            placed_in=\(candidate.ruleHorizon.rawValue) \
            because=\(candidate.ruleReason) \
            title=\(candidate.title)
            """
        }
        return """
        Items:
        \(lines.joined(separator: "\n"))

        For each item, give the bucket it truly belongs in and a short reason the \
        user will read on the card. Use the item's number as its index.
        """
    }

    /// What a card says when the model gave no usable reason.
    public static func fallbackReason(for horizon: Horizon) -> String {
        switch horizon {
        case .now: "needs you today"
        case .next: "due soon"
        case .later: "can wait"
        case .niceToKnow: "worth knowing"
        }
    }
}
