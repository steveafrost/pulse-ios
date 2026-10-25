import Foundation
import ThirdHandCore

/// The real capture seam: wraps `ThirdHandCore`'s `CaptureEngine` (EventKit sources
/// included) behind the app's `CaptureProviding`.
///
/// The engine owns the store write (`ItemStore.upsert`), so this adapter reports
/// `detected: []` upwards. That is not a lie: `BoardViewModel` re-reads the board
/// from the store after every pass, and returning the items here as well would
/// apply them twice -- once by the engine, once by the view model.
///
/// A per-source failure is translated into `SourceFailure` so the board's banner
/// still says "Calendar access is off" rather than "capture failed".
public struct EngineCapture: CaptureProviding {
    private let engine: CaptureEngine
    private let clock: @Sendable () -> Date

    public init(engine: CaptureEngine, now: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.clock = now
    }

    public func capture(now: Date) async -> CaptureOutcome {
        let report = await engine.run(mode: .full)
        return CaptureOutcome(
            detected: [],
            failures: report.errors.map { error in
                SourceFailure(
                    identity: SourceIdentity(item: ThirdHandItem(
                        id: error.source.rawValue + ":",
                        source: error.source,
                        kind: .followup,
                        title: error.source.rawValue,
                        firstSeenAt: report.finishedAt,
                        lastSeenAt: report.finishedAt,
                        updatedAt: report.finishedAt,
                        lastChangedBy: "capture"
                    )),
                    reason: error.isPermissionDenied ? .denied : .failed(error.message)
                )
            },
            ranAt: report.finishedAt,
            // The mail source is reported as `.gmail` because that is the contract's
            // case for mail, so this is the count the mailbox screen wants. It is the
            // number of unread messages the pass turned into items, which is what
            // "N unread" on the mailbox row means.
            emailUnreadCount: report.countsBySource[.gmail] ?? 0
        )
    }

    /// One background-sized pass. Returns whether the store changed.
    public func runIncremental() async -> Bool {
        let report = await engine.run(mode: .incremental)
        return !(report.created.isEmpty
            && report.updated.isEmpty
            && report.resolved.isEmpty
            && report.reopened.isEmpty)
    }

    /// One foreground pass, including resolving items the pass no longer sees.
    public func runFull() async -> Bool {
        let report = await engine.run(mode: .full)
        return !(report.created.isEmpty
            && report.updated.isEmpty
            && report.resolved.isEmpty
            && report.reopened.isEmpty)
    }
}
