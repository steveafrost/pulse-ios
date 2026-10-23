import Foundation

/// Consumes the mirror's commands and acks them.
///
/// `commands.jsonl` is **append-only on the plugin side**; iOS never rewrites or
/// truncates it. Everything this type does is: read the two JSONL files, apply the
/// unacked commands through the store's *user write path* (`ItemStore.userAction`,
/// with `by: "mirror"`), and append one `{"id":"..."}` line per consumed command to
/// `commands.ack.jsonl`.
///
/// Three tolerances matter on the wire:
///
/// * A malformed line is skipped and counted, never fatal for the rest of the tail.
/// * A trailing line with no newline terminator is a writer mid-append, so it is
///   ignored and retried next poll rather than reported corrupt.
/// * A command that cannot be applied is still acked. Leaving it unacked would make
///   the plugin retry it forever.
public struct CommandReader: Sendable {
    public static let commandsFileName = "commands.jsonl"
    public static let ackFileName = "commands.ack.jsonl"
    /// The contract's compaction hint threshold. iOS reports it; the plugin acts.
    public static let compactionThreshold = 5 * 1024 * 1024


    public let container: any CloudContainer
    public let store: ItemStore
    private let clock: @Sendable () -> Date
    /// How far into `commands.jsonl` this device has already looked.
    ///
    /// Without it, a malformed line has no id, so it can never be acked, and every
    /// 15 s poll would recount it as corruption -- forever, and the log would fill
    /// with the same complaint. The watermark is a byte offset: the log is
    /// append-only, so "everything before offset N has been dealt with" is exactly
    /// the invariant that makes re-reading safe. It is device-local state, not part
    /// of the three-file transport (`CommandCursor`), hence the separate store.
    private let cursorStore: any CommandCursor

    public init(
        container: any CloudContainer,
        store: ItemStore,
        cursor: any CommandCursor = MemoryCommandCursor(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.container = container
        self.store = store
        self.cursorStore = cursor
        self.clock = now
    }

    // MARK: Consume

    /// One drain of the command log.
    ///
    /// Idempotent: calling it twice with no new commands applies nothing and
    /// appends no duplicate acks.
    public func consume() async throws -> CommandConsumeReport {
        var report = CommandConsumeReport()

        guard let commandData = try container.read(Self.commandsFileName) else {
            return report
        }
        report.needsCompaction = (try container.fileSize(Self.commandsFileName) ?? 0) > Self.compactionThreshold

        let acked = try ackedIDs()

        // Only the bytes after the watermark. A malformed line has no id, so it can
        // never be acked; without the watermark it would be recounted as corruption
        // on every poll, forever, and fill the log with the same complaint.
        //
        // The log is append-only *between* compactions, and the plugin is free to
        // rewrite it. A file shorter than the watermark therefore means the offsets
        // no longer describe this file -- it was compacted or replaced -- so start
        // over from 0. Without this guard every command after a compaction would be
        // skipped forever, since the cursor would sit past the end of the file.
        let cursor = readCursor(in: commandData)
        let unread = commandData.count > cursor
            ? commandData.subdata(in: cursor..<commandData.count)
            : Data()
        let lines = Self.completeLines(in: unread)
        // Bytes taken by a trailing line with no newline yet. Counted from the
        // buffer, not reconstructed from the split lines, because `split` yields a
        // trailing empty element for a buffer that does end in a newline and that
        // would make the watermark drift one byte past the file.
        let partialTail = Self.partialTrailingBytes(in: unread)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let command: MirrorCommand
            do {
                command = try MirrorCommand.decode(line: trimmed)
            } catch {
                // No id, so nothing to ack. Count it for the log and keep going.
                report.corruptedLines += 1
                continue
            }

            if acked.contains(command.id) {
                report.alreadyAcked += 1
                continue
            }

            let outcome = await apply(command)
            switch outcome {
            case .applied(let itemID):
                report.applied.append(command.id)
                report.changedItemIDs.append(itemID)
            case .dropped(let drop):
                report.dropped.append(drop)
            }

            // Ack only after the store mutation (or the drop) is decided, one
            // append per consumed command, in file order.
            try container.append(command.ackData + Data("\n".utf8), to: Self.ackFileName)
        }

        // Advance past every complete line, including the corrupt ones: they have
        // been reported once, which is all a line with no id can ever get. A
        // trailing partial line is deliberately not covered, so it is retried once
        // its newline lands.
        let consumedBytes = cursor + (unread.count - partialTail)
        if consumedBytes != cursor {
            writeCursor(consumedBytes, in: commandData)
        }

        return report
    }

    // MARK: Watermark

    /// The offset already processed, or 0 when there is none *or* the file no longer
    /// begins with the bytes that offset was measured against.
    ///
    /// The fingerprint is what makes this correct across a compaction. A size check
    /// alone is not enough: the plugin rewriting the log can easily produce a file
    /// of the same length with different content, and resuming mid-line would then
    /// skip real commands and report nonsense. The stored record is
    /// `<offset>:<hash of everything before it>`, so any change to the prefix -- a
    /// compaction, a truncation, a different file entirely -- fails the check and
    /// starts over.
    public func readCursor(in data: Data) -> Int {
        guard let raw = cursorStore.load(),
              let record = CursorRecord(raw),
              record.offset <= data.count,
              Self.fingerprint(data.prefix(record.offset)) == record.fingerprint
        else { return 0 }
        return record.offset
    }

    /// Persists the offset and the fingerprint of everything before it.
    /// Best-effort: losing it costs a re-read, not correctness, because every
    /// command is still protected by its ack and its `at`/`updatedAt` comparison.
    private func writeCursor(_ offset: Int, in data: Data) {
        cursorStore.save("\(offset):\(Self.fingerprint(data.prefix(offset)))")
    }

