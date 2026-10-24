import Foundation
import Observation
import ThirdHandCore
#if canImport(UIKit)
import UIKit
#endif

/// The loop that makes the Mac mirror live.
///
/// Capture -> publish `snapshot.json`; poll `commands.jsonl` -> apply -> republish.
/// Owned by `ThirdHandApp` and shared with the board, so there is one writer of the
/// transport files and one place that knows the last publish failed.
///
/// `@MainActor @Observable` rather than an actor: every entry point is a scene
/// phase change, a 15 s tick, or a background task, all of which arrive on the main
/// actor, and the UI reads `lastPublishedAt` / `lastError` directly through the
/// capture capsule. The blocking work (`ItemStore` reads, the atomic write) happens
/// inside `SnapshotWriter`/`CommandReader`, which are value types safe to call here.
@MainActor
@Observable
public final class SyncCoordinator {
    /// What the capsule's sync line renders.
    public enum Phase: Sendable, Hashable {
        case idle
        case syncing
        /// A write failed. Retryable.
        case failed(String)
        /// Writes are succeeding, but to the local fallback: the board is safe
        /// and the Mac sees nothing. Deliberately its own case, because "the
        /// Mac has it" and "the Mac cannot see it" are the two states a user
        /// must never confuse, and `failed` is the wrong word for a device that
        /// is working exactly as designed with no iCloud account.
        case notConnected(String)
    }

    // MARK: State

    public private(set) var phase: Phase = .idle
    /// When `snapshot.json` was last written by this process.
    public private(set) var lastPublishedAt: Date?
    /// The last failure, cleared by the next success. `nil` while healthy.
    public private(set) var lastError: String?
    /// Set when iCloud is unavailable and the app is publishing to the app-group
    /// fallback instead. The Mac will not see those writes.
    ///
    /// Derived from `mirrorUnavailable`, never from `lastError`: a successful
    /// write to the *local fallback* clears `lastError`, and reading the flag off
    /// that made the capsule claim "Mac · 2m ago" while the Mac saw nothing. That
    /// is the failure this property exists to make impossible.
    public var isMirroring: Bool { mirrorUnavailable == nil }
    /// Why the mirror is unreachable, or nil when it is. Sticky for the lifetime
    /// of the coordinator: the container is resolved once at launch, so a
    /// successful publish never means the mirror came back.
    public private(set) var mirrorUnavailable: MirrorUnavailable?
    /// The last command drain, for the debug sheet and for the board's reload.
    public private(set) var lastReport: CommandConsumeReport?

    // MARK: Dependencies

    private let store: ItemStore
    private let writer: SnapshotWriter
    private let reader: CommandReader
    private let log: SyncLog
    private let clock: @Sendable () -> Date
    private let deviceName: String

    /// Set by the app to reload the board after a drain changed the store. A
    /// closure rather than a reference to `BoardViewModel`, so the sync layer does
    /// not depend on the UI and there is no retain cycle.
    public var onStoreChanged: (@MainActor () async -> Void)?

    /// Set by the app to the one capture pass it should run. Returning `true` means
    /// the store changed and a republish is warranted. Optional so the coordinator
    /// works before the real EventKit wiring exists.
    public var captureHandler: (@MainActor () async -> Bool)?

    /// Called after a successful publish, so the capsule's "Mac · 2m ago" line
    /// updates without a full board reload.
    public var onPublished: (@MainActor () async -> Void)?

    private var pendingPublish: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// 500 ms, per the plan: a burst of Done/Done/Done writes one snapshot.
    nonisolated public static let publishDebounce: Duration = .milliseconds(500)
    /// The contract's poll cadence while the app is active.
    nonisolated public static let pollInterval: Duration = .seconds(15)
    /// Declared in `project.yml` under `BGTaskSchedulerPermittedIdentifiers`.
    nonisolated public static let backgroundTaskIdentifier = "com.steveafrost.thirdhand.refresh"

    public init(
        store: ItemStore,
        container: any CloudContainer,
        deviceName: String,
        paths: ThirdHandPaths = ThirdHandPaths(),
        log: SyncLog = SyncLog(),
        mirrorUnavailable: MirrorUnavailable? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.writer = SnapshotWriter(container: container, deviceName: deviceName, now: now)
        self.reader = CommandReader(
            container: container,
            store: store,
            // Device-local, deliberately outside the transport directory: the
            // contract pins that directory to exactly three files.
            cursor: FileCommandCursor(url: paths.commandCursorURL),
            now: now
        )
        self.log = log
        self.clock = now
        self.deviceName = deviceName
        self.mirrorUnavailable = mirrorUnavailable
    }

    /// Built from the resolved container, logging the iCloud fallback once.
    public static func live(store: ItemStore, paths: ThirdHandPaths = ThirdHandPaths(), now: @escaping @Sendable () -> Date = { Date() }) -> SyncCoordinator {
        let resolved = SyncContainer.resolve(paths: paths)
        let coordinator = SyncCoordinator(
            store: store,
            container: resolved.container,
            deviceName: DeviceName.current,
            paths: paths,
            log: SyncLog(paths: paths, now: now),
            mirrorUnavailable: resolved.unavailable,
            now: now
        )
        if let reason = resolved.unavailable {
            coordinator.log.append("iCloud unavailable (\(reason.message)); publishing to the local fallback the Mac cannot see")
            coordinator.phase = .notConnected(reason.shortReason)
        } else {
            coordinator.log.append("sync started at \(resolved.container.rootURL.lastPathComponent)")
        }
        return coordinator
    }

