import Foundation

/// Persists on-device placement decisions between launches.
///
/// **Why this is not in the snapshot.** Decisions are a device-local judgement, not
/// shared state: the same item on the Mac panel is placed by the panel's own rules,
/// and shipping a phone's opinion over the wire would have the two overwrite each
/// other on every sync. It is the same reasoning that keeps `agentSkills` and
/// `action` out of iOS's write path. Storage is a single small JSON file, matching
/// how the rest of the app's local state is kept.
///
/// Every operation is best-effort. A cache that cannot be read is an empty cache,
/// never an error: failing to load a placement hint must not stop the board drawing.
public struct PlacementCache: Sendable {
    /// Bumped when `PlacementDecision` changes shape, so an old file is discarded
    /// instead of decoded into something incomparable.
    public static let schemaVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var decisions: [PlacementDecision]
    }

    private let fileURL: URL?

    /// A cache backed by a file. `nil` (unsaved) is allowed for previews.
    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The default location: `placements.json` in the app-group root, beside the
    /// sync log and the share inbox (`ThirdHandPaths.placementsURL`).
    public static func appGroup(paths: ThirdHandPaths = ThirdHandPaths()) -> PlacementCache {
        PlacementCache(fileURL: paths.placementsURL)
    }

    /// An in-memory cache for tests and previews.
    public static func inMemory() -> PlacementCache {
        PlacementCache(fileURL: nil)
    }

    /// Every stored decision, keyed by item id. Unreadable or malformed storage
    /// yields an empty cache.
    public func load() -> [ThirdHandItem.ID: PlacementDecision] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL)
        else { return [:] }
        // The decoder must mirror `save`'s date strategy. With the default strategy a
        // file this type wrote itself fails to decode, and because every failure here
        // degrades to an empty cache the symptom is not an error -- it is decisions
        // that silently never survive a relaunch.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.version == Self.schemaVersion
        else { return [:] }
        return Dictionary(
            envelope.decisions.map { ($0.itemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Best-effort write. A failure is swallowed: the decisions are a hint, and the
    /// board is correct without them.
    public func save(_ decisions: [ThirdHandItem.ID: PlacementDecision]) {
        guard let fileURL else { return }
        let envelope = Envelope(
            version: Self.schemaVersion,
            decisions: Array(decisions.values).sorted { $0.itemID < $1.itemID }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return }

        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
