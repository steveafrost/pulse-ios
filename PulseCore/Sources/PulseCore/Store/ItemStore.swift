import Foundation

/// The single writer of item state.
///
/// Pure Swift: no EventKit, no filesystem, and no clock of its own -- the caller
/// injects `now` into every mutating call, so the whole sticky-state machine is
/// deterministic in tests and the app stays in control of what "now" means for a
/// capture pass that took a while.
///
/// An `actor` because `Sync` and the UI both touch it and every read-modify-write
/// (`upsert`, `userAction`) must be atomic with respect to the other.
///
/// Behaviour is a faithful port of `upsert` / `userAction` / `effectiveStatus` /
/// `sortItems` in `bb-plugin-pulse/lib/store.mjs`; the places where Swift needs a
/// decision the JS did not have to make are called out in comments.
public actor ItemStore {
    /// Items keyed by id, plus the insertion order so reads are deterministic --
    /// the JS store relies on object key order for that, which Swift dictionaries
    /// do not promise.
    private var storage: [PulseItem.ID: PulseItem] = [:]
    private var order: [PulseItem.ID] = []
    /// Set by `markSeen`, read by the snapshot writer.
    private var lastViewedAt: Date?

    public init() {}

    /// Seeds a store from an already-decoded item list, e.g. the last snapshot.
    /// Later duplicates replace earlier ones; order of first appearance is kept.
    public init(items: [PulseItem], lastViewedAt: Date? = nil) {
        for item in items {
            if storage[item.id] == nil { order.append(item.id) }
            storage[item.id] = item
        }
        self.lastViewedAt = lastViewedAt
    }

    // MARK: - Reads

    /// Every item, in insertion order. Includes closed items.
    public func allItems() -> [PulseItem] {
        order.compactMap { storage[$0] }
    }

    public func item(id: PulseItem.ID) -> PulseItem? {
        storage[id]
    }

    /// The item, or a thrown `unknownItem`.
    public func requireItem(id: PulseItem.ID) throws -> PulseItem {
        guard let item = storage[id] else { throw PulseStoreError.unknownItem(id) }
        return item
    }

    /// The item's status right now, with an expired snooze reading as `open`.
    /// Pure read: does not normalise storage. Capture does that (`upsert`).
    public func effectiveStatus(of id: PulseItem.ID, at instant: Date) -> Status? {
        storage[id]?.effectiveStatus(at: instant)
    }

    /// Board-ordered items. Defaults match `listItems` in the Node store
    /// (`statuses: ["open", "waiting"]`, all sources).
    ///
    /// Filters on *effective* status, so a snoozed item whose time has passed is
    /// listed as `open` without waiting for the next capture pass. The returned
    /// items carry that effective status, not the stored one.
    ///
    /// `at` is required: the store has no clock of its own, and every item in one
    /// call must be judged against the same instant.
    public func list(
        statuses: Set<Status> = [.open, .waiting],
        sources: Set<Source>? = nil,
        at instant: Date
    ) -> [PulseItem] {
        var items = allItems().map { item -> PulseItem in
            var copy = item
            copy.status = item.effectiveStatus(at: instant)
            return copy
        }
        items = items.filter { statuses.contains($0.status) }
        if let sources { items = items.filter { sources.contains($0.source) } }
        return PulseItemSort.sorted(items)
    }

    /// Items grouped into the four board buckets, each bucket sorted. Closed
    /// items are omitted (`HorizonDerivation.horizon` returns `nil` for them).
    public func board(at instant: Date, calendar: Calendar = .current) -> [Horizon: [PulseItem]] {
        var buckets: [Horizon: [PulseItem]] = [:]
        for item in allItems() {
            guard let horizon = HorizonDerivation.horizon(of: item, at: instant, calendar: calendar) else { continue }
            buckets[horizon, default: []].append(item)
        }
        for key in buckets.keys { buckets[key] = PulseItemSort.sorted(buckets[key] ?? []) }
        return buckets
    }

    public func lastViewed() -> Date? { lastViewedAt }

    public func count() -> Int { storage.count }

    // MARK: - markSeen

    /// Records that the user looked at the board. Returns the new value.
    @discardableResult
    public func markSeen(at instant: Date) -> Date {
        lastViewedAt = instant
        return instant
    }

    // MARK: - Capture write path

    /// Applies one capture pass.
    ///
    /// New ids are created; existing ids get their mutable fields reconciled, with
    /// the user's `done`/`dismissed`/active-`snoozed` state left alone unless the
    /// pass says `reopen: true` with a reason.
    ///
    /// Every input is validated before any item is touched, so a single bad
    /// detection cannot leave the store half-written (the Node store validates up
    /// front for the same reason).
    @discardableResult
    public func upsert(detected: [DetectedItem], run: String, now instant: Date) throws -> UpsertResult {
        guard !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PulseStoreError.missingRun
        }
        for input in detected { try Self.validate(input) }

        var result = UpsertResult()

        for input in detected {
            if storage[input.id] == nil {
                let item = try Self.makeItem(from: input, run: run, at: instant)
                storage[item.id] = item
                order.append(item.id)
                result.created.append(item.id)
                continue
            }

            var current = storage[input.id]!
            // Every pass that still sees the item bumps `lastSeenAt`, even when
            // nothing else changed.
            current.lastSeenAt = instant

            let userLocked = current.isUserLocked(at: instant)

            if userLocked && !input.reopen {
                // Sticky: only the descriptive fields move. Status, timestamps and
                // the audit trail are the user's.
                Self.applyDescriptive(input, to: &current)
                storage[current.id] = current
                result.keptUserState.append(.init(id: current.id, status: current.status))
                continue
            }

            var changes: [String] = []
            for field in Self.mutableFields {
                Self.reconcile(field, input: input, item: &current, changes: &changes)
            }

            if input.reopen {
                // "open, unless the pass supplies a non-resolved status."
                if let requested = input.status, requested != .resolved {
                    current.status = requested
                } else {
                    current.status = .open
                }
                current.snoozedUntil = nil
                current.resolvedAt = nil
                changes.append("reopened")
                result.reopened.append(current.id)
            }

            if current.status == .snoozed, current.effectiveStatus(at: instant) == .open {
                current.status = .open
                current.snoozedUntil = nil
                changes.append("snooze-expired")
            }

            if changes.contains("status") {
                if current.status == .resolved {
                    current.resolvedAt = instant
                    // "may set resolution from reason"; a later pass with no reason
                    // keeps the last one.
                    current.resolution = Self.nonEmpty(input.reason) ?? current.resolution
                    result.resolved.append(current.id)
                } else {
                    current.resolvedAt = nil
                }
            }

            if changes.isEmpty {
                storage[current.id] = current
                result.unchanged.append(current.id)
            } else {
                current.updatedAt = instant
                current.lastChangedBy = run
                Self.pushHistory(
                    on: &current,
                    entry: HistoryEntry(at: instant, by: run, change: changes.joined(separator: ","), reason: input.reason)
                )
                storage[current.id] = current
                // A `resolved` or `reopened` item is reported once, in its own
                // bucket, not again as an update.
                if !result.resolved.contains(current.id), !result.reopened.contains(current.id) {
                    result.updated.append(.init(id: current.id, fields: changes))
                }
            }
        }

        return result
    }

    // MARK: - User write path

    /// Applies a user transition: done, dismiss, snooze or reopen.
    ///
    /// `by` is `"user"` for the iOS app and `"mirror"` when the Mac plugin
    /// forwarded the command, which is what lands in `lastChangedBy` and history.
    @discardableResult
    public func userAction(
        id: PulseItem.ID,
        verb: ItemActionVerb,
        until: Date? = nil,
        reason: String? = nil,
        by: String = "user",
        now instant: Date
    ) throws -> PulseItem {
        guard var current = storage[id] else { throw PulseStoreError.unknownItem(id) }

        switch verb {
        case .done: current.status = .done
        case .dismiss: current.status = .dismissed
        case .snooze:
            guard let until else { throw PulseStoreError.snoozeRequiresUntil(id) }
            current.status = .snoozed
            current.snoozedUntil = until
        case .reopen:
            current.status = .open
        }

        if verb != .snooze { current.snoozedUntil = nil }

        if verb == .reopen {
            // Reopening un-closes: there is no resolution moment any more.
            current.resolvedAt = nil
        }
        if current.status.isUserTerminal {
            current.resolvedAt = instant
            current.resolution = Self.nonEmpty(reason) ?? current.resolution ?? nil
        }

        current.updatedAt = instant
        current.lastChangedBy = by
        // History records the resulting status (`done`, `dismissed`, `snoozed`,
        // `open`) rather than the verb name, matching `userAction` in store.mjs --
        // the Mac mirror greps these strings.
        Self.pushHistory(
            on: &current,
            entry: HistoryEntry(
                at: instant,
                by: by,
                change: current.status.rawValue,
                reason: reason,
                until: verb == .snooze ? current.snoozedUntil : nil
            )
        )

        storage[id] = current
        var returned = current
        // The caller sees the effective status, so snoozing into the past reads
        // back as `open` immediately rather than lying about it.
        returned.status = current.effectiveStatus(at: instant)
        return returned
    }

    // MARK: - Snapshot assembly

    /// Builds the envelope the sync layer writes, pruning closed items older than
    /// the contract's three-day window.
    public func makeSnapshot(
        now instant: Date,
        deviceName: String,
        schemaVersion: Int = PulseSnapshot.currentSchemaVersion,
        runs: [CaptureRun] = [],
        draft: PulseDraft? = nil
    ) -> PulseSnapshot {
        let snapshot = PulseSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: instant,
            deviceName: deviceName,
            lastViewedAt: lastViewedAt,
            items: allItems(),
            runs: runs,
            draft: draft
        )
        return snapshot.pruningClosedItems(olderThan: instant)
    }

    // MARK: - Validation

    static func validate(_ input: DetectedItem) throws {
        guard DetectedItem.isValidIdentifier(input.id) else {
            throw PulseStoreError.invalidIdentifier(input.id)
        }
        if let status = input.status, !status.isCapturable {
            throw PulseStoreError.statusRequiresUserAction(input.id, status)
        }
        if input.reopen, nonEmpty(input.reason) == nil {
            throw PulseStoreError.reopenRequiresReason(input.id)
        }
        try input.quickActions?.validateQuickActions()
        // `title` is optional on the wire so an update can leave it alone, but a
        // blank title is never acceptable (the contract says "Non-empty").
        if let title = input.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PulseStoreError.emptyTitle(input.id)
        }
    }

    private static func makeItem(from input: DetectedItem, run: String, at instant: Date) throws -> PulseItem {
        guard let title = input.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PulseStoreError.emptyTitle(input.id)
        }
        let status = input.status ?? .open
        var item = PulseItem(
            id: input.id,
            // An explicit source wins; otherwise the id prefix, falling back to
            // `.other` for an unknown prefix -- `SOURCES.includes(source) ? source
            // : "other"` in store.mjs.
            source: input.source ?? DetectedItem.source(fromIdentifier: input.id),
            kind: input.kind ?? .followup,
            title: title,
            detail: input.detail ?? "",
            url: input.url,
            due: input.due,
            priority: input.priority ?? .normal,
            people: input.people ?? [],
            status: status,
            snoozedUntil: nil,
            resolution: status == .resolved ? nonEmpty(input.reason) : nil,
            firstSeenAt: instant,
            lastSeenAt: instant,
            updatedAt: instant,
            resolvedAt: status == .resolved ? instant : nil,
            lastChangedBy: run,
            history: [],
            quickActions: input.quickActions ?? []
        )
        pushHistory(on: &item, entry: HistoryEntry(at: instant, by: run, change: "created", reason: input.reason))
        return item
    }

    // MARK: - Field application

    /// The fields a capture pass may always write, even onto a sticky item.
    /// `DESCRIPTIVE` in store.mjs.
    static let descriptiveFields = ["title", "detail", "url", "due", "people", "quickActions"]

    /// Fields reconciled on a non-sticky item, in the order store.mjs lists them
    /// (`MUTABLE`), so a history label reads the same as the Node one.
    static let mutableFields = [
        "title", "detail", "url", "due", "priority", "kind", "source", "people", "status", "quickActions",
    ]

    private static func applyDescriptive(_ input: DetectedItem, to item: inout PulseItem) {
        if let title = input.title { item.title = title }
        if let detail = input.detail { item.detail = detail }
        if let url = input.url { item.url = url }
        if let due = input.due { item.due = due }
        if let people = input.people { item.people = people }
        if let quickActions = input.quickActions { item.quickActions = quickActions }
    }

    /// Reconciles one mutable field, appending its name to `changes` when the
    /// incoming value differs from what is stored.
    ///
    /// Typed rather than stringly: the Node store compares
    /// `JSON.stringify(cur[k]) !== JSON.stringify(next)`, which for these field
    /// types is structural equality, so `==` is the faithful equivalent and it
    /// cannot be confused by a delimiter inside a person's name.
    private static func reconcile(_ field: String, input: DetectedItem, item: inout PulseItem, changes: inout [String]) {
        func set<T: Equatable>(_ next: T?, _ current: T, _ apply: (T) -> Void) {
            guard let next, next != current else { return }
            changes.append(field)
            apply(next)
        }

        switch field {
        case "title": set(input.title, item.title) { item.title = $0 }
        case "detail": set(input.detail, item.detail) { item.detail = $0 }
        case "url": set(input.url, item.url) { item.url = $0 }
        case "due": set(input.due, item.due) { item.due = $0 }
        case "priority": set(input.priority, item.priority) { item.priority = $0 }
        case "kind": set(input.kind, item.kind) { item.kind = $0 }
        case "source": set(input.source, item.source) { item.source = $0 }
        case "people": set(input.people, item.people) { item.people = $0 }
        case "status": set(input.status, item.status) { item.status = $0 }
        case "quickActions": set(input.quickActions, item.quickActions) { item.quickActions = $0 }
        default: break
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// Appends a history entry and enforces the 50-entry cap, dropping the oldest.
    static func pushHistory(on item: inout PulseItem, entry: HistoryEntry) {
        item.history.append(entry)
        if item.history.count > PulseItem.maxHistoryEntries {
            item.history.removeFirst(item.history.count - PulseItem.maxHistoryEntries)
        }
    }
}
