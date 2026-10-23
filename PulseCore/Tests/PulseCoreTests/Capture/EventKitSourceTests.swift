import Foundation
import Testing
@testable import PulseCore

/// Fixtures for calendar detection. Every event sits relative to `Fixture.now`
/// (2026-10-23T18:04:11Z, a Friday afternoon), so "today" and "tomorrow" are
/// fixed by the fixture calendar rather than by the machine's clock.
enum EventFixture {
    static let me = "Steve Frost"

    static func event(
        _ identifier: String,
        title: String = "Meeting",
        startsIn seconds: TimeInterval,
        lasts duration: TimeInterval = 3600,
        isAllDay: Bool = false,
        notes: String? = nil,
        url: String? = nil,
        organizer: String? = "Ada Lovelace",
        attendees: [Attendee] = [],
        status: ParticipationStatus? = .accepted,
        isCancelled: Bool = false
    ) -> CalendarEventSnapshot {
        let start = Fixture.now.addingTimeInterval(seconds)
        return CalendarEventSnapshot(
            identifier: identifier,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            isAllDay: isAllDay,
            notes: notes,
            url: url,
            organizerName: organizer,
            attendees: attendees,
            currentUserStatus: status,
            isCancelled: isCancelled
        )
    }
}

@Suite("EventKitSource")
struct EventKitSourceTests {
    // MARK: RSVP

    @Test("an invite in 3h is rsvp/high with the organizer in people and the user excluded")
    func inviteUrgent() throws {
        let event = EventFixture.event(
            "E1",
            title: "Design review",
            startsIn: 3 * 3600,
            organizer: "Ada Lovelace",
            attendees: [
                Attendee(name: "Grace Hopper", identifier: "grace@example.com"),
                Attendee(name: EventFixture.me, identifier: "steve@example.com"),
            ],
            status: .invited
        )
        let items = EventKitSource.detect(events: [event], now: Fixture.now, currentUserName: EventFixture.me)
        let item = try #require(items.first)

        #expect(items.count == 1)
        #expect(item.kind == .rsvp)
        #expect(item.priority == .high)
        #expect(item.id == "calendar:event:E1")
        #expect(item.people?.contains("Ada Lovelace") == true)
        #expect(item.people?.contains("Grace Hopper") == true)
        #expect(item.people?.contains(EventFixture.me) == false)
        #expect(item.source == .calendar)
        #expect(item.due == event.startDate)
    }

    @Test("an invite in 3 days is rsvp/normal")
    func inviteLater() throws {
        let event = EventFixture.event("E2", startsIn: 3 * 86_400, status: .invited)
        let item = try #require(EventKitSource.detect(events: [event], now: Fixture.now).first)
        #expect(item.kind == .rsvp)
        #expect(item.priority == .normal)
    }

    @Test("a declined attendee does not produce an RSVP")
    func declinedInvite() {
        let event = EventFixture.event("E3", startsIn: 3 * 3600, status: .declined)
        #expect(EventKitSource.detect(events: [event], now: Fixture.now).isEmpty)
    }

    @Test("an accepted event produces no RSVP")
    func acceptedInvite() {
        let event = EventFixture.event("E4", startsIn: 3 * 3600, status: .accepted)
        #expect(EventKitSource.detect(events: [event], now: Fixture.now).isEmpty)
    }

    @Test("an invite with an https url gets one Accept quick action")
    func acceptAction() throws {
        let with = EventFixture.event("E5", startsIn: 3600, url: "https://calendar.example.com/e/5", status: .invited)
        let item = try #require(EventKitSource.detect(events: [with], now: Fixture.now).first)
        #expect(item.quickActions?.count == 1)
        #expect(item.quickActions?.first?.url == "https://calendar.example.com/e/5")
        #expect(item.quickActions?.first?.label == "Accept")

        let without = EventFixture.event("E6", startsIn: 3600, status: .invited)
        #expect(EventKitSource.detect(events: [without], now: Fixture.now).first?.quickActions == nil)
    }

