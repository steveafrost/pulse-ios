import Foundation
import Observation
import ThirdHandCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The board's state owner (#17). `@MainActor @Observable`, so views read
/// properties and call intents, and nothing here touches EventKit, disk or the
/// clock directly: the store, capture engine, persistence and `now` are all
/// injected.
@MainActor
@Observable
public final class BoardViewModel {
    // MARK: Dependencies

    private let store: any ItemStoring
    private let capture: any CaptureProviding
    private let persistence: any BoardPersisting
    private let shared: SharedStore
    private let calendar: Calendar
    private let markSeenOnLoad: Bool

    /// The sync loop, when the app is running with one. Optional so previews, tests
    /// and the debug screen keep working with no container at all -- the board
    /// functioned before sync existed and must not depend on it.
    public private(set) var sync: SyncCoordinator?

    #if canImport(ActivityKit) && os(iOS)
    /// The Live Activity owner (#31), when this build has one. Optional so previews
    /// and tests run without ActivityKit and without the app group.
    var liveActivity: ImminentMeetingController?
    #endif

    /// Injectable clock. A preview pins it; the app passes `Date.init`.
    private let clock: @Sendable () -> Date

    // MARK: State

    public private(set) var state: BoardState = .loading
    public private(set) var board: [Horizon: [ThirdHandItem]] = [:]
    public private(set) var captureStatus: CaptureStatusModel = .init(phase: .idle(nil), itemCount: 0)
    public private(set) var permissionState = PermissionState()
    public private(set) var lastViewedAt: Date?
    public private(set) var errorMessage: String?

    public var filter: BoardFilter = .all {
        didSet { if filter != oldValue { persistFilter() } }
    }

    /// §4.1: expanded sections are per-session, never persisted.
    public private(set) var expandedHorizons: Set<Horizon> = []

    /// The instant the board is rendered against.
    public var nowDate: Date { clock() }

    public init(
        store: any ItemStoring,
        capture: any CaptureProviding,
        persistence: any BoardPersisting = InMemoryBoardPersistence(),
        shared: SharedStore = SharedStore(),
        permissionState: PermissionState = PermissionState(),
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { Date() },
        markSeenOnLoad: Bool = true,
        sync: SyncCoordinator? = nil
    ) {
        self.store = store
        self.capture = capture
        self.persistence = persistence
        self.shared = shared
        self.permissionState = permissionState
        self.calendar = calendar
        self.clock = clock
        self.markSeenOnLoad = markSeenOnLoad
        self.sync = sync
        self.filter = Self.restoreFilter(shared)
    }

    // MARK: Reads

    /// The items of one section after filtering, in board order.
    public func items(in horizon: Horizon) -> [ThirdHandItem] {
        filter.apply(to: board[horizon] ?? [])
    }

    public var filteredItems: [ThirdHandItem] {
        Horizon.allCases.flatMap { items(in: $0) }
    }

    public var totalCount: Int { filteredItems.count }

    /// The Now count shown on the "All" chip. `.fyi` never contributes (§1).
    public var nowCount: Int {
        (board[.now] ?? []).filter { $0.kind != .fyi }.count
    }

    /// §8.1: the FAB resolves the topmost open Now item; `title` doubles as its
    /// VoiceOver label so the two cannot disagree.
    public var topNowItem: ThirdHandItem? {
        items(in: .now).first
    }

    public var fabTitle: String {
        topNowItem == nil ? "Refresh board" : "Done"
    }

    public var fabCaption: String? { topNowItem?.title }

    /// Sources present on the board, in §8.1 order, with counts for the chips.
    public var availableSources: [(identity: SourceIdentity, count: Int)] {
        let items = Horizon.allCases.flatMap { board[$0] ?? [] }
        let grouped = Dictionary(grouping: items, by: \.sourceIdentity)
        return SourceIdentity.filterOrder.compactMap { identity in
            guard let matches = grouped[identity], !matches.isEmpty else { return nil }
            return (identity, matches.count)
        }
    }

    /// §9.4: a zero-item section is never rendered — unless the board is fully empty.
    public var visibleHorizons: [Horizon] {
        Horizon.allCases.filter { !items(in: $0).isEmpty }
    }

