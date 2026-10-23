import Foundation
import Testing
@testable import PulseCore

@Suite("CaptureEngine")
struct CaptureEngineTests {
    private func makeEngine(
        sources: [any CaptureSource],
        store: ItemStore,
        now: Date = Fixture.now
    ) -> CaptureEngine {
        CaptureEngine(
            sources: sources,
            store: store,
            // A constant, obviously-fake instant: capture logic must never call
            // `Date()` itself, and any such call would show up as a wildly
            // different `startedAt`.
            now: { now },
            calendar: Fixture.calendar
        )
    }

    @Test("a throwing source does not prevent the other sources from contributing")
    func oneSourceFails() async throws {
        let store = ItemStore()
        let good = FakeSource(sourceID: .calendar, items: [
            Fixture.detected("calendar:event:A", title: "A"),
            Fixture.detected("calendar:event:B", title: "B"),
        ])
        let bad = FakeSource(sourceID: .other, error: .underlying("boom"))
        let engine = makeEngine(sources: [good, bad], store: store)

        let report = await engine.run(mode: .full)

        #expect(report.errors.count == 1)
        #expect(report.errors.first?.source == .other)
        #expect(report.errors.first?.isPermissionDenied == false)
        #expect(report.created.count == 2)
        #expect(await store.count() == 2)
        #expect(await store.item(id: "calendar:event:A") != nil)
    }

    @Test("a denied source is reported as paused, not as a failure of the pass")
    func deniedIsPaused() async {
        let store = ItemStore()
        let denied = FakeSource(sourceID: .calendar, error: .denied(.calendar))
        let engine = makeEngine(sources: [denied], store: store)

        let report = await engine.run(mode: .full)

        #expect(report.errors.count == 1)
        #expect(report.errors.first?.isPermissionDenied == true)
        #expect(report.pausedSources == [.calendar])
        #expect(report.detectedCount == 0)
        #expect(await store.count() == 0)
    }

    @Test("the same now twice produces identical ids and no duplicates")
    func idempotentPass() async {
        let store = ItemStore()
        let source = FakeSource(sourceID: .calendar, items: [
            Fixture.detected("calendar:event:A", title: "A"),
            Fixture.detected("reminders:reminder:B", title: "B"),
        ])
        let engine = makeEngine(sources: [source], store: store)

        let first = await engine.run(mode: .full)
        let second = await engine.run(mode: .full)

        #expect(first.created.count == 2)
        #expect(second.created.isEmpty)
        #expect(await store.count() == 2)
        #expect(await store.allItems().map(\.id) == ["calendar:event:A", "reminders:reminder:B"])
    }

    @Test("deduplication is last-wins, in source order")
    func deduplication() async {
        let store = ItemStore()
        let first = FakeSource(sourceID: .calendar, items: [
            Fixture.detected("calendar:event:A", title: "first", priority: .low),
        ])
        let second = FakeSource(sourceID: .calendar, items: [
            Fixture.detected("calendar:event:A", title: "second", priority: .high),
        ])
        let engine = makeEngine(sources: [first, second], store: store)

        let report = await engine.run(mode: .full)
        let item = await store.item(id: "calendar:event:A")

        #expect(report.created.count == 1)
        #expect(report.detectedCount == 1)
        #expect(item?.title == "second")
        #expect(item?.priority == .high)
    }

    @Test("a full pass resolves an item it no longer sees; an incremental pass leaves it alone")
    func resolveMissing() async throws {
        let store = ItemStore()
        let source = FakeSource(sourceID: .calendar, items: [
            Fixture.detected("calendar:event:A", title: "A"),
        ])
        let engine = makeEngine(sources: [source], store: store)
        _ = await engine.run(mode: .full)
        #expect(await store.item(id: "calendar:event:A")?.status == .open)

        // The source now returns nothing: the meeting is gone.
        let gone = makeEngine(
            sources: [FakeSource(sourceID: .calendar, items: [])],
            store: store,
            now: Fixture.now.addingTimeInterval(60)
        )

        let incremental = await gone.run(mode: .incremental)
        #expect(incremental.resolved.isEmpty)
        #expect(await store.item(id: "calendar:event:A")?.status == .open)

        let full = await gone.run(mode: .full)
        #expect(full.resolved == ["calendar:event:A"])
        #expect(await store.item(id: "calendar:event:A")?.status == .resolved)
    }