    // MARK: Conflict

    @Test("two overlapping accepted events produce exactly one conflict with a contract-shaped id")
    func overlappingPair() throws {
        let a = EventFixture.event("A", title: "Standup", startsIn: 3600, lasts: 3600)
        let b = EventFixture.event("B", title: "Design review", startsIn: 3600 + 1800, lasts: 3600)

        let items = EventKitSource.detect(events: [a, b], now: Fixture.now)
        let conflicts = items.filter { $0.kind == .conflict }

        #expect(conflicts.count == 1)
        let conflict = try #require(conflicts.first)
        #expect(conflict.priority == .high)
        #expect(conflict.id.hasPrefix("calendar:conflict:"))
        let parts = conflict.id.split(separator: ":")
        #expect(parts.count == 4)
        #expect(parts[0] == "calendar")
        #expect(parts[1] == "conflict")
        #expect(parts[2] == "20261023")
        #expect(parts[3].count == 8 && parts[3].allSatisfy(\.isHexDigit))
    }

    @Test("three mutually overlapping events give one conflict per pair and no duplicate ids")
    func threeWayConflict() {
        let a = EventFixture.event("A", title: "A", startsIn: 3600, lasts: 3600,
                                   attendees: [Attendee(name: "Ada", identifier: "ada@x")])
        let b = EventFixture.event("B", title: "B", startsIn: 3600, lasts: 3600,
                                   attendees: [Attendee(name: "Grace", identifier: "grace@x")])
        let c = EventFixture.event("C", title: "C", startsIn: 3600, lasts: 3600,
                                   attendees: [Attendee(name: "Linus", identifier: "linus@x")])

        let conflicts = EventKitSource.detect(events: [a, b, c], now: Fixture.now).filter { $0.kind == .conflict }
        #expect(conflicts.count == 3)
        #expect(Set(conflicts.map(\.id)).count == 3)
    }

    @Test("a 4-minute overlap is not a conflict; 6 minutes is")
    func overlapThreshold() {
        // 60-minute events offset by 56 minutes share 4 minutes.
        let four = [
            EventFixture.event("A", title: "A", startsIn: 3600, lasts: 3600),
            EventFixture.event("B", title: "B", startsIn: 3600 + 3360, lasts: 3600),
        ]
        #expect(EventKitSource.detect(events: four, now: Fixture.now).filter { $0.kind == .conflict }.isEmpty)

        // Offset by 54 minutes -> 6 minutes of overlap.
        let six = [
            EventFixture.event("C", title: "C", startsIn: 3600, lasts: 3600),
            EventFixture.event("D", title: "D", startsIn: 3600 + 3240, lasts: 3600),
        ]
        #expect(EventKitSource.detect(events: six, now: Fixture.now).filter { $0.kind == .conflict }.count == 1)
    }

    @Test("a conflict needs accepted, live events on both sides")
    func conflictRequiresAccepted() {
        let declined = [
            EventFixture.event("A", title: "A", startsIn: 3600, lasts: 3600),
            EventFixture.event("B", title: "B", startsIn: 3600, lasts: 3600, status: .declined),
        ]
        #expect(EventKitSource.detect(events: declined, now: Fixture.now).filter { $0.kind == .conflict }.isEmpty)

        let cancelled = [
            EventFixture.event("C", title: "C", startsIn: 3600, lasts: 3600),
            EventFixture.event("D", title: "D", startsIn: 3600, lasts: 3600, isCancelled: true),
        ]
        #expect(EventKitSource.detect(events: cancelled, now: Fixture.now).filter { $0.kind == .conflict }.isEmpty)
    }

    @Test("an overlap beyond tomorrow is not a conflict")
    func conflictOnlyTodayOrTomorrow() {
        let far = 5 * 86_400.0
        let events = [
            EventFixture.event("A", title: "A", startsIn: far, lasts: 3600),
            EventFixture.event("B", title: "B", startsIn: far + 600, lasts: 3600),
        ]
        #expect(EventKitSource.detect(events: events, now: Fixture.now).filter { $0.kind == .conflict }.isEmpty)
    }

