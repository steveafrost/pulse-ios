import Foundation
import Testing
@testable import ThirdHandCore

/// `userAction` and the read paths, split out of `ItemStoreTests` for the same reason as
/// `ItemStoreSnapshotTests`: the suite was over the body-length limit, and "what a verb
/// does to one item" is a different subject from "what a capture pass does to the store".
@Suite("ItemStore actions and reads")
struct ItemStoreActionTests {
    // MARK: - userAction

    @Test("done sets resolvedAt and resolution, and is terminal")
    func doneSetsResolution() async throws {
        let store = ItemStore()
        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T")],
            run: "run",
            now: Fixture.now
        )

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
        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T")],
            run: "run",
            now: Fixture.now
        )
        let item = try await store.userAction(id: "calendar:event:1", verb: .dismiss, now: Fixture.now)
        #expect(item.status == .dismissed)
        #expect(item.resolvedAt == Fixture.now)
        #expect(item.history.last?.change == "dismissed")
    }

    @Test("reopen clears resolvedAt and lands on open")
    func reopenClearsResolvedAt() async throws {
        let store = ItemStore()
        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T")],
            run: "run",
            now: Fixture.now
        )
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
        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T")],
            run: "run",
            now: Fixture.now
        )
        let until = Fixture.now.addingTimeInterval(3600)
        let item = try await store.userAction(id: "calendar:event:1", verb: .snooze, until: until, now: Fixture.now)
        #expect(item.status == .snoozed)
        #expect(item.snoozedUntil == until)
        #expect(item.history.last?.until == until)
    }

    @Test("userAction on an unknown item throws")
    func unknownItemThrows() async {
        let store = ItemStore()
        await #expect(throws: ThirdHandStoreError.unknownItem("nope:1")) {
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
                Fixture.detected("calendar:event:2", title: "Done")
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
            detected: ["calendar:event:b", "calendar:event:a", "calendar:event:c"]
                .map { Fixture.detected($0, title: $0) },
            run: "run",
            now: Fixture.now
        )
        #expect(await store.allItems().map(\.id) == ["calendar:event:b", "calendar:event:a", "calendar:event:c"])
    }
}
