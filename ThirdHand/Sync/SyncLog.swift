import Foundation
import ThirdHandCore

/// A bounded, on-device log of sync events.
///
/// Deliberately not `os.Logger` alone: the debug sheet in the recently-closed
/// screen has to show *why* a command was dropped without a console attached, and
/// the answer is the same three lines every time ("drained 2, dropped 1 stale").
/// Nothing here ever leaves the device -- it is a file in the app group, capped at
/// `maxLines`, oldest dropped.
///
/// Append-only on disk, rewritten only when the cap is exceeded: a rewrite on every
/// line would be more I/O than the 15 s poll deserves.
public struct SyncLog: Sendable {
    public static let maxLines = 200
    public static let fileName = "sync.log"

    public let url: URL
    private let clock: @Sendable () -> Date

    public init(url: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        clock = now
    }

    /// The app-group log.
    ///
    /// Deliberately *not* in `Documents/ThirdHand/`: the data contract pins that
    /// directory to the three files the Mac plugin enumerates, and this log is
    /// device-local.
    public init(paths: ThirdHandPaths = ThirdHandPaths(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(url: paths.syncLogURL, now: now)
    }

    public func append(_ event: String) {
        var lines = readLines()
        lines.append("\(ThirdHandJSON.dates.string(from: clock())) \(event)")
        write(Self.trimmed(lines))
    }

    public func readLines() -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        // Lossy on purpose: this log is written by us and read by the debug sheet. A
        // truncated final line after a crash is the one line most worth seeing, and a
        // failable initializer would discard the whole file because of it.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// The most recent `limit` lines, newest last. The debug sheet shows these.
    public func recent(_ limit: Int = 40) -> [String] {
        Array(readLines().suffix(limit))
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Keeps the newest `maxLines`. Pure so the cap is unit-testable without I/O.
    public static func trimmed(_ lines: [String], cap: Int = SyncLog.maxLines) -> [String] {
        lines.count <= cap ? lines : Array(lines.suffix(cap))
    }

    private func write(_ lines: [String]) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
}