    // MARK: Imminent

    @Test("an event in 45 minutes is a deadline item at high priority")
    func imminent() throws {
        let event = EventFixture.event("E7", title: "Retro", startsIn: 45 * 60)
        let item = try #require(EventKitSource.detect(events: [event], now: Fixture.now).first)
        #expect(item.kind == .deadline)
        #expect(item.priority == .high)
        #expect(item.title == "Retro")
        #expect(item.due == event.startDate)
    }

    @Test("an all-day event today produces no imminent item")
    func imminentAllDay() {
        let event = EventFixture.event("E8", startsIn: 600, isAllDay: true)
        #expect(EventKitSource.detect(events: [event], now: Fixture.now).isEmpty)
    }

    @Test("exactly 60 minutes away counts; one second more does not")
    func imminentBoundary() {
        let exactly = EventFixture.event("E9", startsIn: 3_600)
        #expect(EventKitSource.detect(events: [exactly], now: Fixture.now).count == 1)

        let over = EventFixture.event("E10", startsIn: 3_601)
        #expect(EventKitSource.detect(events: [over], now: Fixture.now).isEmpty)
    }

    // MARK: fyi

    @Test("an event with a link and no action becomes fyi/low")
    func passiveLink() throws {
        let event = EventFixture.event(
            "E11",
            title: "Reading group",
            startsIn: 3 * 86_400,
            notes: "Notes: https://example.com/reading",
            attendees: []
        )
        let item = try #require(EventKitSource.detect(events: [event], now: Fixture.now).first)
        #expect(item.kind == .fyi)
        #expect(item.priority == .low)
        #expect(item.url == "https://example.com/reading")
    }

    @Test("an actionable event is not also reported as fyi")
    func fyiDoesNotCompete() {
        let event = EventFixture.event(
            "E12",
            title: "Retro",
            startsIn: 30 * 60,
            notes: "Agenda https://example.com/retro"
        )
        let items = EventKitSource.detect(events: [event], now: Fixture.now)
        #expect(items.count == 1)
        #expect(items.first?.kind == .deadline)
    }

    // MARK: Shape

    @Test("output is sorted by id and free of duplicates")
    func deterministicOrder() {
        let events = [
            EventFixture.event("Z", title: "Z", startsIn: 600),
            EventFixture.event("A", title: "A", startsIn: 1200),
            EventFixture.event("M", title: "M", startsIn: 1800),
        ]
        let items = EventKitSource.detect(events: events, now: Fixture.now)
        #expect(items.map(\.id) == items.map(\.id).sorted())
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test("the source fetches through its provider and sorts the result")
    func detectsThroughProvider() async throws {
        // Deliberately 4 minutes of overlap: not enough to be a conflict, so the
        // provider's items come through unchanged.
        let provider = FakeEventProvider(events: [
            EventFixture.event("B", title: "B", startsIn: 600, lasts: 60),
            EventFixture.event("A", title: "A", startsIn: 900, lasts: 60),
        ])
        let source = EventKitSource(provider: provider, currentUserName: EventFixture.me, calendar: Fixture.calendar)
        let items = try await source.detect(now: Fixture.now, window: CaptureWindow.next(days: 7, now: Fixture.now))
        #expect(source.sourceID == .calendar)
        #expect(items.map(\.id) == ["calendar:event:A", "calendar:event:B"])
    }

    @Test("a denied provider throws the typed denial")
    func providerDenied() async {
        let source = EventKitSource(provider: FakeEventProvider(events: [], error: .denied(.calendar)))
        await #expect(throws: CaptureError.denied(.calendar)) {
            try await source.detect(now: Fixture.now, window: CaptureWindow.next(days: 7, now: Fixture.now))
        }
    }
}
