import Foundation
import PulseCore

/// The seam between the views and the domain store.
///
/// The real implementation is `ItemStore` (an `actor` in `PulseCore`); previews
/// and tests use `FakeItemStore` from `PreviewSupport`. Declaring it here rather
/// than in `PulseCore` keeps the package free of UI-driven API and lets the app
/// add fakes without touching the other agent's work.
public protocol ItemStoring: Sendable {
    func allItems() async -> [PulseItem]
    func item(id: PulseItem.ID) async -> PulseItem?
    func board(at instant: Date, calendar: Calendar) async -> [Horizon: [PulseItem]]
    func lastViewed() async -> Date?
    @discardableResult func markSeen(at instant: Date) async -> Date
    func userAction(
        id: PulseItem.ID,
        verb: ItemActionVerb,
        until: Date?,
        reason: String?,
        by: String,
        now: Date
    ) async throws -> PulseItem
    func upsert(detected: [DetectedItem], run: String, now: Date) async throws -> UpsertResult
}

/// Adapts the domain actor to the seam. `ItemStore` is not modified.
public struct StoreAdapter: ItemStoring {
    public let store: ItemStore

    public init(_ store: ItemStore) {
        self.store = store
    }

    public func allItems() async -> [PulseItem] { await store.allItems() }

    public func item(id: PulseItem.ID) async -> PulseItem? { await store.item(id: id) }

    public func board(at instant: Date, calendar: Calendar) async -> [Horizon: [PulseItem]] {
        await store.board(at: instant, calendar: calendar)
    }

    public func lastViewed() async -> Date? { await store.lastViewed() }

    @discardableResult
    public func markSeen(at instant: Date) async -> Date { await store.markSeen(at: instant) }

    public func userAction(
        id: PulseItem.ID,
        verb: ItemActionVerb,
        until: Date?,
        reason: String?,
        by: String,
        now: Date
    ) async throws -> PulseItem {
        try await store.userAction(id: id, verb: verb, until: until, reason: reason, by: by, now: now)
    }

    public func upsert(detected: [DetectedItem], run: String, now: Date) async throws -> UpsertResult {
        try await store.upsert(detected: detected, run: run, now: now)
    }
}
