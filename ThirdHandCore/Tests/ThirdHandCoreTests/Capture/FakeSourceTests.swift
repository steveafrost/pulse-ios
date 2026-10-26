import Foundation
import Testing
@testable import ThirdHandCore

@Suite("FakeSource")
struct FakeSourceTests {
    @Test("returns the canned items verbatim and counts calls")
    func cannedItems() async throws {
        let items = [
            Fixture.detected("calendar:event:A", title: "A"),
            Fixture.detected("reminders:reminder:B", title: "B")
        ]
        let source = FakeSource(sourceID: .calendar, items: items)
        let window = DateInterval(start: Fixture.now, duration: 3600)

        let first = try await source.detect(now: Fixture.now, window: window)
        let second = try await source.detect(now: Fixture.now, window: window)

        #expect(source.detectCallCount == 2)
        #expect(first == items)
        #expect(second == items)
        #expect(first == second)
    }

    @Test("propagates an injected denial as CaptureError.denied")
    func deniedPropagates() async {
        let source = FakeSource(sourceID: .calendar, error: .denied(.calendar))
        let window = DateInterval(start: Fixture.now, duration: 3600)

        await #expect(throws: CaptureError.denied(.calendar)) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("CaptureWindow.next(days: 7) is exactly seven days")
    func nextWindowIsSevenDays() {
        let window = CaptureWindow.next(days: 7, now: Fixture.now)
        #expect(window.duration == 7 * 86400)
        #expect(window.start == Fixture.now)
        #expect(window.end == Fixture.now.addingTimeInterval(604_800))
    }

    @Test("CaptureWindow.day covers the calendar day containing now")
    func dayWindow() {
        let window = CaptureWindow.day(now: Fixture.now, calendar: Fixture.calendar)
        #expect(Fixture.calendar.isDate(window.start, inSameDayAs: Fixture.now))
        #expect(window.duration == 86400)
    }

    @Test("CaptureWindow.rolling is symmetric around now")
    func rollingWindow() {
        let window = CaptureWindow.rolling(hours: 3, now: Fixture.now)
        #expect(window.duration == 6 * 3600)
        #expect(window.start == Fixture.now.addingTimeInterval(-10800))
    }

    @Test("CaptureError names its source")
    func errorSources() {
        #expect(CaptureError.denied(.calendar).source == .calendar)
        #expect(CaptureError.unavailable(.other).source == .other)
        #expect(CaptureError.timeout.source == nil)
        #expect(CaptureError.denied(.calendar).description == "access to calendar was denied")
    }
}