    public func visibleItems(in horizon: Horizon) -> [ThirdHandItem] {
        let all = items(in: horizon)
        guard !expandedHorizons.contains(horizon) else { return all }
        return Array(all.prefix(horizon.collapseLimit))
    }

    public func hiddenCount(in horizon: Horizon) -> Int {
        max(0, items(in: horizon).count - horizon.collapseLimit)
    }

    public func isExpanded(_ horizon: Horizon) -> Bool { expandedHorizons.contains(horizon) }

    public func toggleExpansion(_ horizon: Horizon) {
        if expandedHorizons.contains(horizon) {
            expandedHorizons.remove(horizon)
        } else {
            expandedHorizons.insert(horizon)
        }
    }

    /// The detail route for one item.
    public func detailModel(for item: ThirdHandItem) -> ItemDetailViewModel {
        ItemDetailViewModel(item: item, store: store, clock: clock)
    }

    public func closedModel() -> ClosedItemsViewModel {
        ClosedItemsViewModel(store: store, clock: clock, calendar: calendar)
    }

    // MARK: Intents

    /// First paint: read the store, project the board, decide the state.
    public func load() async {
        let now = nowDate
        lastViewedAt = await store.lastViewed()
        board = await store.board(at: now, calendar: calendar)
        captureStatus = CaptureStatusModel(
            phase: .idle(shared.date(.lastCaptureAt)),
            itemCount: totalCount,
            syncText: syncStatusText
        )
        state = Self.state(
            board: board,
            filter: filter,
            failures: [],
            lastCapturedAt: shared.date(.lastCaptureAt),
            now: now
        )
        persist()
    }

    /// The FAB and the capsule: a full capture pass.
    public func refresh() async {
        captureStatus = CaptureStatusModel(phase: .capturing, itemCount: totalCount, syncText: syncStatusText)
        let now = nowDate
        let outcome = await capture.capture(now: now)
        if !outcome.detected.isEmpty {
            _ = try? await store.upsert(detected: outcome.detected, run: "foreground", now: outcome.ranAt)
        }
        shared.set(outcome.ranAt, for: .lastCaptureAt)
        board = await store.board(at: nowDate, calendar: calendar)
        // The Mac mirror sees every capture pass, not just user actions.
        sync?.publishSoon()
        captureStatus = CaptureStatusModel(
            phase: outcome.failures.isEmpty ? .idle(outcome.ranAt) : .failed(outcome.ranAt),
            itemCount: totalCount,
            syncText: syncStatusText
        )
        state = Self.state(
            board: board,
            filter: filter,
            failures: outcome.failures,
            lastCapturedAt: outcome.ranAt,
            now: nowDate
        )
        persist()
    }

    public func setFilter(_ filter: BoardFilter) {
        self.filter = filter
        recomputeState()
    }

    public func resetFilters() {
        setFilter(.all)
    }

    public func setPermissionState(_ state: PermissionState) {
        permissionState = state
        recomputeState()
    }

    /// The sync state the capsule appends to the capture line, or `nil` when this
    /// build has no container.
    public var syncStatusText: String? {
        guard let sync else { return nil }
        switch sync.phase {
        // §8.1: the capsule names the user's Mac, never the transport. "Syncing"
        // and "publishing a snapshot" describe files; the user is sending their
        // board to the Mac they set up.
        case .syncing: return "Sending to your Mac\u{2026}"
        case .failed(let message): return message
        // Never the "Mac · 2m ago" line here: that sentence is a claim the Mac
        // has the data, and in this state it does not.
        case .notConnected(let reason): return reason
        case .idle:
            guard let published = sync.lastPublishedAt else { return nil }
            return "Mac \u{00B7} \(ThirdHandDateFormat.relative(published, now: nowDate))"
        }
    }

    /// §7.2: Done from the FAB, a row control or the overflow menu. Optimistic:
    /// the board is re-read from the store straight away.
    public func complete(_ item: ThirdHandItem) async {
        await perform(item, verb: .done, until: nil, reason: nil)
    }

    public func dismiss(_ item: ThirdHandItem) async {
        await perform(item, verb: .dismiss, until: nil, reason: nil)
    }

