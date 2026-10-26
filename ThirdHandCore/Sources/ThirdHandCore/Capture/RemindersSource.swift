import Foundation

/// The Reminders detector: every incomplete reminder that carries a due date.
///
/// Same split as `EventKitSource`: no rules here, only fetching plus delegation
/// to pure static functions.
///
/// **Why every due date, not just overdue/today.** This detector used to emit
/// only reminders due at or before the end of today. That made a rescheduled
/// reminder impossible to track: once the user pushed it two months out the source
/// stopped reporting it, so the stored item kept its old (overdue, high-priority)
/// `due` and sat in **Now** claiming it needed them today, forever. A full pass did
/// eventually resolve it, which is the opposite of "it moved".
///
/// The source has to keep reporting a reminder for the store to learn its new date,
/// so the rule is now simply "incomplete and dated": the horizon decides where it
/// lands (today/overdue -> Now, within three days -> Next, further out -> Later).
/// Undated reminders stay excluded -- they are not schedulable and would sit in
/// Later indefinitely as permanent noise.
public struct RemindersSource: CaptureSource {
    /// `Source` has no `reminders` case; the contract's source set is
    /// `slack|gmail|calendar|github|docs|other`, so Reminders lives in `.other`
    /// and `ItemIdentity.source(for: "reminders:reminder:x")` agrees.
    public let sourceID: Source = .other

    private let provider: any ReminderProviding
    private let calendar: Calendar

    public init(provider: any ReminderProviding, calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
    }

    public func detect(now: Date, window: DateInterval) async throws -> [DetectedItem] {
        let reminders = try await provider.incompleteReminders()
        return Self.detect(reminders: reminders, now: now, calendar: calendar)
    }

    /// Every reminder-derived item, sorted by id.
    ///
    /// The inclusion rule is "incomplete and carries a due date", with no forward
    /// bound: the horizon places the item. `window` is not consulted because
    /// Reminders has no window query of its own.
    ///
    /// There is deliberately no forward cutoff. A bound would reintroduce the bug
    /// this rule exists to fix at the boundary -- a reminder just past the cutoff
    /// would silently stop being reported, the store would keep the stale date, and
    /// it would strand wherever it used to be. "No bound" has no cliff.
    public static func detect(
        reminders: [ReminderSnapshot],
        now: Date,
        calendar: Calendar = .current
    ) -> [DetectedItem] {
        reminders.compactMap { reminder in
            guard !reminder.isCompleted, let due = reminder.dueDate else { return nil }
            guard let (kind, priority) = Classifier.classifyReminder(
                due: due,
                now: now,
                isCompleted: reminder.isCompleted
            ) else { return nil }

            return DetectedItem(
                id: ItemIdentity.reminder(reminder.identifier),
                source: .other,
                kind: kind,
                title: reminder.title,
                detail: reminder.notes,
                url: Classifier.firstHTTPSLink(in: reminder.notes),
                due: due,
                priority: priority,
                quickActions: linkActions(in: reminder.notes),
                reason: Self.reason(due: due, now: now, calendar: calendar)
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// The `reason` recorded in history. Kept provider-neutral and factual: it
    /// states the relationship between the due date and today, and nothing else.
    static func reason(due: Date, now: Date, calendar: Calendar = .current) -> String {
        if due < now { return "overdue" }
        let dueDay = calendar.startOfDay(for: due)
        let today = calendar.startOfDay(for: now)
        if dueDay <= today { return "due today" }
        return "due later"
    }

    /// One `Open link` action when the notes carry an `https://` URL. An
    /// `http://` link yields nothing: the contract's quick actions and item `url`
    /// are https-only.
    static func linkActions(in notes: String?) -> [QuickAction]? {
        guard let link = Classifier.firstHTTPSLink(in: notes) else { return nil }
        return [QuickAction(label: "Open link", url: link)]
    }
}
