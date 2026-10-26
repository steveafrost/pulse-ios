import Foundation
import ThirdHandCore

/// The seam between the views and the domain store.
///
/// The real implementation is `ItemStore` (an `actor` in `ThirdHandCore`); previews
/// and tests use `FakeItemStore` from `PreviewSupport`. Declaring it here rather
/// than in `ThirdHandCore` keeps the package free of UI-driven API and lets the app
/// add fakes without touching the other agent's work.
public protocol ItemStoring: Sendable {
    func allItems() async -> [ThirdHandItem]
    func item(id: ThirdHandItem.ID) async -> ThirdHandItem?
    func board(at instant: Date, calendar: Calendar) async -> [Horizon: [ThirdHandItem]]
    func lastViewed() async -> Date?
    @discardableResult func markSeen(at instant: Date) async -> Date
    // Six parameters is the user's own vocabulary -- what, which verb, until when, why,
    // by whom, at what instant -- and `docs/DATA-CONTRACT.md` names all six in one record.
    // Bundling them into an options struct would move that vocabulary one level away from
    // the call sites, in an API that exists to be a seam, not a convenience.
    // swiftlint:disable:next function_parameter_count
    func userAction(
        id: ThirdHandItem.ID,
        verb: ItemActionVerb,
        until: Date?,
        reason: String?,
        by: String,
        now: Date
    ) async throws -> ThirdHandItem
    func upsert(detected: [DetectedItem], run: String, now: Date) async throws -> UpsertResult
}

/// Adapts the domain actor to the seam. `ItemStore` is not modified.
public struct StoreAdapter: ItemStoring {
    public let store: ItemStore

    public init(_ store: ItemStore) {
        self.store = store
    }

    public func allItems() async -> [ThirdHandItem] {
        await store.allItems()
    }

    public func item(id: ThirdHandItem.ID) async -> ThirdHandItem? {
        await store.item(id: id)
    }

    public func board(at instant: Date, calendar: Calendar) async -> [Horizon: [ThirdHandItem]] {
        await store.board(at: instant, calendar: calendar)
    }

    public func lastViewed() async -> Date? {
        await store.lastViewed()
    }

    @discardableResult
    public func markSeen(at instant: Date) async -> Date {
        await store.markSeen(at: instant)
    }

    // Same signature as the protocol; the reason is stated there.
    // swiftlint:disable:next function_parameter_count
    public func userAction(
        id: ThirdHandItem.ID,
        verb: ItemActionVerb,
        until: Date?,
        reason: String?,
        by: String,
        now: Date
    ) async throws -> ThirdHandItem {
        try await store.userAction(id: id, verb: verb, until: until, reason: reason, by: by, now: now)
    }

    public func upsert(detected: [DetectedItem], run: String, now: Date) async throws -> UpsertResult {
        try await store.upsert(detected: detected, run: run, now: now)
    }
}
