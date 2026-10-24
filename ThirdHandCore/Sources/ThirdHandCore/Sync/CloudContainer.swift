import Foundation

/// The transport abstraction both sync types talk to.
///
/// Deliberately tiny: three files, a handful of operations, plus one way to
/// notice that something changed. The app uses `ICloudContainer` (the user's own
/// private iCloud); tests and `THIRDHAND_HOME` runs use `LocalContainer` over a plain
/// directory. Everything above this protocol is therefore exercised by
/// `swift test` on macOS with no iCloud and no simulator.
///
/// Paths are **relative** to `rootURL` and use `/` separators
/// (`"snapshot.json"`, `"commands.ack.jsonl"`). Implementations reject anything
/// absolute or containing `..` with `ThirdHandSyncError.pathEscapesRoot`.
public protocol CloudContainer: Sendable {
    /// The directory the three transport files live in.
    var rootURL: URL { get }

    /// The file's bytes, or `nil` when it does not exist.
    ///
    /// An absent transport file is normal state, not an error: the first launch
    /// has no snapshot and no commands, and `nil` lets the caller distinguish
    /// "nothing to do" from "something broke".
    func read(_ relativePath: String) throws -> Data?

    /// Writes atomically: `<path>.tmp` then `rename`. A reader never observes a
    /// partial file, and an interrupted write leaves the previous file intact.
    func write(_ data: Data, to relativePath: String) throws

    /// Appends at the end of the file, creating it if needed. Used for the two
    /// append-only JSONL files.
    func append(_ data: Data, to relativePath: String) throws

    func fileExists(_ relativePath: String) -> Bool

    /// Size in bytes, or `nil` when absent. The command reader uses this to
    /// report that `commands.jsonl` has grown past the compaction threshold.
    func fileSize(_ relativePath: String) throws -> Int?

    func modificationDate(_ relativePath: String) throws -> Date?
}

// MARK: - Change observation

/// A cheap "has this file changed?" summary. Comparing fingerprints is enough for
/// the snapshot: the plugin reloads when `generatedAt` advances, and so do we.
public struct FileFingerprint: Sendable, Hashable {
    public var exists: Bool
    public var size: Int
    public var modifiedAt: Date?

    public init(exists: Bool, size: Int, modifiedAt: Date?) {
        self.exists = exists
        self.size = size
        self.modifiedAt = modifiedAt
    }

    public static let absent = FileFingerprint(exists: false, size: 0, modifiedAt: nil)
}

extension CloudContainer {
    public func fingerprint(_ relativePath: String) throws -> FileFingerprint {
        guard fileExists(relativePath) else { return .absent }
        return FileFingerprint(
            exists: true,
            size: try fileSize(relativePath) ?? 0,
            modifiedAt: try modificationDate(relativePath)
        )
    }

    /// Emits once whenever `relativePath`'s fingerprint changes, until the
    /// consuming task is cancelled.
    ///
    /// A fingerprint poll rather than `NSMetadataQuery` / FSEvents: the contract's
    /// own cadence is a 5 s poll on the Mac side, the file is a few hundred KB at
    /// most, and one implementation means `LocalContainer` (tests, `THIRDHAND_HOME`)
    /// and `ICloudContainer` behave identically. Callers that need the contract's
    /// 15 s command poll should use `CommandReader` directly instead of this.
    public func changeStream(
        _ relativePath: String,
        every interval: Duration = .seconds(2)
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                var last = try? fingerprint(relativePath)
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: interval)
                    } catch {
                        break
                    }
                    let current = try? fingerprint(relativePath)
                    guard current != last else { continue }
                    last = current
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
