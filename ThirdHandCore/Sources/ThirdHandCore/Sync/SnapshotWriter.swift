import Foundation

/// Serialises the store into the contract's `snapshot.json`.
///
/// The plugin's only read. Three properties matter more than anything else here:
///
/// 1. **Always complete.** The write goes through `CloudContainer.write`, which is
///    tmp + rename. A reader sees the previous envelope or the new one.
/// 2. **Never destructive.** If the file on disk carries a higher
///    `schemaVersion`, this build does not know all the fields and must not write
///    over them. It throws and the app shows "update Pulse".
/// 3. **Deterministic.** Items are emitted sorted by id and keys are sorted by the
///    shared encoder, so two writes with nothing changed are byte-identical --
///    which is what lets the plugin's `generatedAt`-based change detection work
///    without spurious reloads.
public struct SnapshotWriter: Sendable {
    /// The transport file name from "Transport layout" in the data contract.
    public static let fileName = "snapshot.json"
    /// The contract caps nothing explicitly; 12 matches the plugin's own
    /// `lastRuns` window and keeps the envelope small.
    public static let maxRuns = ItemStore.maxRuns

    public let container: any CloudContainer
    public let deviceName: String
    private let clock: @Sendable () -> Date

    public init(
        container: any CloudContainer,
        deviceName: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.container = container
        self.deviceName = deviceName
        self.clock = now
    }

    // MARK: Write

    /// Builds, guards, and writes the envelope. Returns what was written so the
    /// coordinator can report item counts without re-reading the file.
    @discardableResult
    public func write(
        items: [ThirdHandItem],
        runs: [CaptureRun] = [],
        draft: ThirdHandDraft? = nil,
        lastViewedAt: Date? = nil
    ) throws -> ThirdHandSnapshot {
        let instant = clock()

        // Guard first: a build that cannot represent the file must not touch it.
        try assertWritableSchema()

        // A duplicate id means the mirror cannot key its rows. Refuse rather than
        // publish something that will silently collapse two items into one.
        var seen = Set<String>()
        for item in items {
            guard seen.insert(item.id).inserted else {
                throw ThirdHandSyncError.duplicateItemID(item.id)
            }
        }

        let snapshot = ThirdHandSnapshot(
            schemaVersion: ThirdHandSnapshot.currentSchemaVersion,
            generatedAt: instant,
            deviceName: deviceName,
            lastViewedAt: lastViewedAt,
            items: items.sorted { $0.id < $1.id },
            runs: Array(runs.sorted { $0.finishedAt > $1.finishedAt }.prefix(Self.maxRuns)),
            draft: draft
        )
        .pruningClosedItems(olderThan: instant)

        let data = try ThirdHandJSON.encode(snapshot, prettyPrinted: true)
        try container.write(data, to: Self.fileName)
        return snapshot
    }

    /// Reads back what is on disk, for diagnostics and for the app's own state.
    /// Returns `nil` when there is no snapshot yet.
    public func read() throws -> ThirdHandSnapshot? {
        guard let data = try container.read(Self.fileName) else { return nil }
        return try ThirdHandJSON.decode(ThirdHandSnapshot.self, from: data)
    }

    /// The schema version currently on disk, if any.
    public func publishedSchemaVersion() throws -> Int? {
        try read()?.schemaVersion
    }

    /// Throws `ThirdHandSyncError.unsupportedSchemaVersion` when the file on disk was
    /// written by a newer build.
    ///
    /// A file whose envelope does not even decode is treated as seedable: it is
    /// unreadable to this build *and* to the plugin, so replacing it is the only
    /// recovery. A file that decodes with a higher version is different -- it is
    /// valid data this build would truncate, so we leave it alone.
    public func assertWritableSchema() throws {
        guard let data = try container.read(Self.fileName) else { return }
        guard let existing = try? ThirdHandJSON.decode(ThirdHandSnapshot.self, from: data) else { return }
        guard existing.isWritable() else {
            throw ThirdHandSyncError.unsupportedSchemaVersion(
                existing.schemaVersion,
                supported: ThirdHandSnapshot.currentSchemaVersion
            )
        }
    }

    // MARK: Run log

    /// Appends a run to `runs` on the next write, newest first, capped.
    ///
    /// A free function rather than writer state: the writer is a value type and
    /// the caller may write from more than one place (capture, background task),
    /// so the run list belongs to the caller that owns the store.
    public static func appending(_ run: CaptureRun, to runs: [CaptureRun]) -> [CaptureRun] {
        Array(([run] + runs).prefix(maxRuns))
    }
}
