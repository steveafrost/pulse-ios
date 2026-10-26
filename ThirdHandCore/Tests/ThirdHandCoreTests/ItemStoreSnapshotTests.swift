import Foundation
import Testing
@testable import ThirdHandCore

/// Seeding and snapshotting, split out of `ItemStoreTests` because that file had grown
/// past the 400-line body limit and the two halves read as separate concerns: one is
/// what a capture pass does to the store, this one is what the store hands to disk.
@Suite("ItemStore seeding and snapshots")
struct ItemStoreSnapshotTests {
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

        let decoded = try ThirdHandJSON.decode(ThirdHandSnapshot.self, from: ThirdHandJSON.encode(snapshot))
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].id == "calendar:event:ABC-123")
    }

    @Test("makeSnapshot prunes closed items past the retention window")
    func snapshotPrunes() async throws {
        let store = ItemStore()
        _ = try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "T")],
            run: "run",
            now: Fixture.now
        )
        _ = try await store.userAction(id: "calendar:event:1", verb: .done, now: Fixture.now)

        let soon = await store.makeSnapshot(now: Fixture.now.addingTimeInterval(60), deviceName: "iPhone")
        #expect(soon.items.count == 1)

        let muchLater = await store.makeSnapshot(now: Fixture.now.addingTimeInterval(4 * 86400), deviceName: "iPhone")
        #expect(muchLater.items.isEmpty)
    }
}
