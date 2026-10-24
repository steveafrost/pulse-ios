import Foundation

/// §8.3 / #19: the snooze presets. Pure date math with an injected `now` and
/// `Calendar`, so the tests can pin both and the presets cannot drift.
///
/// The presets are computed, never stored: "this evening" means 18:00 *today*
/// and disappears once it is gone.
public struct SnoozePresets: Sendable {
    public struct Preset: Sendable, Hashable, Identifiable {
        public var id: String { label }
        public var label: String
        public var date: Date
        /// Shown as the trailing detail, e.g. "18:00".
        public var detail: String

        public init(label: String, date: Date, detail: String) {
            self.label = label
            self.date = date
            self.detail = detail
        }
    }

    public let now: Date
    public let calendar: Calendar

    public init(now: Date, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    /// #19: 1 hour, this evening (hidden after 18:00), tomorrow 9:00, next
    /// Monday 9:00. Only future dates are returned.
    public var all: [Preset] {
        [laterToday, thisEvening, tomorrowMorning, nextMonday].compactMap { $0 }
    }

    public var laterToday: Preset? {
        let date = now.addingTimeInterval(Self.secondsPerHour)
        guard isFuture(date) else { return nil }
        return Preset(label: "In an hour", date: date, detail: time(date))
    }

    /// The design's "this evening" is 18:00 today and is absent after it.
    public var thisEvening: Preset? {
        guard let date = today(hour: 18), isFuture(date) else { return nil }
        return Preset(label: "This evening", date: date, detail: time(date))
    }

    public var tomorrowMorning: Preset? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let date = day(tomorrow, hour: 9)
        else { return nil }
        return Preset(label: "Tomorrow morning", date: date, detail: time(date))
    }

    /// "this weekend (Sat 9:00)" from the design's sheet, expressed as the next
    /// Monday 9:00 per #19's option list.
    public var nextMonday: Preset? {
        guard let date = nextWeekday(2, hour: 9) else { return nil }
        return Preset(label: "Next Monday", date: date, detail: time(date))
    }

    // MARK: Helpers

    static let secondsPerHour: TimeInterval = 3_600

    public func isFuture(_ date: Date) -> Bool { date > now }

    /// Formatted in *this* preset's calendar, not the device's: with a Greenwich
    /// calendar and a New York device, "18:00" must read 18:00, or the label and
    /// the instant it writes to the store disagree.
    private func time(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    private func today(hour: Int) -> Date? {
        day(now, hour: hour)
    }

    private func day(_ date: Date, hour: Int) -> Date? {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
    }

    /// The next date whose weekday is `weekday`, strictly after today, at `hour`.
    private func nextWeekday(_ weekday: Int, hour: Int) -> Date? {
        guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now) else { return nil }
        var probe = calendar.startOfDay(for: nextWeek)
        // Walk back to the Monday of that week rather than forward, so "next
        // Monday" from a Tuesday is the Monday coming, not a week later.
        for _ in 0..<7 {
            if calendar.component(.weekday, from: probe) == weekday { break }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: probe) else { return nil }
            probe = previous
        }
        if calendar.component(.weekday, from: probe) != weekday,
           let forward = calendar.date(byAdding: .day, value: 7, to: probe) {
            probe = forward
        }
        guard let date = day(probe, hour: hour), isFuture(date) else { return nil }
        return date
    }
}
