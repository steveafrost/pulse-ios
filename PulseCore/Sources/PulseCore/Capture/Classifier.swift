import Foundation

/// The one place that turns raw source facts into a `(Kind, Priority)`.
///
/// Every row of the table in `docs/DATA-CONTRACT.md` ("Classification rules
/// (MVP, on-device only)") has exactly one function here, and the detectors call
/// it instead of re-deriving the rule. Each function returns `nil` when its row
/// does not apply, so a detector can chain them and read as the table does.
///
/// The table this mirrors, verbatim:
///
/// | Detector | kind | priority | notes |
/// | --- | --- | --- | --- |
/// | Meeting accepted=false, start within 7d | `rsvp` | high if <24h else normal | people = organizer + attendees |
/// | Two accepted events overlap > 5 min, today or tomorrow | `conflict` | high | one item per pair per day |
/// | Event start within 60 min, not all-day | `deadline` | high | title = event title |
/// | Reminder overdue or due today, incomplete | `deadline` | high if overdue | |
/// | Event/reminder with a link in notes and no action needed | `fyi` | low | collapsed under Nice to Know |
/// | Imported mail awaiting a reply | `reply` | normal | share-sheet import path |
public enum Classifier {
    /// "Meeting accepted=false, start within 7d".
    public static let inviteHorizon: TimeInterval = 7 * CaptureWindow.secondsPerDay
    /// A start inside this window makes an invite `high`.
    public static let inviteUrgentWindow: TimeInterval = 24 * CaptureWindow.secondsPerHour
    /// "Two accepted events overlap > 5 min".
    public static let minimumConflictOverlap: TimeInterval = 5 * 60
    /// "Event start within 60 min".
    public static let imminentWindow: TimeInterval = 60 * 60

    // MARK: - Calendar rows

    /// Row 1. `isAccepted == false` means the user's own participant status is
    /// `invited`/`pending`; a `declined` event is not an RSVP to act on and the
    /// caller must not reach here for one.
    ///
    /// Boundary: a start exactly 7 days (or exactly 24 hours) away still counts
    /// -- "within" is inclusive, so the comparison is `<=`.
    public static func classifyInvite(started: Date, now: Date, isAccepted: Bool) -> (Kind, Priority)? {
        guard !isAccepted else { return nil }
        let delta = started.timeIntervalSince(now)
        guard delta >= 0, delta <= inviteHorizon else { return nil }
        return (.rsvp, delta < inviteUrgentWindow ? .high : .normal)
    }

    /// Row 2. The overlap itself is checked by the detector (it needs the pair);
    /// this is the classification once the rule has matched.
    public static func classifyConflict() -> (Kind, Priority)? {
        (.conflict, .high)
    }

    /// Row 3. All-day events are excluded: "starts in 45 minutes" is meaningless
    /// for an event that owns the whole day. A start exactly 60 minutes away
    /// counts.
    public static func classifyImminentEvent(started: Date, now: Date, isAllDay: Bool) -> (Kind, Priority)? {
        guard !isAllDay else { return nil }
        let delta = started.timeIntervalSince(now)
        guard delta >= 0, delta <= imminentWindow else { return nil }
        return (.deadline, .high)
    }

    // MARK: - Reminders row

    /// Row 4. The caller must have already established "overdue or due today"
    /// (that needs the calendar); this decides the priority: overdue is `high`,
    /// still due later today is `normal`.
    ///
    /// Deviation note: the contract's notes column reads "high if overdue" and
    /// does not say what a due-today reminder is. M2.3 specifies `normal` for
    /// that case, so that is what we do -- do not "fix" this to `high` without a
    /// contract change.
    public static func classifyReminder(due: Date, now: Date, isCompleted: Bool) -> (Kind, Priority)? {
        guard !isCompleted else { return nil }
        return (.deadline, due < now ? .high : .normal)
    }

    // MARK: - Link row

    /// Row 5. "a link in its notes and no action needed" -> `fyi`, `low`.
    ///
    /// Only `https://` counts: the store refuses a non-https quick action and the
    /// contract says `url` is https-only, so an `http://` note is not a link we
    /// can act on. Returns the first `https://` URL found, trimmed of trailing
    /// punctuation the way a sentence would leave it.
    public static func classifyLinkInNotes(_ notes: String?) -> (Kind, Priority)? {
        guard firstHTTPSLink(in: notes) != nil else { return nil }
        return (.fyi, .low)
    }

    /// The first `https://` URL in free text, with trailing `.,;:)!?` trimmed.
    /// Shared by the `fyi` rule and by the reminders quick action so both agree
    /// on what "the link" is.
    public static func firstHTTPSLink(in notes: String?) -> String? {
        guard let notes, let range = notes.range(of: "https://") else { return nil }
        let tail = notes[range.lowerBound...]
        var candidate = ""
        for character in tail {
            if character.isWhitespace || character == "\n" || character == "\"" || character == "<" {
                break
            }
            candidate.append(character)
        }
        while let last = candidate.last, ".,;:!?".contains(last) {
            candidate.removeLast()
        }
        guard candidate.count > "https://".count, URL(string: candidate) != nil else { return nil }
        return candidate
    }

    // MARK: - Mail row

    /// Row 6. The share-sheet import path, wired up in a later milestone; the
    /// rule lives here now so the table stays in one file.
    public static func classifyImportedMail(awaitsReply: Bool) -> (Kind, Priority)? {
        awaitsReply ? (.reply, .normal) : nil
    }

    // MARK: - Composed rule

    /// The fallback for a calendar event that matched nothing actionable: an
    /// event with a link in its notes becomes `fyi`. Returns `nil` when the event
    /// carries no link, so the detector emits nothing rather than noise.
    public static func classifyPassiveEvent(notes: String?) -> (Kind, Priority)? {
        classifyLinkInNotes(notes)
    }
}