    @Test("two concurrent runs perform exactly one capture")
    func concurrentRuns() async {
        let store = ItemStore()
        let source = FakeSource(
            sourceID: .calendar,
            items: [Fixture.detected("calendar:event:A", title: "A")],
            delay: .milliseconds(50)
        )
        let engine = makeEngine(sources: [source], store: store)

        async let first = engine.run(mode: .full)
        async let second = engine.run(mode: .full)
        let reports = await [first, second]

        #expect(source.detectCallCount == 1)
        #expect(reports[0].created == reports[1].created)
        #expect(await store.count() == 1)
    }

    @Test("every source is judged against the same injected instant")
    func sharedInstant() async {
        let store = ItemStore()
        let a = FakeSource(sourceID: .calendar, items: [])
        let b = FakeSource(sourceID: .other, items: [])
        let engine = makeEngine(sources: [a, b], store: store)

        let report = await engine.run(mode: .full)

        #expect(a.detectInstants == [Fixture.now])
        #expect(b.detectInstants == [Fixture.now])
        #expect(report.startedAt == Fixture.now)
        #expect(report.finishedAt == Fixture.now)
    }

    @Test("the report converts to a CaptureRun envelope")
    func reportEnvelope() async {
        let store = ItemStore()
        let source = FakeSource(sourceID: .calendar, items: [Fixture.detected("calendar:event:A")])
        let bad = FakeSource(sourceID: .other, error: .denied(.calendar))
        let report = await makeEngine(sources: [source, bad], store: store).run(mode: .full)

        let run = report.captureRun()
        #expect(run.sources == ["calendar"])
        #expect(run.errors.count == 1)
        #expect(run.summary.contains("1 detected"))
        #expect(run.summary.contains("1 errors"))
        #expect(run.startedAt == Fixture.now)
    }

    @Test("CaptureMode windows match the architecture's scheduling")
    func modeWindows() {
        let full = CaptureMode.full.window(now: Fixture.now, calendar: Fixture.calendar)
        #expect(Fixture.calendar.isDate(full.start, inSameDayAs: Fixture.now))
        #expect(full.duration == 8 * 86_400)

        let incremental = CaptureMode.incremental.window(now: Fixture.now, calendar: Fixture.calendar)
        #expect(incremental.start == Fixture.now.addingTimeInterval(-86_400))
        #expect(incremental.end == Fixture.now.addingTimeInterval(2 * 86_400))

        #expect(CaptureMode.full.resolvesMissingItems)
        #expect(!CaptureMode.incremental.resolvesMissingItems)
        #expect(CaptureMode.full.runName == "capture-full")
    }

    @Test("an expired snooze is normalised during a pass")
    func expiredSnoozeNormalised() async throws {
        let store = ItemStore()
        try await store.upsert(
            detected: [Fixture.detected("calendar:event:A", title: "A")],
            run: "capture",
            now: Fixture.now.addingTimeInterval(-7200)
        )
        try await store.userAction(
            id: "calendar:event:A",
            verb: .snooze,
            until: Fixture.now.addingTimeInterval(-60),
            now: Fixture.now.addingTimeInterval(-7200)
        )
        #expect(await store.item(id: "calendar:event:A")?.status == .snoozed)

        let engine = makeEngine(
            sources: [FakeSource(sourceID: .calendar, items: [])],
            store: store
        )
        _ = await engine.run(mode: .incremental)
        #expect(await store.item(id: "calendar:event:A")?.status == .open)
        #expect(await store.item(id: "calendar:event:A")?.snoozedUntil == nil)
    }

    // MARK: End to end

