import Foundation

/// How much work a pass does.
public enum CaptureMode: String, Sendable, Codable, CaseIterable, Hashable {
    /// App foreground: scan today plus a week ahead and treat absence as
    /// resolution.
    case full
    /// Background refresh: a narrow window around now, and never resolve an item
    /// just because this cheap pass did not look far enough to see it.
    case incremental

    /// The window this mode scans, as of `now`.
    public func window(now: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .full:
            let start = calendar.startOfDay(for: now)
            let end = start.addingTimeInterval(CaptureWindow.secondsPerDay * 8)
            return DateInterval(start: start, end: end)
        case .incremental:
            return CaptureWindow.around(now: now, back: CaptureWindow.secondsPerDay, forward: 2 * CaptureWindow.secondsPerDay)
        }
    }

    /// Whether a pass in this mode may move unseen items to `resolved`.
    public var resolvesMissingItems: Bool { self == .full }

    /// The name recorded as `lastChangedBy` and in history.
    public var runName: String { "capture-\(rawValue)" }
}

/// One source's failure, kept per source so the board can say "Calendar is off"
/// rather than "capture failed".
public struct SourceError: Sendable, Hashable, Codable, CustomStringConvertible {
    public var source: Source
    /// True when the failure is a missing permission -- a paused source, not a
    /// broken one.
    public var isPermissionDenied: Bool
    public var message: String

    public init(source: Source, isPermissionDenied: Bool, message: String) {
        self.source = source
        self.isPermissionDenied = isPermissionDenied
        self.message = message
    }

    /// Builds from a thrown error, classifying `CaptureError.denied`/`unavailable`.
    public init(source: Source, error: any Error) {
        let captureError = error as? CaptureError
        let denied: Bool
        switch captureError {
        case .denied, .unavailable: denied = true
        default: denied = false
        }
        self.init(
            source: captureError?.source ?? source,
            isPermissionDenied: denied,
            message: captureError?.description ?? String(describing: error)
        )
    }

    public var description: String { "\(source.rawValue): \(message)" }
}

/// What one capture pass did, per source and in total.
public struct CaptureReport: Sendable, Hashable, Codable {
    public var startedAt: Date
    public var finishedAt: Date
    /// How many items each source contributed *after* de-duplication.
    public var countsBySource: [Source: Int]
    public var created: [PulseItem.ID]
    public var updated: [PulseItem.ID]
    public var resolved: [PulseItem.ID]
    public var reopened: [PulseItem.ID]
    public var keptUserState: [PulseItem.ID]
    public var errors: [SourceError]

    public init(
        startedAt: Date,
        finishedAt: Date,
        countsBySource: [Source: Int] = [:],
        created: [PulseItem.ID] = [],
        updated: [PulseItem.ID] = [],
        resolved: [PulseItem.ID] = [],
        reopened: [PulseItem.ID] = [],
        keptUserState: [PulseItem.ID] = [],
        errors: [SourceError] = []
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.countsBySource = countsBySource
        self.created = created
        self.updated = updated
        self.resolved = resolved
        self.reopened = reopened
        self.keptUserState = keptUserState
        self.errors = errors
    }

    /// Empty pass: no items, no errors.
    public static func empty(at instant: Date) -> CaptureReport {
        CaptureReport(startedAt: instant, finishedAt: instant)
    }

    /// Total items detected across all sources.
    public var detectedCount: Int { countsBySource.values.reduce(0, +) }

    /// Sources that reported a permission problem -- the UI's "paused" list.
    public var pausedSources: [Source] {
        errors.filter(\.isPermissionDenied).map(\.source).sorted { $0.rawValue < $1.rawValue }
    }

    /// The envelope the snapshot carries so the mirror can show "last captured
    /// 3 min ago, 2 errors".
    public func captureRun() -> CaptureRun {
        let parts = [
            "\(detectedCount) detected",
            "\(created.count) new",
            "\(resolved.count) resolved",
        ]
        return CaptureRun(
            run: "capture",
            startedAt: startedAt,
            finishedAt: finishedAt,
            summary: (parts + (errors.isEmpty ? [] : ["\(errors.count) errors"])).joined(separator: ", "),
            sources: countsBySource.keys.map(\.rawValue).sorted(),
            errors: errors.map(\.description)
        )
    }
}

