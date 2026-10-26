import Foundation

/// One reminder, as plain values -- the same boundary as `CalendarEventSnapshot`.
///
/// `EventKitReminderProvider` maps `EKReminder` into this; the rules are pure
/// functions over arrays of these.
public struct ReminderSnapshot: Sendable, Hashable, Identifiable {
    /// `EKCalendarItem.calendarItemIdentifier` -- the `<identifier>` half of
    /// `reminders:reminder:<id>`.
    public var identifier: String
    public var title: String
    public var notes: String?
    /// `nil` for a reminder with no due date, which is never overdue.
    public var dueDate: Date?
    public var isCompleted: Bool

    public var id: String {
        identifier
    }

    public init(
        identifier: String,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
    }
}

/// Anything that can hand back incomplete reminders.
public protocol ReminderProviding: Sendable {
    func incompleteReminders() async throws -> [ReminderSnapshot]
}
