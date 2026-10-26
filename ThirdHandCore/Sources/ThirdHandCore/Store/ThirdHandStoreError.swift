import Foundation

/// Everything the store refuses to do. `lib/store.mjs` throws `ThirdHandError` with a
/// message; these cases carry the same readable text through `description`, so a
/// log line from either side reads the same.
///
/// The store throws rather than silently no-oping: a caller that asked for an
/// impossible transition has a bug, and hiding it would corrupt the board.
public enum ThirdHandStoreError: Error, Sendable, Hashable, CustomStringConvertible {
    /// A new item arrived with an empty or whitespace-only title.
    case emptyTitle(String)
    /// `userAction` / `item(id:)` was called with an id the store has never seen.
    case unknownItem(String)
    /// `id` does not match `"<source>:<stable-id>"`, so the source cannot be derived.
    case invalidIdentifier(String)
    /// A `snooze` verb (or a capture-pass snooze) without `until`.
    case snoozeRequiresUntil(String)
    /// A `reopen` without a non-empty `reason`. Reopening is only for real new activity.
    case reopenRequiresReason(String)
    /// A capture pass asserted a status it is not allowed to set (`done`/`dismissed`/`snoozed`).
    case statusRequiresUserAction(String, Status)
    /// More than `ThirdHandItem.maxQuickActions` quick actions.
    case tooManyQuickActions
    /// A quick action broke the label/text/url rules.
    case invalidQuickAction(String)
    /// A timestamp string that is not a valid ISO 8601 instant.
    case invalidDate(field: String, value: String)
    /// `upsert` was called without a run name, so provenance would be unrecorded.
    case missingRun
    /// Starting an agent action while another one is still running on the item.
    case actionAlreadyRunning(String, threadId: String)
    /// The verb is not one of done/dismiss/snooze/reopen (only reachable from decoded input).
    case unknownVerb(String)
    /// `snapshot.json` was written by a newer schema than this build understands.
    case unsupportedSchemaVersion(Int, supported: Int)

    public var description: String {
        switch self {
        case let .emptyTitle(id):
            "new item \(id) needs a title"
        case let .unknownItem(id):
            "no item \(id)"
        case let .invalidIdentifier(id):
            #"item id must look like "<source>:<stable-id>", got \#(id)"#
        case let .snoozeRequiresUntil(id):
            "snooze for \(id) needs an until time"
        case let .reopenRequiresReason(id):
            "reopen for \(id) requires a reason"
        case let .statusRequiresUserAction(id, status):
            "item \(id) cannot be set to \(status.rawValue) by a capture pass; only a user action can"
        case .tooManyQuickActions:
            "quickActions allows at most \(ThirdHandItem.maxQuickActions) actions"
        case let .invalidQuickAction(why):
            "quickAction \(why)"
        case let .invalidDate(field, value):
            "\(field) is not a valid date: \(value)"
        case .missingRun:
            "run name is required"
        case let .actionAlreadyRunning(id, threadId):
            "item \(id) already has a running action (\(threadId))"
        case let .unknownVerb(verb):
            "unknown action \(verb)"
        case let .unsupportedSchemaVersion(found, supported):
            "snapshot schemaVersion \(found) is newer than this build supports (\(supported)); update Pulse"
        }
    }

    public var errorDescription: String? {
        description
    }
}

extension ThirdHandStoreError: LocalizedError {}