    /// The transport directory, for the debug sheet and the simulator check.
    public var rootURL: URL { writer.container.rootURL }

    // MARK: Publish

    /// Publishes after any mutation, coalescing a burst into one write.
    public func publishSoon() {
        pendingPublish?.cancel()
        pendingPublish = Task { [weak self] in
            do {
                try await Task.sleep(for: SyncCoordinator.publishDebounce)
            } catch {
                return
            }
            await self?.publish()
        }
    }

    /// Writes `snapshot.json` now.
    public func publish() async {
        pendingPublish?.cancel()
        pendingPublish = nil
        phase = .syncing
        do {
            let runs = await store.recentRuns()
            let snapshot = try writer.write(
                items: await store.allItems(),
                runs: runs,
                lastViewedAt: await store.lastViewed()
            )
            lastPublishedAt = snapshot.generatedAt
            lastError = nil
            // A successful write does not mean the Mac got it. When iCloud was
            // unavailable at launch we are writing to the local fallback, and
            // resetting the phase to `.idle` here is what made the capsule say
            // "Mac · 2m ago" over a file the Mac can never read.
            phase = mirrorUnavailable.map { .notConnected($0.shortReason) } ?? .idle
            await onPublished?()
            log.append("published \(snapshot.items.count) items\(mirrorUnavailable == nil ? "" : " (local fallback; Mac cannot see this)")")
        } catch {
            let message = (error as? ThirdHandSyncError)?.description ?? "\(error)"
            lastError = message
            phase = .failed(message)
            // The schema guard is the one failure worth shouting about, because it
            // means a newer build owns this container and we must not overwrite it.
            log.append("publish failed: \(message)")
        }
    }

    // MARK: Commands

    /// Drains `commands.jsonl`. Returns whether the store changed, so the caller
    /// can decide to reload the board.
    @discardableResult
    public func pollCommands() async -> Bool {
        // Nothing to drain without a container we can read; the local fallback
        // holds no commands and polling it would only log noise every 15 s.
        if mirrorUnavailable != nil { return false }
        do {
            let report = try await reader.consume()
            lastReport = report
            guard !report.isEmpty else { return false }
            log.append("drained \(report.applied.count) applied, \(report.dropped.count) dropped, \(report.corruptedLines) corrupt")
            for summary in report.dropSummaries { log.append(summary) }
            if report.needsCompaction {
                log.append("commands.jsonl is past 5 MB; the mirror should compact it")
            }
            if report.didChangeStore {
                await publish()
                await onStoreChanged?()
            }
            return report.didChangeStore
        } catch {
            let message = (error as? ThirdHandSyncError)?.description ?? "\(error)"
            lastError = message
            phase = .failed(message)
            log.append("drain failed: \(message)")
            return false
        }
    }

    // MARK: Refresh

    /// One button press / scene-phase entry: drain, capture, publish.
    ///
    /// `capture` is optional so the coordinator still works before the real
    /// EventKit wiring lands -- it then only mirrors whatever the board already
    /// has, which is the honest behaviour for a device with no sources.
    public func syncNow() async {
        phase = mirrorUnavailable.map { .notConnected($0.shortReason) } ?? .syncing
        // Mirror first, capture second, publish after each.
        //
        // Order matters: a capture pass can block on a first-run permission
        // prompt, and holding the whole sync behind that would also hold the
        // commands the user just tapped on the Mac. Draining and publishing take
        // milliseconds; the pass can take as long as it likes afterwards.
        _ = await pollCommands()
        await publish()
        if let captureHandler, await captureHandler() {
            await publish()
        }
        await BackgroundRefresh.schedule()
    }

    /// Foreground entry point: publish immediately so the Mac sees whatever the
    /// board already applied, then start the contract's 15 s poll.
    public func didBecomeActive() async {
        // Poll starts before the first sync so a slow capture cannot delay it.
        startPolling()
        await BackgroundRefresh.schedule()
        await syncNow()
    }

    /// Leaving the foreground stops the poll; a suspended app has no business
    /// polling, and the OS would cancel the task anyway.
    public func didEnterBackground() async {
        await publish()
        stopPolling()
    }

    // MARK: Active polling

    /// Polls every `pollInterval` until cancelled.
    ///
    /// `ContinuousClock.sleep` rather than a `Timer` so the loop survives the main
    /// run loop being busy and so it is cancellable as one unit.
    public func startPolling() {
        guard pollTask == nil else { return }
        log.append("polling every \(Int(Self.pollInterval.components.seconds))s")
        #if DEBUG
        print("[Third Hand] polling started")
        #endif
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: SyncCoordinator.pollInterval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await self.pollCommands()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public var isPolling: Bool { pollTask != nil }

    // MARK: Helpers

    /// Runs inside the `BGAppRefreshTask` handler: drain, capture, publish, then
    /// ask the system for another slot.
    public func performBackgroundRefresh() async -> Bool {
        log.append("background refresh started")
        let changed = await pollCommands()
        _ = await captureHandler?()
        await publish()
        await BackgroundRefresh.schedule()
        log.append("background refresh finished (command change: \(changed), mirroring: \(isMirroring))")
        // A refresh that wrote only to the local fallback did its local job but
        // did not reach the Mac. Reporting success there would let the OS keep a
        // slot reserved for work that cannot succeed until the user signs in.
        return lastError == nil && isMirroring
    }
}

// MARK: - Device name

enum DeviceName {
    /// `UIDevice.current.name` is the user-visible name ("Steve's iPhone") which is
    /// exactly what the contract's `deviceName` shows in the Mac mirror.
    static var current: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }
}
