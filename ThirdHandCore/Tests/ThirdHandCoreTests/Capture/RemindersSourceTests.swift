import Foundation
import Testing
@testable import ThirdHandCore

@Suite("RemindersSource")
struct RemindersSourceTests {
    private func reminder(
        _ identifier: String,
        title: String = "Reminder",
        dueIn seconds: TimeInterval?,
        notes: String? = nil,
        isCompleted: Bool = false
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            identifier: identifier,
            title: title,
            notes: notes,
            dueDate: seconds.map { Fixture.now.addingTimeInterval($0) },
            isCompleted: isCompleted
        )
    }

    @Test("an overdue reminder is a high deadline")
    func overdue() throws {
        let item = try #require(RemindersSource.detect(
            reminders: [reminder("R1", title: "Pay invoice", dueIn: -2 * 3600)],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).first)

        #expect(item.kind == .deadline)
        #expect(item.priority == .high)
        #expect(item.id == "reminders:reminder:R1")
        #expect(item.source == .other)
        #expect(DetectedItem.source(fromIdentifier: item.id) == .other)
        #expect(item.reason == "overdue")
    }

    @Test("a reminder due later today is a normal deadline")
    func dueToday() throws {
        let item = try #require(RemindersSource.detect(
            reminders: [reminder("R2", dueIn: 3600)],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).first)
        #expect(item.kind == .deadline)
        #expect(item.priority == .normal)
        #expect(item.reason == "due today")
    }

    /// A future reminder is reported, not dropped. Dropping it was the bug: the
    /// store then kept whatever stale date it already had, so a reminder the user
    /// pushed two months out stayed in Now forever. The horizon places it.
    @Test("a reminder due tomorrow is reported, and the horizon files it under next")
    func dueTomorrow() throws {
        let tomorrow = Fixture.now.addingTimeInterval(26 * 3600)
        let item = try #require(RemindersSource.detect(
            reminders: [reminder("R3", dueIn: 26 * 3600)],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).first)
        #expect(item.priority == .normal)
        #expect(item.reason == "due later")

        let stored = ThirdHandItem(
            id: item.id, source: .other, kind: item.kind ?? .deadline, title: item.title ?? "",
            due: item.due, priority: item.priority ?? .normal, status: .open,
            firstSeenAt: Fixture.now, lastSeenAt: Fixture.now, updatedAt: Fixture.now,
            lastChangedBy: "test"
        )
        #expect(HorizonDerivation.horizon(of: stored, at: Fixture.now, calendar: Fixture.calendar) == .next)
        #expect(item.due == tomorrow)
    }

    /// The regression itself: a far-future reminder must reach the store so the
    /// store can learn its new date, and it must land in Later rather than Now.
    @Test("a reminder two months out is reported and lands in later")
    func farFuture() throws {
        let twoMonths: TimeInterval = 61 * 24 * 3600
        let item = try #require(RemindersSource.detect(
            reminders: [reminder("R3b", dueIn: twoMonths)],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).first)
        #expect(item.priority == .normal)

        let stored = ThirdHandItem(
            id: item.id, source: .other, kind: item.kind ?? .deadline, title: item.title ?? "",
            due: item.due, priority: item.priority ?? .normal, status: .open,
            firstSeenAt: Fixture.now, lastSeenAt: Fixture.now, updatedAt: Fixture.now,
            lastChangedBy: "test"
        )
        #expect(HorizonDerivation.horizon(of: stored, at: Fixture.now, calendar: Fixture.calendar) == .later)
    }

    @Test("a completed reminder is excluded even when overdue")
    func completed() {
        #expect(RemindersSource.detect(
            reminders: [reminder("R4", dueIn: -3600, isCompleted: true)],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).isEmpty)
    }

    @Test("a reminder with no due date is excluded")
    func noDueDate() {
        #expect(RemindersSource.detect(
            reminders: [reminder("R5", dueIn: nil)],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).isEmpty)
    }

    @Test("an https link in notes yields exactly one quick action; http yields none")
    func linkQuickAction() throws {
        let with = try #require(RemindersSource.detect(
            reminders: [reminder("R6", dueIn: -60, notes: "Form: https://example.com/form")],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).first)
        #expect(with.quickActions?.count == 1)
        #expect(with.quickActions?.first?.url == "https://example.com/form")
        #expect(with.quickActions?.first?.label == "Open link")
        #expect(with.url == "https://example.com/form")

        let without = try #require(RemindersSource.detect(
            reminders: [reminder("R7", dueIn: -60, notes: "http://insecure.example.com/form")],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).first)
        #expect(without.quickActions == nil)
        #expect(without.url == nil)
    }

    @Test("detail carries the notes and due carries the due date")
    func fieldMapping() throws {
        let snapshot = reminder("R8", title: "Water plants", dueIn: -600, notes: "Kitchen and balcony")
        let item = try #require(RemindersSource.detect(
            reminders: [snapshot],
            now: Fixture.now,
            calendar: Fixture.calendar
        ).first)
        #expect(item.detail == "Kitchen and balcony")
        #expect(item.due == snapshot.dueDate)
        #expect(item.title == "Water plants")
    }

    @Test("output is sorted by id")
    func deterministicOrder() {
        let items = RemindersSource.detect(
            reminders: [reminder("Z", dueIn: -60), reminder("A", dueIn: -60), reminder("M", dueIn: -60)],
            now: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(items.map(\.id) == ["reminders:reminder:A", "reminders:reminder:M", "reminders:reminder:Z"])
    }

    @Test("detect goes through the provider")
    func detectsThroughProvider() async throws {
        let source = RemindersSource(
            provider: FakeReminderProvider(reminders: [reminder("R9", dueIn: -60)]),
            calendar: Fixture.calendar
        )
        let items = try await source.detect(now: Fixture.now, window: CaptureWindow.next(days: 2, now: Fixture.now))
        #expect(source.sourceID == .other)
        #expect(items.count == 1)
    }

    @Test("a denied provider throws the typed denial")
    func providerDenied() async {
        let source = RemindersSource(provider: FakeReminderProvider(reminders: [], error: .denied(.calendar)))
        await #expect(throws: CaptureError.denied(.calendar)) {
            try await source.detect(now: Fixture.now, window: CaptureWindow.next(days: 2, now: Fixture.now))
        }
    }
}
