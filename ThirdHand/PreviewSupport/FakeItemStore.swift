#if DEBUG
import Foundation
import ThirdHandCore

/// In-memory `ItemStoring` for previews and tests. It runs the real rules by
/// delegating to `ThirdHandCore.ItemStore`, so a preview shows the same ordering and
/// state machine the app does — it just never touches disk or EventKit.
public struct FakeItemStore: ItemStoring {
    private let store: ItemStore

    public init(items: [ThirdHandItem] = [], lastViewedAt: Date? = nil) {
        store = ItemStore(items: items, lastViewedAt: lastViewedAt)
    }

    public func allItems() async -> [ThirdHandItem] { await store.allItems() }

    public func item(id: ThirdHandItem.ID) async -> ThirdHandItem? { await store.item(id: id) }

    public func board(at instant: Date, calendar: Calendar) async -> [Horizon: [ThirdHandItem]] {
        await store.board(at: instant, calendar: calendar)
    }

    public func lastViewed() async -> Date? { await store.lastViewed() }

    @discardableResult
    public func markSeen(at instant: Date) async -> Date { await store.markSeen(at: instant) }

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

/// A capture engine that returns a fixed outcome, and optionally fails one source.
public struct FakeCaptureEngine: CaptureProviding {
    public var outcome: CaptureOutcome

    public init(outcome: CaptureOutcome) {
        self.outcome = outcome
    }

    public init(items: [ThirdHandItem] = [], failures: [SourceFailure] = [], at instant: Date = Fixtures.fixtureNow) {
        let detected = items.map { item in
            DetectedItem(
                id: item.id,
                source: item.source,
                kind: item.kind,
                title: item.title,
                detail: item.detail,
                url: item.url,
                due: item.due,
                priority: item.priority,
                people: item.people,
                status: item.status.isCapturable ? item.status : .open,
                quickActions: item.quickActions
            )
        }
        outcome = CaptureOutcome(detected: detected, failures: failures, ranAt: instant)
    }

    public func capture(now: Date) async -> CaptureOutcome {
        var copy = outcome
        copy.ranAt = now
        return copy
    }
}

/// A clock pinned to `Fixtures.fixtureNow`.
public func fixtureClock(_ date: Date = Fixtures.fixtureNow) -> @Sendable () -> Date {
    { date }
}
#endif
