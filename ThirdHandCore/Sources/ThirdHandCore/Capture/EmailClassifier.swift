import Foundation

/// The mail-specific classification rules, kept next to `Classifier` and for the
/// same reason: one place per rule, so the detector reads as prose and the rules are
/// testable without a transport.
///
/// The contract's table (`docs/DATA-CONTRACT.md`, "Classification rules") names only
/// "Imported mail awaiting a reply -> `reply`", which was the share-sheet row. A real
/// IMAP pull adds rows, and they are recorded in `docs/DEFERRED-SOURCES.md` rather
/// than in the contract: the contract governs the *wire shape*, and none of these
/// rules changes a field, a type or a `schemaVersion`.
///
/// **The one rule that matters here is the negative one: a direct unread message is
/// never `fyi`.** Unread mail addressed to the user is by definition something a
/// person sent and nobody has acknowledged; filing it under "Nice to Know" would be
/// the silently-empty-source failure wearing a smile. Every path below ends in
/// `reply`, `decision` or `deadline`.
public enum EmailClassifier {
    /// Deadline words. Matched case-insensitively as whole phrases against the
    /// subject, so "deadline" in a mailing-list footer does not fire but "by Friday"
    /// in a direct message does.
    ///
    /// Ordered most to least urgent; the first match wins and only affects the
    /// `reason`, so order is cosmetic.
    public static let deadlinePhrases: [String] = [
        "deadline", "due by", "due on", "due tomorrow", "due today", "due friday",
        "due monday", "end of day", "eod", "cob", "close of business", "by end of",
        "expires", "last chance", "final reminder", "action required", "overdue"
    ]

    /// Decision words: the sender wants a choice, an approval or a sign-off, not an
    /// answer. This is the same vocabulary `Classifier.decisionPhrases` uses for
    /// shared links, plus mail-specific forms ("please approve", "LGTM?").
    public static let decisionPhrases: [String] = [
        "can you approve", "please approve", "need your approval", "your approval",
        "sign off", "sign-off", "signoff", "should we", "do we want", "which option",
        "vote on", "decide", "decision needed", "go/no-go", "go no-go", "approve the"
    ]

    /// Classification of one message, as the `(Kind, Priority)` pair the store wants.
    public struct Classification: Sendable, Hashable {
        public var kind: Kind
        public var priority: Priority
        /// A short human explanation, recorded as the item's `reason` in history.
        public var reason: String

        init(_ kind: Kind, _ priority: Priority, _ reason: String) {
            self.kind = kind
            self.priority = priority
            self.reason = reason
        }
    }

    /// The rule set, in precedence order:
    ///
    /// 1. A deadline phrase in the subject -> `deadline`, `high`. A date is the one
    ///    thing that gets harder to act on the longer it waits.
    /// 2. A decision phrase in the subject -> `decision`, `normal`. Asking the user to
    ///    reply would understate "should we ship Friday?".
    /// 3. The user is the *sole* recipient and the message is not itself a reply ->
    ///    `reply`, `normal`. One sender, one recipient, no `Re:`: a person waiting on
    ///    the user.
    /// 4. A question mark anywhere in subject or detail -> `reply`, `normal`.
    /// 5. Anything else -> `followup`, `normal`. Never `fyi`.
    ///
    /// "Sole recipient" counts `To` and `Cc` together, minus the user's own address,
    /// so a message to the user plus one colleague lands on rule 5 -- it is waiting on
    /// two people, which is a follow-up rather than a direct ask.
    ///
    /// `isReply` only *demotes* rule 3, it never produces `fyi`: an unread reply still
    /// wants to be read, so it falls through to rule 5.
    public static func classify(
        subject: String,
        detail: String?,
        recipients: [EmailAddress],
        userAddress: String,
        isReply: Bool
    ) -> Classification {
        let lowered = subject.lowercased()

        if let phrase = firstMatch(deadlinePhrases, in: lowered) {
            return Classification(.deadline, .high, "mentions a deadline (\(phrase))")
        }
        if let phrase = firstMatch(decisionPhrases, in: lowered) {
            return Classification(.decision, .normal, "asks for a decision (\(phrase))")
        }

        let others = recipients.filter { !$0.matches(anyOf: [userAddress]) }
        if others.isEmpty, !isReply {
            return Classification(.reply, .normal, "only you were addressed")
        }
        if lowered.contains("?") || (detail?.contains("?") ?? false) {
            return Classification(.reply, .normal, "asks a question")
        }
        return Classification(.followup, .normal, isReply ? "part of an unread thread" : "unread mail")
    }

    /// Whether `text` contains any of `phrases`, matched as a substring of the
    /// lowercased text. A phrase list matched this way is intentionally blunt: a
    /// "deadline" anywhere in a direct message's subject is a signal worth acting on,
    /// and the cost of a false positive is a high-priority card, not a missed one.
    static func firstMatch(_ phrases: [String], in loweredText: String) -> String? {
        phrases.first { loweredText.contains($0) }
    }
}
