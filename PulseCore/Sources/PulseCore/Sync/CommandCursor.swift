import Foundation

/// Where `CommandReader` remembers how far into `commands.jsonl` it got.
///
/// The contract pins the transport directory to exactly three files
/// (`snapshot.json`, `commands.jsonl`, `commands.ack.jsonl`), and the Mac plugin
/// enumerates that directory -- so a fourth file there would be an undeclared
/// addition to a protocol another process owns. The bookmark belongs to this
/// device, not to the shared transport, so it lives wherever the caller keeps
/// device-local state: the app group for the app, memory for a test.
public protocol CommandCursor: Sendable {
    /// The stored `<offset>:<fingerprint>` record, or `nil` when there is none.
    func load() -> String?
    func save(_ record: String)
}

/// Process-lifetime only. The default, so nothing writes a file unless the caller
/// asks for persistence. Losing the bookmark costs one re-read, never a lost
/// command: the ack log and the `at`/`updatedAt` rule are the real safety net.
public final class MemoryCommandCursor: CommandCursor, @unchecked Sendable {
    private let lock = NSLock()
    private var record: String?

    public init(record: String? = nil) {
        self.record = record
    }

    public func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return record
    }

    public func save(_ record: String) {
        lock.lock()
        defer { lock.unlock() }
        self.record = record
    }
}

/// A small file, written atomically. The app points this at its app group so the
/// bookmark survives relaunches without touching the transport directory.
public struct FileCommandCursor: CommandCursor {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func save(_ record: String) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(record.utf8).write(to: url, options: .atomic)
    }
}
