import Foundation
import Testing
@testable import PulseCore

@Suite("ItemStore")
struct ItemStoreTests {

    // MARK: - Creation

    @Test("a new item is created with derived source, defaults and a history entry")
    func createNewItem() async throws {
        let store = ItemStore()
        let result = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "Standup", kind: .deadline)],
            run: "morning",
            now: Fixture.now
        )

        #expect(result.created == ["calendar:event:1"])
        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.source == .calendar)
        #expect(item.kind == .deadline)
        #expect(item.status == .open)
        #expect(item.priority == .normal)
        #expect(item.detail == "")
        #expect(item.firstSeenAt == Fixture.now)
        #expect(item.lastSeenAt == Fixture.now)
        #expect(item.updatedAt == Fixture.now)
        #expect(item.resolvedAt == nil)
        #expect(item.lastChangedBy == "morning")
        #expect(item.history.count == 1)
        #expect(item.history[0].change == "created")
        #expect(item.history[0].by == "morning")
    }

    @Test("a new item without a title is refused")
    func emptyTitleThrows() async {
        let store = ItemStore()
        await #expect(throws: PulseStoreError.emptyTitle("calendar:event:1")) {
            try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "")], run: "run", now: Fixture.now)
        }
        await #expect(throws: (any Error).self) {
            try await store.upsert(detected: [Fixture.detected("calendar:event:2", title: nil)], run: "run", now: Fixture.now)
        }
        #expect(await store.count() == 0)
    }

    @Test("an unknown id prefix creates a source of other")
    func unknownPrefixBecomesOther() async throws {
        let store = ItemStore()
        try await store.upsert(detected: [Fixture.detected("mystery:thing:1")], run: "run", now: Fixture.now)
        #expect(await store.item(id: "mystery:thing:1")?.source == .other)
    }

    @Test("a malformed id is refused")
    func malformedIdentifierThrows() async {
        let store = ItemStore()
        await #expect(throws: (any Error).self) {
            try await store.upsert(detected: [Fixture.detected("nocolon")], run: "run", now: Fixture.now)
        }
    }

    @Test("a capture pass cannot assert a user-only status")
    func captureCannotSetTerminalStatus() async {
        let store = ItemStore()
        for status in [Status.done, .dismissed, .snoozed] {
            await #expect(throws: (any Error).self) {
                try await store.upsert(
                    detected: [DetectedItem(id: "calendar:event:x", title: "T", status: status)],
                    run: "run",
                    now: Fixture.now
                )
            }
        }
    }

    @Test("a run name is required")
    func missingRunThrows() async {
        let store = ItemStore()
        await #expect(throws: PulseStoreError.missingRun) {
            try await store.upsert(detected: [], run: "  ", now: Fixture.now)
        }
    }

    // MARK: - Update semantics

    @Test("a second pass with the same values reports unchanged and does not bump updatedAt")
    func unchangedPass() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "Standup")], run: "morning", now: Fixture.now)

        let later = Fixture.now.addingTimeInterval(900)
        let result = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "Standup")], run: "evening", now: later)

        #expect(result.unchanged == ["calendar:event:1"])
        #expect(result.updated.isEmpty)
        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.lastSeenAt == later)          // bumped by every pass
        #expect(item.updatedAt == Fixture.now)      // untouched, nothing changed
        #expect(item.lastChangedBy == "morning")
        #expect(item.history.count == 1)            // no new entry
    }

    @Test("a changed field bumps updatedAt, lastChangedBy and history")
    func changedField() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "Standup")], run: "morning", now: Fixture.now)

        let later = Fixture.now.addingTimeInterval(900)
        let result = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "Standup (moved)", detail: "Room 2")],
            run: "evening",
            now: later
        )

        #expect(result.updated == [UpsertResult.Update(id: "calendar:event:1", fields: ["title", "detail"])])
        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.title == "Standup (moved)")
        #expect(item.detail == "Room 2")
        #expect(item.updatedAt == later)
        #expect(item.lastChangedBy == "evening")
        #expect(item.history.last?.change == "title,detail")
    }

    // MARK: - Sticky state

    @Test("done is sticky: descriptive fields update, status does not")
    func stickyDone() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "Standup")], run: "morning", now: Fixture.now)
        _ = try await store.userAction(id: "calendar:event:1", verb: .done, now: Fixture.now)

        let later = Fixture.now.addingTimeInterval(3600)
        let newDue = Fixture.date("2026-10-25T09:00:00.000Z")
        let result = try await store.upsert(
            detected: [Fixture.detected(
                "calendar:event:1",
                title: "Standup (renamed)",
                detail: "new detail",
                url: "https://example.com/x",
                due: newDue,
                people: ["Ada"],
                quickActions: [QuickAction(label: "Decline", text: "no")]
            )],
            run: "evening",
            now: later
        )

        let item = try #require(await store.item(id: "calendar:event:1"))
        // Descriptive fields moved...
        #expect(item.title == "Standup (renamed)")
        #expect(item.detail == "new detail")
        #expect(item.url == "https://example.com/x")
        #expect(item.due == newDue)
        #expect(item.people == ["Ada"])
        #expect(item.quickActions == [QuickAction(label: "Decline", text: "no")])
        // ...status did not, and the user's timestamps are untouched.
        #expect(item.status == .done)
        #expect(item.updatedAt == Fixture.now)
        #expect(item.resolvedAt == Fixture.now)
        #expect(result.keptUserState == [UpsertResult.KeptUserState(id: "calendar:event:1", status: .done)])
        #expect(result.updated.isEmpty)
        // A non-descriptive change (kind/priority) is ignored wholesale on a
        // sticky item; `stickyIgnoresNonDescriptiveFields` asserts that directly.
    }

    @Test("a non-descriptive field does not move on a sticky item")
    func stickyIgnoresNonDescriptiveFields() async throws {
        let store = ItemStore()
        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T", kind: .deadline, priority: .normal)],
            run: "morning",
            now: Fixture.now
        )
        _ = try await store.userAction(id: "calendar:event:1", verb: .dismiss, now: Fixture.now)

        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", kind: .conflict, priority: .high)],
            run: "evening",
            now: Fixture.now.addingTimeInterval(60)
        )

        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.kind == .deadline)
        #expect(item.priority == .normal)
        #expect(item.status == .dismissed)
    }

    @Test("dismissed is sticky too")
    func stickyDismissed() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("gmail:message:1", title: "Reply?")], run: "run", now: Fixture.now)
        _ = try await store.userAction(id: "gmail:message:1", verb: .dismiss, now: Fixture.now)

        let result = try await store.upsert(
            detected: [Fixture.detected("gmail:message:1", title: "Reply!")],
            run: "run",
            now: Fixture.now.addingTimeInterval(10)
        )
        #expect(result.keptUserState.first?.status == .dismissed)
    }

    // MARK: - Reopen

    @Test("reopening without a reason throws")
    func reopenNeedsReason() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        _ = try await store.userAction(id: "calendar:event:1", verb: .done, now: Fixture.now)

        await #expect(throws: PulseStoreError.reopenRequiresReason("calendar:event:1")) {
            try await store.upsert(
                detected: [DetectedItem(id: "calendar:event:1", reopen: true)],
                run: "run",
                now: Fixture.now.addingTimeInterval(60)
            )
        }
        await #expect(throws: (any Error).self) {
            try await store.upsert(
                detected: [DetectedItem(id: "calendar:event:1", reopen: true, reason: "  ")],
                run: "run",
                now: Fixture.now
            )
        }
        #expect(await store.item(id: "calendar:event:1")?.status == .done)
    }

    @Test("reopening with a reason moves to open, clears the close, and records history")
    func reopenWithReason() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        _ = try await store.userAction(id: "calendar:event:1", verb: .done, reason: "handled", now: Fixture.now)

        let later = Fixture.now.addingTimeInterval(3600)
        let result = try await store.upsert(
            detected: [DetectedItem(id: "calendar:event:1", reopen: true, reason: "new reply arrived")],
            run: "run",
            now: later
        )

        #expect(result.reopened == ["calendar:event:1"])
        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.status == .open)
        #expect(item.resolvedAt == nil)
        #expect(item.snoozedUntil == nil)
        #expect(item.updatedAt == later)
        #expect(item.history.last?.change == "reopened")
        #expect(item.history.last?.reason == "new reply arrived")
    }

    @Test("reopening honours a supplied non-resolved status")
    func reopenToWaiting() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        _ = try await store.userAction(id: "calendar:event:1", verb: .done, now: Fixture.now)

        _ = try await store.upsert(
            detected: [DetectedItem(id: "calendar:event:1", status: .waiting, reopen: true, reason: "waiting on Ada")],
            run: "run",
            now: Fixture.now.addingTimeInterval(60)
        )
        #expect(await store.item(id: "calendar:event:1")?.status == .waiting)
    }

    // MARK: - Snooze

    @Test("snoozing requires an until time")
    func snoozeNeedsUntil() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        await #expect(throws: PulseStoreError.snoozeRequiresUntil("calendar:event:1")) {
            try await store.userAction(id: "calendar:event:1", verb: .snooze, now: Fixture.now)
        }
    }

    @Test("an active snooze is sticky against capture")
    func activeSnoozeIsSticky() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        let until = Fixture.now.addingTimeInterval(3600)
        _ = try await store.userAction(id: "calendar:event:1", verb: .snooze, until: until, now: Fixture.now)

        let result = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T renamed", status: .waiting)],
            run: "run",
            now: Fixture.now.addingTimeInterval(600)
        )
        #expect(result.keptUserState.first?.status == .snoozed)
        #expect(await store.item(id: "calendar:event:1")?.status == .snoozed)
    }

    @Test("an expired snooze reads as open and normalises on the next pass")
    func expiredSnooze() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        let until = Fixture.now.addingTimeInterval(600)
        _ = try await store.userAction(id: "calendar:event:1", verb: .snooze, until: until, now: Fixture.now)

        let after = until.addingTimeInterval(1)
        // Pure read: still stored as snoozed, but reads as open.
        #expect(await store.effectiveStatus(of: "calendar:event:1", at: after) == .open)
        #expect(await store.item(id: "calendar:event:1")?.status == .snoozed)

        let result = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T")],
            run: "run",
            now: after
        )
        #expect(result.updated.contains { $0.id == "calendar:event:1" && $0.fields.contains("snooze-expired") })

        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.status == .open)          // normalised
        #expect(item.snoozedUntil == nil)
        #expect(item.history.last?.change.contains("snooze-expired") == true)
    }

    @Test("effectiveStatus leaves a future snooze alone")
    func activeSnoozeReadsSnoozed() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        let until = Fixture.now.addingTimeInterval(600)
        _ = try await store.userAction(id: "calendar:event:1", verb: .snooze, until: until, now: Fixture.now)
        #expect(await store.effectiveStatus(of: "calendar:event:1", at: Fixture.now.addingTimeInterval(1)) == .snoozed)
        // Exactly at the boundary the snooze is over, matching `<=` in store.mjs.
        #expect(await store.effectiveStatus(of: "calendar:event:1", at: until) == .open)
    }

    // MARK: - Resolution

    @Test("losing an item resolves it, and detecting it again reopens it")
    func resolvedRoundTrips() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)

        let later = Fixture.now.addingTimeInterval(600)
        let result = try await store.upsert(
            detected: [DetectedItem(id: "calendar:event:1", status: .resolved, reason: "event deleted")],
            run: "run",
            now: later
        )
        #expect(result.resolved == ["calendar:event:1"])
        var item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.status == .resolved)
        #expect(item.resolvedAt == later)
        #expect(item.resolution == "event deleted")

        // `resolved` is not sticky: a later detection brings it back to open
        // and clears resolvedAt.
        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", status: .open)],
            run: "run",
            now: later.addingTimeInterval(600)
        )
        item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.status == .open)
        #expect(item.resolvedAt == nil)
    }

    // MARK: - History cap

    @Test("60 changes leave exactly 50 history entries, newest last")
    func historyCap() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "v0")], run: "run", now: Fixture.now)

        // 1 creation + 60 updates. Each title differs so each is a real change.
        for index in 1...60 {
            _ = try await store.upsert(
                detected: [Fixture.detected("calendar:event:1", title: "v\(index)")],
                run: "run",
                now: Fixture.now.addingTimeInterval(Double(index))
            )
        }

        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.history.count == 50)
        // Oldest entries were dropped: the creation entry is long gone.
        #expect(item.history.first?.change == "title")
        // The newest entry is last and corresponds to the final update.
        #expect(item.history.last?.change == "title")
        #expect(item.history.last?.at == Fixture.now.addingTimeInterval(60))
    }

    // MARK: - userAction

    @Test("done sets resolvedAt and resolution, and is terminal")
    func doneSetsResolution() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)

        let later = Fixture.now.addingTimeInterval(300)
        let item = try await store.userAction(id: "calendar:event:1", verb: .done, reason: "declined", now: later)

        #expect(item.status == .done)
        #expect(item.resolvedAt == later)
        #expect(item.resolution == "declined")
        #expect(item.snoozedUntil == nil)
        #expect(item.updatedAt == later)
        #expect(item.lastChangedBy == "user")
        #expect(item.history.last?.change == "done")
        #expect(item.history.last?.reason == "declined")
    }

    @Test("dismiss is terminal and records dismissed")
    func dismissIsTerminal() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        let item = try await store.userAction(id: "calendar:event:1", verb: .dismiss, now: Fixture.now)
        #expect(item.status == .dismissed)
        #expect(item.resolvedAt == Fixture.now)
        #expect(item.history.last?.change == "dismissed")
    }

    @Test("reopen clears resolvedAt and lands on open")
    func reopenClearsResolvedAt() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        _ = try await store.userAction(id: "calendar:event:1", verb: .done, reason: "x", now: Fixture.now)

        let later = Fixture.now.addingTimeInterval(300)
        let item = try await store.userAction(id: "calendar:event:1", verb: .reopen, now: later)
        #expect(item.status == .open)
        #expect(item.resolvedAt == nil)
        #expect(item.snoozedUntil == nil)
        #expect(item.history.last?.change == "open")
    }

    @Test("a snooze records the until in history")
    func snoozeHistoryCarriesUntil() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        let until = Fixture.now.addingTimeInterval(3600)
        let item = try await store.userAction(id: "calendar:event:1", verb: .snooze, until: until, now: Fixture.now)
        #expect(item.status == .snoozed)
        #expect(item.snoozedUntil == until)
        #expect(item.history.last?.until == until)
    }

    @Test("userAction on an unknown item throws")
    func unknownItemThrows() async {
        let store = ItemStore()
        await #expect(throws: PulseStoreError.unknownItem("nope:1")) {
            try await store.userAction(id: "nope:1", verb: .done, now: Fixture.now)
        }
    }

    // MARK: - Reads

    @Test("list filters by effective status and source, and sorts")
    func listFiltering() async throws {
        let store = ItemStore()
        _ = try await store.upsert(
            detected: [
                Fixture.detected("calendar:event:1", title: "Cal", priority: .low),
                Fixture.detected("gmail:message:1", title: "Mail", priority: .high),
                Fixture.detected("calendar:event:2", title: "Done"),
            ],
            run: "run",
            now: Fixture.now
        )
        _ = try await store.userAction(id: "calendar:event:2", verb: .done, now: Fixture.now)

        let all = await store.list(at: Fixture.now)
        #expect(all.map(\.id) == ["gmail:message:1", "calendar:event:1"])

        let mailOnly = await store.list(sources: [.gmail], at: Fixture.now)
        #expect(mailOnly.map(\.id) == ["gmail:message:1"])

        let closed = await store.list(statuses: [.done], at: Fixture.now)
        #expect(closed.map(\.id) == ["calendar:event:2"])
    }

    @Test("item(id:) returns nil rather than throwing for a miss")
    func itemLookupMiss() async {
        let store = ItemStore()
        #expect(await store.item(id: "nothing:1") == nil)
    }

    @Test("markSeen records lastViewedAt")
    func markSeen() async {
        let store = ItemStore()
        let stamp = Fixture.now
        #expect(await store.lastViewed() == nil)
        await store.markSeen(at: stamp)
        #expect(await store.lastViewed() == stamp)
    }

    @Test("allItems keeps insertion order")
    func allItemsIsStable() async throws {
        let store = ItemStore()
        _ = try await store.upsert(
            detected: ["calendar:event:b", "calendar:event:a", "calendar:event:c"].map { Fixture.detected($0, title: $0) },
            run: "run",
            now: Fixture.now
        )
        #expect(await store.allItems().map(\.id) == ["calendar:event:b", "calendar:event:a", "calendar:event:c"])
    }

    // MARK: - Seeding + snapshot

    @Test("a store can be seeded from a decoded snapshot and round-trips back out")
    func snapshotRoundTripThroughStore() async throws {
        let original = Fixture.fullItem()
        let store = ItemStore(items: [original], lastViewedAt: Fixture.now)
        let snapshot = await store.makeSnapshot(now: Fixture.now, deviceName: "iPhone")

        #expect(snapshot.items.count == 1)
        #expect(snapshot.items[0] == original)
        #expect(snapshot.lastViewedAt == Fixture.now)
        #expect(snapshot.schemaVersion == 1)

        let decoded = try PulseJSON.decode(PulseSnapshot.self, from: try PulseJSON.encode(snapshot))
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].id == "calendar:event:ABC-123")
    }

    @Test("makeSnapshot prunes closed items past the retention window")
    func snapshotPrunes() async throws {
        let store = ItemStore()
        _ = try await store.upsert(detected: [Fixture.detected("calendar:event:1", title: "T")], run: "run", now: Fixture.now)
        _ = try await store.userAction(id: "calendar:event:1", verb: .done, now: Fixture.now)

        let soon = await store.makeSnapshot(now: Fixture.now.addingTimeInterval(60), deviceName: "iPhone")
        #expect(soon.items.count == 1)

        let muchLater = await store.makeSnapshot(now: Fixture.now.addingTimeInterval(4 * 86_400), deviceName: "iPhone")
        #expect(muchLater.items.isEmpty)
    }
}
