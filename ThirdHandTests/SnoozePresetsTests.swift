import Foundation
import Testing
@testable import ThirdHand

// Force-unwrapping is the fixture style here on purpose: the calendar and the dates
// below are fixed literals, and a bad one is a broken test that should stop the run at
// the line that built it.

/// #19: every preset asserted against a fixed `now` on a fixed calendar,
/// including the "this evening disappears after 18:00" rule.
@Suite("Snooze presets")
struct SnoozePresetsTests {
    /// 2026-10-23 09:00 UTC — a Friday.
    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        // swiftlint:disable:next force_unwrapping
        calendar().date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test("In an hour is exactly one hour ahead")
    func inAnHour() {
        let now = Self.date(2026, 10, 23, 9)
        let presets = SnoozePresets(now: now, calendar: Self.calendar())
        #expect(presets.laterToday?.date == now.addingTimeInterval(3600))
        #expect(presets.laterToday?.label == "In an hour")
    }

    @Test("This evening is 18:00 today before 18:00")
    func thisEvening() {
        let now = Self.date(2026, 10, 23, 9)
        let presets = SnoozePresets(now: now, calendar: Self.calendar())
        #expect(presets.thisEvening?.date == Self.date(2026, 10, 23, 18))
    }

    @Test("This evening is absent at and after 18:00")
    func thisEveningGone() {
        let calendar = Self.calendar()
        for hour in [18, 19, 23] {
            let now = Self.date(2026, 10, 23, hour)
            let presets = SnoozePresets(now: now, calendar: calendar)
            #expect(presets.thisEvening == nil, "should be nil at \(hour):00")
        }
        // And it is absent from `all`.
        let evening = SnoozePresets(now: Self.date(2026, 10, 23, 19), calendar: calendar)
        #expect(evening.all.contains { $0.label == "This evening" } == false)
    }

    @Test("Tomorrow morning is tomorrow at 09:00")
    func tomorrowMorning() {
        let now = Self.date(2026, 10, 23, 9)
        let presets = SnoozePresets(now: now, calendar: Self.calendar())
        #expect(presets.tomorrowMorning?.date == Self.date(2026, 10, 24, 9))
    }

    @Test("Next Monday is the coming Monday at 09:00")
    func nextMonday() {
        let now = Self.date(2026, 10, 23, 9) // Friday
        let presets = SnoozePresets(now: now, calendar: Self.calendar())
        #expect(presets.nextMonday?.date == Self.date(2026, 10, 26, 9))
    }

    @Test("Every preset is in the future")
    func allFuture() {
        let now = Self.date(2026, 10, 23, 23, 30)
        let presets = SnoozePresets(now: now, calendar: Self.calendar())
        #expect(presets.all.allSatisfy { $0.date > now })
        #expect(presets.all.isEmpty == false)
    }

    @Test("Presets are computed, not stored: a later now yields later dates")
    func computed() {
        let calendar = Self.calendar()
        let early = SnoozePresets(now: Self.date(2026, 10, 23, 9), calendar: calendar)
        let late = SnoozePresets(now: Self.date(2026, 10, 23, 15), calendar: calendar)
        #expect(early.tomorrowMorning?.date == late.tomorrowMorning?.date)
        #expect(early.laterToday?.date != late.laterToday?.date)
    }
}