    public func snooze(_ item: ThirdHandItem, until: Date) async {
        await perform(item, verb: .snooze, until: until, reason: nil)
    }

    public func reopen(_ item: ThirdHandItem, reason: String) async {
        await perform(item, verb: .reopen, until: nil, reason: reason)
    }

    /// Recomputes only the capsule's sync line, e.g. after a publish advances
    /// `lastPublishedAt` without changing any item.
    public func refreshSyncStatus() {
        captureStatus = CaptureStatusModel(
            phase: captureStatus.phase,
            itemCount: captureStatus.itemCount,
            syncText: syncStatusText
        )
    }

    /// Re-reads the board after the sync layer applied a mirror command, so a Done
    /// tapped on the Mac appears without waiting for the next capture pass.
    public func reloadAfterSync() async {
        board = await store.board(at: nowDate, calendar: calendar)
        captureStatus = CaptureStatusModel(
            phase: captureStatus.phase,
            itemCount: totalCount,
            syncText: syncStatusText
        )
        recomputeState()
        persist()
    }

    /// Marks the board seen. §5.2 newness clears when the board is left.
    public func markSeen() async {
        guard markSeenOnLoad else { return }
        let seen = await store.markSeen(at: nowDate)
        lastViewedAt = seen
        shared.set(seen, for: .lastViewedAt)
        // `lastViewedAt` is part of the envelope, so the Mac can dim what the user
        // has already seen.
        sync?.publishSoon()
    }

    private func perform(_ item: ThirdHandItem, verb: ItemActionVerb, until: Date?, reason: String?) async {
        do {
            _ = try await store.userAction(
                id: item.id,
                verb: verb,
                until: until,
                reason: reason,
                by: "user",
                now: nowDate
            )
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save that. Try again."
        }
        board = await store.board(at: nowDate, calendar: calendar)
        recomputeState()
        persist()
        // Debounced: a burst of Done taps writes one snapshot.
        sync?.publishSoon()
    }

    // MARK: State derivation

    private func recomputeState() {
        state = Self.state(
            board: board,
            filter: filter,
            failures: state.failures,
            lastCapturedAt: shared.date(.lastCaptureAt),
            now: nowDate
        )
    }

    /// Pure so the tests and previews can assert every case.
    static func state(
        board: [Horizon: [ThirdHandItem]],
        filter: BoardFilter,
        failures: [SourceFailure],
        lastCapturedAt: Date?,
        now: Date
    ) -> BoardState {
        let all = Horizon.allCases.flatMap { board[$0] ?? [] }
        if all.isEmpty {
            // §9.3: a paused source is the reason the board is empty, so it wins
            // over "nothing needs you" and over the never-captured invitation.
            if let paused = failures.first(where: \.isPermissionProblem) {
                return .empty(.denied(paused.identity))
            }
            return .empty(lastCapturedAt == nil ? .neverCaptured : .allClear)
        }
        if filter.apply(to: all).isEmpty, filter.isActive {
            return .empty(.filtered)
        }
        // §8.1: an error never blocks the board when items are still renderable —
        // but a per-source failure does exist, so the state carries it for the banner.
        if !failures.isEmpty {
            return .degraded(failures)
        }
        return .ready
    }

    /// Writes the widget projection and tells WidgetKit the board moved (#29).
    ///
    /// `WidgetCenter.reloadAllTimelines()` is what makes a Done tap show up on the
    /// Home Screen within a second instead of waiting out the 15-minute timeline
    /// policy. It is coalesced with the write: one reload per persisted board, not one
    /// per mutation, so a burst of Done taps does not queue a burst of reloads.
    private func persist() {
        try? persistence.save(board: board, generatedAt: nowDate)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        #if canImport(ActivityKit) && os(iOS)
        // #31: a capture pass or a mutation can make the next meeting imminent, or
        // end the one that was running.
        Task { @MainActor in await liveActivity?.sync() }
        #endif
    }

    private func persistFilter() {
        shared.set(filter.source?.rawValue, for: .boardFilter)
    }

    private static func restoreFilter(_ shared: SharedStore) -> BoardFilter {
        guard let raw = shared.string(.boardFilter) else { return .all }
        return BoardFilter(source: SourceIdentity(rawValue: raw))
    }
}
