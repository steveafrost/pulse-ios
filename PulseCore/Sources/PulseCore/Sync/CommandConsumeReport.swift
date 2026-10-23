import Foundation

/// Why a command was consumed but not applied. Every one of these is acked -- the
/// plugin must stop retrying a command iOS has decided not to honour.
public enum CommandDropReason: String, Sendable, Hashable, CaseIterable {
    /// The command's `at` is not newer than the item's `updatedAt`. The contract's
    /// conflict rule: iOS wins on item content, and a late-arriving transition
    /// against newer local state is stale by definition.
    case stale
    /// `itemId` is not in the store. Nothing to transition.
    case unknownItem
    /// A `snooze` with no `until`, or one already in the past. Coercing it would
    /// invent an intent the user never expressed.
    case invalidUntil
    /// The store refused the transition (e.g. the verb cannot produce a legal
    /// state). Recorded with the underlying message.
    case refused

    /// The short label used in `SyncLog` lines and the debug sheet.
    public var label: String { rawValue }
}

/// One consumed-but-dropped command, with enough detail to explain it in a log.
public struct DroppedCommand: Sendable, Hashable, Identifiable {
    public var id: String { commandID }
    public var commandID: String
    public var itemID: String
    public var op: MirrorOp
    public var reason: CommandDropReason
    /// Human-readable detail for the log, e.g. the store's refusal message.
    public var detail: String?

    public init(
        commandID: String,
        itemID: String,
        op: MirrorOp,
        reason: CommandDropReason,
        detail: String? = nil
    ) {
        self.commandID = commandID
        self.itemID = itemID
        self.op = op
        self.reason = reason
        self.detail = detail
    }
}

/// What one `CommandReader.consume()` pass did.
///
/// `applied` and `dropped` are both *consumed*, i.e. both acked. `skipped` ids were
/// already in `commands.ack.jsonl` and are not re-acked. `corruptedLines` counts
/// lines that were not commands at all -- those carry no id, so they cannot be
/// acked and are reported for the log instead.
public struct CommandConsumeReport: Sendable, Hashable {
    /// Ids of commands that were applied to the store, in file order.
    public var applied: [String]
    /// Commands consumed but deliberately not applied.
    public var dropped: [DroppedCommand]
    /// How many lines failed to parse.
    public var corruptedLines: Int
    /// Ids already acked on a previous pass, so the caller can tell "nothing new"
    /// from "everything was stale".
    public var alreadyAcked: Int
    /// Item ids that actually changed, so the caller knows whether to republish.
    public var changedItemIDs: [String]
    /// `commands.jsonl` has grown past the compaction threshold. The *plugin*
    /// compacts it; iOS never truncates an append-only file it does not own.
    public var needsCompaction: Bool

    public init(
        applied: [String] = [],
        dropped: [DroppedCommand] = [],
        corruptedLines: Int = 0,
        alreadyAcked: Int = 0,
        changedItemIDs: [String] = [],
        needsCompaction: Bool = false
    ) {
        self.applied = applied
        self.dropped = dropped
        self.corruptedLines = corruptedLines
        self.alreadyAcked = alreadyAcked
        self.changedItemIDs = changedItemIDs
        self.needsCompaction = needsCompaction
    }

    /// Nothing consumed and nothing applied -- the common case on every 15 s poll.
    public var isEmpty: Bool {
        applied.isEmpty && dropped.isEmpty && corruptedLines == 0
    }

    /// Whether the store changed, i.e. whether the snapshot has to be rewritten.
    public var didChangeStore: Bool { !changedItemIDs.isEmpty }

    /// One line per dropped command, for `SyncLog`.
    public var dropSummaries: [String] {
        dropped.map { drop in
            var line = "dropped \(drop.op.rawValue) \(drop.itemID): \(drop.reason.label)"
            if let detail = drop.detail { line += " (\(detail))" }
            return line
        }
    }
}
