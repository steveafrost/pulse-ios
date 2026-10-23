import Foundation

/// The Reminders detector: overdue or due-today, incomplete.
///
/// Same split as `EventKitSource`: no rules here, only fetching plus delegation
/// to pure static functions.
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
    /// The inclusion rule is "due at or before the end of today", i.e. overdue or
    /// due today; `window` is not consulted because Reminders has no window query
    /// and a reminder due in three weeks is not this milestone's business.
    public static func detect(
        reminders: [ReminderSnapshot],
        now: Date,
        calendar: Calendar = .current
    ) -> [DetectedItem] {
        let endOfToday = endOfDay(containing: now, calendar: calendar)
        return reminders.compactMap { reminder in
            guard !reminder.isCompleted, let due = reminder.dueDate, due <= endOfToday else { return nil }
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
                reason: due < now ? "overdue" : "due today"
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// The last instant of the day containing `date`. A reminder due at 23:59
    /// tonight is "due today"; one due at 00:01 tomorrow is not.
    public static func endOfDay(containing date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(CaptureWindow.secondsPerDay)
        return nextDay.addingTimeInterval(-0.001)
    }

    /// One `Open link` action when the notes carry an `https://` URL. An
    /// `http://` link yields nothing: the contract's quick actions and item `url`
    /// are https-only.
    static func linkActions(in notes: String?) -> [QuickAction]? {
        guard let link = Classifier.firstHTTPSLink(in: notes) else { return nil }
        return [QuickAction(label: "Open link", url: link)]
    }
}
