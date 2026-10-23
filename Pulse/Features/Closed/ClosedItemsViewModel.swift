import Foundation
import Observation
import PulseCore

/// #19: closed items from the last three days, grouped by day, newest first,
/// paged 50 at a time.
@MainActor
@Observable
public final class ClosedItemsViewModel {
    public struct DayGroup: Sendable, Identifiable {
        public var id: Date
        public var title: String
        public var items: [PulseItem]
    }

    public private(set) var groups: [DayGroup] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let store: any ItemStoring
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private let pageSize: Int

    private var allClosed: [PulseItem] = []
    private var visibleCount: Int

    public init(
        store: any ItemStoring,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        pageSize: Int = 50
    ) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
        self.pageSize = pageSize
        self.visibleCount = pageSize
    }

    public var now: Date { clock() }

    public var canLoadMore: Bool { visibleCount < allClosed.count }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let cutoff = clock().addingTimeInterval(-3 * 86_400)
        allClosed = await store.allItems()
            .filter { $0.status.isClosed }
            .filter { ($0.resolvedAt ?? $0.updatedAt) >= cutoff }
            .sorted { ($0.resolvedAt ?? $0.updatedAt) > ($1.resolvedAt ?? $1.updatedAt) }
        rebuild()
    }

    public func loadMore() {
        visibleCount += pageSize
        rebuild()
    }

    public func reopen(_ item: PulseItem, reason: String) async {
        do {
            _ = try await store.userAction(
                id: item.id,
                verb: .reopen,
                until: nil,
                reason: reason,
                by: "user",
                now: clock()
            )
            await load()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't reopen that. Try again."
        }
    }

    /// §19: a non-empty reason is required to reopen.
    public func canReopen(reason: String) -> Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func rebuild() {
        let visible = allClosed.prefix(visibleCount)
        let byDay = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.resolvedAt ?? $0.updatedAt) }
        groups = byDay.keys.sorted(by: >).map { day in
            DayGroup(
                id: day,
                title: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                items: byDay[day] ?? []
            )
        }
    }
}
