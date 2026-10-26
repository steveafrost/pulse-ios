import Foundation

/// One capture run's outcome. The snapshot carries the recent runs so the mirror
/// can show "last captured 3 min ago, 2 errors" without reading another file.
public struct CaptureRun: Codable, Sendable, Hashable, Identifiable {
    public var id: String {
        run + finishedAt.description
    }

    public var run: String
    public var startedAt: Date?
    public var finishedAt: Date
    public var summary: String
    public var thread: String?
    public var sources: [String]
    public var errors: [String]

    public init(
        run: String,
        startedAt: Date? = nil,
        finishedAt: Date,
        summary: String,
        thread: String? = nil,
        sources: [String] = [],
        errors: [String] = []
    ) {
        self.run = run
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.thread = thread
        self.sources = sources
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case run, startedAt, finishedAt, summary, thread, sources, errors
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decode(String.self, forKey: .run)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try c.decode(Date.self, forKey: .finishedAt)
        summary = try c.decode(String.self, forKey: .summary)
        thread = try c.decodeIfPresent(String.self, forKey: .thread)
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
    }
}

/// A saved draft (weekly status update on the Mac side). Present in the envelope
/// so the shape stays wire-compatible; iOS currently only round-trips it.
public struct ThirdHandDraft: Codable, Sendable, Hashable {
    public var kind: String
    public var date: String
    public var file: String?
    public var body: String
    public var modifiedAt: Date?

    public init(kind: String = "weekly", date: String, file: String? = nil, body: String, modifiedAt: Date? = nil) {
        self.kind = kind
        self.date = date
        self.file = file
        self.body = body
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind, date, file, body, modifiedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "weekly"
        date = try c.decode(String.self, forKey: .date)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }
}

/// The envelope written to `snapshot.json`.
///
/// Note this is the *contract* envelope: `schemaVersion`, `generatedAt`,
/// `deviceName`, `lastViewedAt`, `items`, `runs`, `draft`. The plugin's own
/// `ThirdHandSnapshot` type in `types.ts` is a superset carrying Mac-only fields
/// (`home`, `lastRuns`, `automations`, ...) that iOS neither produces nor reads;
/// those are out of scope here. An unknown extra key in the file is ignored.
public struct ThirdHandSnapshot: Codable, Sendable, Hashable {
    /// The contract version this build writes and understands.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var generatedAt: Date
    public var deviceName: String
    public var lastViewedAt: Date?
    /// Every item, including closed ones from the last three days.
    public var items: [ThirdHandItem]
    public var runs: [CaptureRun]
    public var draft: ThirdHandDraft?

    public init(
        schemaVersion: Int = ThirdHandSnapshot.currentSchemaVersion,
        generatedAt: Date,
        deviceName: String,
        lastViewedAt: Date? = nil,
        items: [ThirdHandItem] = [],
        runs: [CaptureRun] = [],
        draft: ThirdHandDraft? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.deviceName = deviceName
        self.lastViewedAt = lastViewedAt
        self.items = items
        self.runs = runs
        self.draft = draft
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, deviceName, lastViewedAt, items, runs, draft
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A reader seeing a higher version must refuse to write and surface an
        // "update Pulse" state rather than silently dropping fields. Decoding
        // succeeds; `validateVersion()` is the gate the writer calls.
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        lastViewedAt = try c.decodeIfPresent(Date.self, forKey: .lastViewedAt)
        items = try c.decodeIfPresent([ThirdHandItem].self, forKey: .items) ?? []
        runs = try c.decodeIfPresent([CaptureRun].self, forKey: .runs) ?? []
        draft = try c.decodeIfPresent(ThirdHandDraft.self, forKey: .draft)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(deviceName, forKey: .deviceName)
        try c.encode(lastViewedAt, forKey: .lastViewedAt)
        try c.encode(items, forKey: .items)
        try c.encode(runs, forKey: .runs)
        // The contract shows `"draft": null` explicitly, so encode the key even
        // when absent rather than omitting it.
        try c.encode(draft, forKey: .draft)
    }

    /// Whether this build may write the file back. A newer `schemaVersion` means
    /// we would drop fields we do not model, so the caller must refuse.
    public func isWritable(by build: Int = ThirdHandSnapshot.currentSchemaVersion) -> Bool {
        schemaVersion <= build
    }

    /// Decoded from disk, this throws when the file is newer than the build.
    public func validateVersion() throws {
        guard isWritable() else {
            throw ThirdHandStoreError.unsupportedSchemaVersion(schemaVersion, supported: Self.currentSchemaVersion)
        }
    }

    /// Prunes closed items older than three days, per the contract's write rule:
    /// "items carries every item, including done and dismissed closed within the
    /// last 3 days. Older closed items are pruned on write."
    public static func closedItemRetention() -> TimeInterval {
        3 * 86400
    }

    public func pruningClosedItems(
        olderThan instant: Date,
        retention: TimeInterval = closedItemRetention()
    ) -> ThirdHandSnapshot {
        let cutoff = instant.addingTimeInterval(-retention)
        var copy = self
        copy.items = items.filter { item in
            guard item.status.isClosed else { return true }
            let closedAt = item.resolvedAt ?? item.updatedAt
            return closedAt > cutoff
        }
        return copy
    }
}