    /// A fixed `now`, a fake calendar and fake reminders, run through a real
    /// `ItemStore`, then a second pass where the invite has been answered.
    @Test("a full pass over a fake calendar and reminders produces the contract's item set")
    func endToEnd() async throws {
        let store = ItemStore()

        let invite = EventFixture.event(
            "INVITE-1",
            title: "Design review",
            startsIn: 3 * 3600,
            organizer: "Ada Lovelace",
            attendees: [
                Attendee(name: "Grace Hopper", identifier: "grace@example.com"),
                Attendee(name: EventFixture.me, identifier: "steve@example.com"),
            ],
            status: .invited
        )
        // Two hours out: overlapping (30 min) but not imminent, so they exist
        // only as the conflict card.
        let standup = EventFixture.event("CAL-1", title: "Standup", startsIn: 7200, lasts: 3600)
        let design = EventFixture.event("CAL-2", title: "Design sync", startsIn: 7200 + 1800, lasts: 3600)
        // 20 minutes out and 10 minutes long, so it is imminent without
        // overlapping the standup/design-sync pair.
        let soon = EventFixture.event("CAL-3", title: "Retro", startsIn: 20 * 60, lasts: 10 * 60)
        let reading = EventFixture.event(
            "CAL-4",
            title: "Reading group",
            startsIn: 3 * 86_400,
            notes: "https://example.com/reading"
        )

        let calendarSource = EventKitSource(
            provider: FakeEventProvider(events: [invite, standup, design, soon, reading]),
            currentUserName: EventFixture.me,
            calendar: Fixture.calendar
        )
        let remindersSource = RemindersSource(
            provider: FakeReminderProvider(reminders: [
                ReminderSnapshot(identifier: "REM-1", title: "Pay invoice",
                                 dueDate: Fixture.now.addingTimeInterval(-3600)),
                ReminderSnapshot(identifier: "REM-2", title: "File expenses",
                                 dueDate: Fixture.now.addingTimeInterval(3600)),
            ]),
            calendar: Fixture.calendar
        )

        let engine = CaptureEngine(
            sources: [calendarSource, remindersSource],
            store: store,
            now: { Fixture.now },
            calendar: Fixture.calendar
        )

        let report = await engine.run(mode: .full)

        #expect(report.errors.isEmpty)
        // rsvp + imminent deadline + fyi + one conflict card + two reminders.
        let items = await store.allItems()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["calendar:event:INVITE-1"]?.kind == .rsvp)
        #expect(byID["calendar:event:INVITE-1"]?.priority == .high)
        // Standup and Design sync are not imminent, so they exist only as the
        // conflict card; Retro is the imminent deadline.
        #expect(byID["calendar:event:CAL-3"]?.kind == .deadline)
        #expect(byID["calendar:event:CAL-4"]?.kind == .fyi)
        #expect(byID["reminders:reminder:REM-1"]?.priority == .high)
        #expect(byID["reminders:reminder:REM-2"]?.priority == .normal)

        let conflicts = items.filter { $0.kind == .conflict }
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.id.hasPrefix("calendar:conflict:20261023:") == true)
        #expect(items.count == 6)
        #expect(report.created.count == 6)

        // The board sees the invite in Now.
        let board = await store.board(at: Fixture.now, calendar: Fixture.calendar)
        #expect(board[.now]?.contains { $0.id == "calendar:event:INVITE-1" } == true)

        // Second pass: the user accepted the invite, so the event is no longer
        // awaiting a response -- and its card resolves rather than vanishing.
        let accepted = EventFixture.event(
            "INVITE-1",
            title: "Design review",
            startsIn: 3 * 3600,
            organizer: "Ada Lovelace",
            status: .accepted
        )
        let secondEngine = CaptureEngine(
            sources: [
                EventKitSource(
                    provider: FakeEventProvider(events: [accepted, standup, design, soon, reading]),
                    currentUserName: EventFixture.me,
                    calendar: Fixture.calendar
                )
            ],
            store: store,
            now: { Fixture.now.addingTimeInterval(300) },
            calendar: Fixture.calendar
        )

        let second = await secondEngine.run(mode: .full)
        #expect(second.resolved.contains("calendar:event:INVITE-1"))
        #expect(second.resolved.contains("reminders:reminder:REM-1"))
        #expect(second.resolved.contains("reminders:reminder:REM-2"))

        let after = await store.item(id: "calendar:event:INVITE-1")
        #expect(after?.status == .resolved)
        #expect(after?.resolution == "no longer detected")
    }

    @Test("capture never reads the wall clock: a pass built on a fake instant reports that instant")
    func noWallClock() async {
        let store = ItemStore()
        let fake = Fixture.date("2001-01-01T00:00:00.000Z")
        let engine = CaptureEngine(
            sources: [FakeSource(sourceID: .calendar, items: [])],
            store: store,
            now: { fake },
            calendar: Fixture.calendar
        )
        let report = await engine.run(mode: .full)
        #expect(report.startedAt == fake)
        #expect(report.finishedAt == fake)
        #expect(report.captureRun().finishedAt == fake)
    }
}