/// Runs every source for one instant, de-duplicates, and hands the union to the
/// store.
///
/// `now` is a closure rather than a `Date` so the app can pass `Date.init` and a
/// test can pin it; capture logic never calls `Date()` itself. `run(mode:)` takes
/// its instant from that closure, so one pass judges every source against the
/// same moment.
///
/// Sources are ordered and independent: `EventKitSource`, `RemindersSource` and
/// `SharedLinkSource` run against the same `now`. A source that throws contributes
/// a `SourceError` and nothing else; a source that throws `CaptureError.denied`
/// (or `.unavailable`) is reported in `pausedSources`, which is what the board
/// shows as "Calendar access is off" rather than as a broken pass.
///
/// An `actor` because it holds the in-flight-run guard: two overlapping
/// `run` calls would otherwise double-capture and race on the store.
public actor CaptureEngine {
    public let sources: [any CaptureSource]
    private let store: ItemStore
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    /// Set while a pass is in flight. A second `run` waits for the first and
    /// returns its report rather than capturing again.
    private var inFlight: Task<CaptureReport, Never>?

    public init(
        sources: [any CaptureSource],
        store: ItemStore,
        now: @escaping @Sendable () -> Date,
        calendar: Calendar = .current
    ) {
        self.sources = sources
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    /// Runs one pass. Never throws: a failing source is reported, not fatal.
    public func run(mode: CaptureMode) async -> CaptureReport {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task<CaptureReport, Never> { [self] in
            await perform(mode: mode)
        }
        inFlight = task
        let report = await task.value
        inFlight = nil
        return report
    }

    /// Whether a pass is currently running. Exposed for the UI's status capsule.
    public var isRunning: Bool { inFlight != nil }

    private func perform(mode: CaptureMode) async -> CaptureReport {
        let startedAt = now()
        let window = mode.window(now: startedAt, calendar: calendar)

        // One source failing must not abort the pass: collect, do not propagate.
        var detected: [DetectedItem] = []
        var errors: [SourceError] = []
        for source in sources {
            do {
                detected += try await source.detect(now: startedAt, window: window)
            } catch {
                errors.append(SourceError(source: error.captureSource ?? source.sourceID, error: error))
            }
        }

        let deduped = Self.deduplicate(detected)

        var counts: [Source: Int] = [:]
        for item in deduped {
            counts[item.source ?? DetectedItem.source(fromIdentifier: item.id), default: 0] += 1
        }

        var report = CaptureReport(
            startedAt: startedAt,
            finishedAt: startedAt,
            countsBySource: counts,
            errors: errors
        )

        do {
            let result = try await store.upsert(detected: deduped, run: mode.runName, now: startedAt)
            report.created = result.created
            report.updated = result.updated.map(\.id)
            report.reopened = result.reopened
            report.keptUserState = result.keptUserState.map(\.id)

            if mode.resolvesMissingItems {
                // Anything the store holds as live that this pass did not see is
                // no longer real. It becomes `resolved`, never `done`: only a user
                // action is terminal, and a resolved item can come back if it is
                // detected again. User-locked items (done/dismissed/active snooze)
                // are left alone, and an already-resolved one is not re-resolved.
                let seen = Set(deduped.map(\.id))
                let missing = (await store.allItems())
                    .filter { item in
                        let status = item.effectiveStatus(at: startedAt)
                        return !seen.contains(item.id) && !status.isUserTerminal && status != .resolved
                    }
                    .map(\.id)
                if !missing.isEmpty {
                    // No `reopen`: `reopen` restores an item to `open` by design,
                    // which is the opposite of resolving it.
                    let resolution = try await store.upsert(
                        detected: missing.map {
                            DetectedItem(id: $0, status: .resolved, reason: "no longer detected")
                        },
                        run: mode.runName,
                        now: startedAt
                    )
                    report.resolved = resolution.resolved
                }
            }

            await store.normalizeExpiredSnoozes(at: startedAt)
        } catch {
            report.errors.append(SourceError(source: .other, error: error))
        }

        report.finishedAt = now()
        return report
    }

    /// Collapse duplicate ids. The rule is **last wins**, in source order, and it
    /// is deterministic because `sources` is ordered: a later source with a
    /// richer view of the same id replaces an earlier one, and the output keeps
    /// the position of the id's first appearance so a diff stays stable.
    public static func deduplicate(_ items: [DetectedItem]) -> [DetectedItem] {
        var order: [String] = []
        var byID: [String: DetectedItem] = [:]
        for item in items {
            if byID[item.id] == nil { order.append(item.id) }
            byID[item.id] = item
        }
        return order.compactMap { byID[$0] }
    }
}

extension Error {
    /// The source a `CaptureError` names, if any. Used so a denied Calendar
    /// permission is reported against `.calendar` even when the source's own
    /// `sourceID` is `.other`.
    var captureSource: Source? {
        (self as? CaptureError)?.source
    }
}
