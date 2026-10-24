import Foundation

/// The one way a background-surface feature (an intent, the Live Activity
/// controller) mutates state: it appends a `MirrorCommand`-shaped line to the same
/// `commands.jsonl` the Mac mirror writes, and lets the app's `CommandReader`
/// apply it through `ItemStore.userAction`.
///
/// Why not write `board.json` directly: `board.json` is a *projection*, not state.
/// Overwriting it would agree with the store for as long as nothing else changed,
/// then be silently clobbered by the next capture pass or `publish` -- a lost
/// update the user would report as "the snooze didn't stick". The command log is
/// the app's existing write path for a non-foreground actor, it ack-protects and
/// dedupes (`CommandReader.consume`), and the app drains it on the next activation
/// or background refresh, which the OS guarantees.
///
/// The writer is append-only and uses a single `write(to:options:.atomic)` per
/// command; `FileHandle`-free so a partially written line is impossible.
public struct SnoozeCommandWriter: @unchecked Sendable {
    public let paths: ThirdHandPaths
    private let fileManager: FileManager

    public init(paths: ThirdHandPaths = ThirdHandPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    /// Appends a snooze command for `itemID` at `instant`, returning the command's
    /// id. Best-effort: a failure means the snooze did not reach the app, so the
    /// caller must report that rather than claim success.
    @discardableResult
    public func snooze(itemID: String, until: Date, now instant: Date, by: String = "intent") throws -> String {
        let command = MirrorCommand(
            at: instant,
            op: .snooze,
            itemId: itemID,
            until: until,
            // The contract's `reason` is free text; this is what the history row
            // will show, so it names the surface rather than a generic verb.
            reason: by
        )
        try append(command)
        return command.id
    }

    /// Serialises the command exactly as `MirrorCommand.decode(line:)` expects, so
    /// the app side needs no special case for an intent-authored line.
    public func append(_ command: MirrorCommand) throws {
        paths.ensureDirectory(fileManager: fileManager)
        let object: [String: Any] = [
            "id": command.id,
            "at": ThirdHandJSON.dates.string(from: command.at),
            "op": command.op.rawValue,
            "itemId": command.itemId,
            "until": command.until.map { ThirdHandJSON.dates.string(from: $0) } ?? NSNull(),
            "reason": command.reason ?? NSNull(),
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let line = data + Data("\n".utf8)

        let url = paths.commandsURL
        if !fileManager.fileExists(atPath: url.path) {
            try line.write(to: url, options: .atomic)
            return
        }
        // Append, not read-modify-write: the Mac may be appending at the same time,
        // and a rewrite would drop its bytes.
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