    /// Forgets the watermark, so the next `consume` re-reads from the start.
    public func resetCursor() {
        cursorStore.save("0:0")
    }

    /// `<offset>:<fingerprint>` as stored in `commands.cursor`.
    private struct CursorRecord {
        let offset: Int
        let fingerprint: UInt64

        init?(_ text: String) {
            let parts = text.split(separator: ":")
            guard parts.count == 2,
                  let offset = Int(parts[0]), offset >= 0,
                  let fingerprint = UInt64(parts[1])
            else { return nil }
            self.offset = offset
            self.fingerprint = fingerprint
        }
    }

    /// FNV-1a. Small, dependency-free and stable across launches -- unlike
    /// `Hasher`, whose seed is deliberately randomized per process and would make
    /// every stored fingerprint fail on the next launch.
    static func fingerprint<Bytes: Sequence>(_ bytes: Bytes) -> UInt64 where Bytes.Element == UInt8 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    // MARK: Apply

    private enum Outcome {
        case applied(String)
        case dropped(DroppedCommand)
    }

    /// The contract's conflict rule, in one place.
    ///
    /// A plugin command is applied only if its `at` is **strictly newer** than the
    /// item's `updatedAt`; otherwise it is dropped as `.stale`. Strictly newer
    /// matters: `<=` would let a command at the same millisecond re-apply an
    /// already-applied transition after the store bumped `updatedAt`, and it makes
    /// `at == updatedAt` a deterministic tie rather than an ordering accident.
    ///
    /// The other drops are the same shape -- unknown item, snooze without a future
    /// `until`, a store refusal -- and every one of them is still acked.
    private func apply(_ command: MirrorCommand) async -> Outcome {
        guard let item = await store.item(id: command.itemId) else {
            return .dropped(DroppedCommand(
                commandID: command.id,
                itemID: command.itemId,
                op: command.op,
                reason: .unknownItem
            ))
        }

        guard command.at > item.updatedAt else {
            return .dropped(DroppedCommand(
                commandID: command.id,
                itemID: command.itemId,
                op: command.op,
                reason: .stale,
                detail: "command at \(PulseJSON.dates.string(from: command.at)) is not newer than item updatedAt \(PulseJSON.dates.string(from: item.updatedAt))"
            ))
        }

        if command.op == .snooze {
            guard let until = command.until else {
                return .dropped(DroppedCommand(
                    commandID: command.id, itemID: command.itemId, op: command.op,
                    reason: .invalidUntil, detail: "no until"
                ))
            }
            guard until > clock() else {
                return .dropped(DroppedCommand(
                    commandID: command.id, itemID: command.itemId, op: command.op,
                    reason: .invalidUntil,
                    detail: "until \(PulseJSON.dates.string(from: until)) is not in the future"
                ))
            }
        }

        // The instant recorded as `updatedAt`.
        //
        // The command's own `at`, clamped so it can never move `updatedAt` into
        // the future. Using `clock()` here instead would be wrong for a batch: the
        // first apply would set `updatedAt` to "now", and every later command in
        // the same tail -- genuinely newer, per the plugin's append order -- would
        // then look stale and be lost. `command.at` is already guaranteed newer
        // than the item's `updatedAt` by the guard above, so it is both monotonic
        // and honest about when the user acted.
        let applyAt = min(command.at, clock())

        do {
            _ = try await store.userAction(
                id: command.itemId,
                verb: command.op,
                until: command.until,
                reason: command.reason,
                // The contract's field for a transition forwarded from the Mac.
                by: "mirror",
                now: applyAt
            )
            return .applied(command.itemId)
        } catch {
            return .dropped(DroppedCommand(
                commandID: command.id,
                itemID: command.itemId,
                op: command.op,
                reason: .refused,
                detail: "\(error)"
            ))
        }
    }

    // MARK: Files

    /// Every acked id. An absent ack file means nothing has been consumed yet.
    public func ackedIDs() throws -> Set<String> {
        guard let data = try container.read(Self.ackFileName) else { return [] }
        var ids: Set<String> = []
        for line in Self.completeLines(in: data) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let ack = try? Self.decodeAck(trimmed) else { continue }
            ids.insert(ack)
        }
        return ids
    }

    private static func decodeAck(_ line: String) throws -> String {
        struct Ack: Decodable { let id: String }
        return try PulseJSON.decoder.decode(Ack.self, from: Data(line.utf8)).id
    }

    /// Splits a JSONL buffer into lines, dropping a trailing partial line.
    ///
    /// A writer appending to the file can be observed mid-write: the last line has
    /// bytes but no `\n` yet. Applying it would act on a truncated command, so it is
    /// ignored until the terminator lands and the next poll reads it whole.
    /// The bytes after the last newline, i.e. an incomplete line still being
    /// appended. Zero when the buffer ends on a newline.
    static func partialTrailingBytes(in data: Data) -> Int {
        guard !data.isEmpty, data.last != UInt8(ascii: "\n") else { return 0 }
        return data.reversed().prefix { $0 != UInt8(ascii: "\n") }.count
    }

    static func completeLines(in data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        // A buffer that does not end in a newline has a partial last line.
        let endsWithNewline = data.last == UInt8(ascii: "\n")
        var text = String(decoding: data, as: UTF8.self)
        if !endsWithNewline {
            if let lastNewline = text.lastIndex(of: "\n") {
                text = String(text[text.startIndex..<lastNewline])
            } else {
                // A single unterminated line: nothing complete to read yet.
                return []
            }
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
