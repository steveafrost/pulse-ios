import Foundation

/// Everything the sync layer refuses to do.
///
/// Deliberately distinct from `ThirdHandStoreError`: a store error is about item
/// semantics, a sync error is about the wire. The app maps them to different UI
/// states -- `unsupportedSchemaVersion` is the contract's "update Pulse" banner,
/// everything else is a retryable sync failure.
public enum ThirdHandSyncError: Error, Sendable, Hashable, CustomStringConvertible {
    /// `snapshot.json` on disk was written by a build newer than this one. Per the
    /// contract we must refuse to write rather than drop fields we do not model.
    case unsupportedSchemaVersion(Int, supported: Int)
    /// A relative path was absolute or climbed out of the container root.
    case pathEscapesRoot(String)
    /// iCloud is not signed in, iCloud Drive is off for this app, or the ubiquity
    /// container could not be resolved. Deliberately separate from
    /// `iCloudDirectoryUnavailable`: "sign in" and "we couldn't make our folder"
    /// are different sentences to a user, and the device protocol checks both.
    case iCloudUnavailable
    /// The ubiquity container resolved, but `Documents/ThirdHand/` could not be
    /// created inside it (storage full, container read-only, a file where the
    /// directory should be). Distinct from `iCloudUnavailable` because the
    /// recovery differs and because it would otherwise surface as a raw
    /// `NSError` out of `FileManager`.
    case iCloudDirectoryUnavailable(String)
    /// A file could not be downloaded from iCloud within the timeout.
    case iCloudDownloadTimedOut(String)
    /// The tmp-write + rename dance failed; the previous file is untouched.
    case atomicWriteFailed(String)
    /// A line in a JSONL transport file was not valid JSON. Recorded, never fatal.
    case corruptLine(Int, String)
    /// Two items share an id. That is a store bug and must not reach the plugin.
    case duplicateItemID(String)
    /// A command carried a timestamp that is not an ISO 8601 instant.
    case invalidTimestamp(String)

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "snapshot schemaVersion \(found) is newer than this build supports (\(supported)); update Pulse"
        case let .pathEscapesRoot(path):
            "sync path escapes the container root: \(path)"
        case .iCloudUnavailable:
            "iCloud is unavailable; sign in to iCloud to mirror Pulse to the Mac"
        case let .iCloudDirectoryUnavailable(why):
            "couldn't create the Pulse folder in iCloud Drive: \(why)"
        case let .iCloudDownloadTimedOut(path):
            "timed out downloading \(path) from iCloud"
        case let .atomicWriteFailed(why):
            "couldn't write the snapshot atomically: \(why)"
        case let .corruptLine(index, text):
            "line \(index) is not a valid transport record: \(text)"
        case let .duplicateItemID(id):
            "two items share the id \(id); refusing to publish a snapshot the mirror cannot key"
        case let .invalidTimestamp(value):
            "\(value) is not an ISO 8601 instant"
        }
    }

    public var errorDescription: String? {
        description
    }

    /// Whether the user has to update the app to recover, as opposed to retrying.
    public var requiresUpdate: Bool {
        if case .unsupportedSchemaVersion = self {
            return true
        }
        return false
    }
}

extension ThirdHandSyncError: LocalizedError {}
