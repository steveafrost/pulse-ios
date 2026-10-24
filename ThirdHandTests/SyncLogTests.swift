import Foundation
import ThirdHandCore
import Testing
@testable import ThirdHand

@Suite("SyncLog")
struct SyncLogTests {

    private func makeLog() -> SyncLog {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-synclog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(SyncLog.fileName)
        return SyncLog(url: url) { Date(timeIntervalSince1970: 1_792_778_651) }
    }

    @Test("the log never grows past 200 lines after 300 events")
    func cappedAtMaxLines() {
        let log = makeLog()
        defer { log.clear() }

        for index in 0..<300 {
            log.append("event \(index)")
        }
        let lines = log.readLines()
        #expect(lines.count == SyncLog.maxLines)
        // The newest survive: the last event is present, the first is gone.
        #expect(lines.last?.hasSuffix("event 299") == true)
        #expect(lines.contains { $0.hasSuffix("event 0") } == false)
    }

    @Test("every line is stamped with the injected clock")
    func stampsEvents() {
        let log = makeLog()
        defer { log.clear() }
        log.append("published 3 items")
        let line = log.readLines().first ?? ""
        #expect(line.hasPrefix("2026-10-23T18:04:11.000Z "))
        #expect(line.hasSuffix("published 3 items"))
    }

    @Test("the device cursor lives outside the transport directory")
    func cursorOutsideTransport() {
        let paths = ThirdHandPaths(root: URL(fileURLWithPath: "/tmp/pulse-test-group"))
        // The contract pins Documents/ThirdHand/ to snapshot.json, commands.jsonl and
        // commands.ack.jsonl. A fourth file there would be an undeclared protocol
        // change the Mac plugin does not know to ignore.
        #expect(
            paths.commandCursorURL.deletingLastPathComponent().standardizedFileURL.path
                == paths.root.standardizedFileURL.path
        )
        #expect(!paths.commandCursorURL.path.hasPrefix(paths.appGroupRoot.path))
        #expect(!paths.syncLogURL.path.hasPrefix(paths.appGroupRoot.path))
        #expect(paths.syncLogURL.lastPathComponent == SyncLog.fileName)
    }

    @Test("recent returns the tail only")
    func recentTail() {
        let log = makeLog()
        defer { log.clear() }
        for index in 0..<50 { log.append("event \(index)") }
        #expect(log.recent(5).count == 5)
        #expect(log.recent(5).last?.hasSuffix("event 49") == true)
    }

    @Test("trimmed keeps the newest lines and is a no-op under the cap")
    func trimming() {
        #expect(SyncLog.trimmed(["a", "b", "c"], cap: 5) == ["a", "b", "c"])
        #expect(SyncLog.trimmed(["a", "b", "c", "d"], cap: 2) == ["c", "d"])
    }
}
