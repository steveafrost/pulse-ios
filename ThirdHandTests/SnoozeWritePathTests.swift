import Foundation
import Testing
@testable import ThirdHand
import ThirdHandCore

/// The app-group write path the intents use (#32).
///
/// The point of these is that a snooze from the Lock Screen reaches the app through
/// the log `CommandReader` already consumes, and that the *projection* is left alone --
/// so a background refresh cannot silently undo the snooze.
@Suite("Snooze write path")
struct SnoozeWritePathTests {
    /// 2026-10-27 00:00 UTC. Pinned so the due-hint and snooze-date assertions
    /// do not depend on the machine clock.
    private let base = Date(timeIntervalSince1970: 1_793_059_200)

    private func temporaryPaths() throws -> ThirdHandPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulse-intent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ThirdHandPaths(root: root)
    }

    @Test("A snooze appends one command line the reader can decode")
    func writesDecodableCommand() throws {
        let paths = try temporaryPaths()
        let writer = SnoozeCommandWriter(paths: paths)
        let until = base.addingTimeInterval(86400)

        let id = try writer.snooze(itemID: "calendar:event:a", until: until, now: base)

        let contents = try String(contentsOf: paths.commandsURL, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 1)

        let decoded = try MirrorCommand.decode(line: String(lines[0]))
        #expect(decoded.id == id)
        #expect(decoded.op == .snooze)
        #expect(decoded.itemId == "calendar:event:a")
        #expect(decoded.at == base)
        #expect(decoded.until == until)
    }

    @Test("Two snoozes append rather than replace")
    func appendsWithoutDropping() throws {
        let paths = try temporaryPaths()
        let writer = SnoozeCommandWriter(paths: paths)
        try writer.snooze(itemID: "a", until: base, now: base)
        try writer.snooze(itemID: "b", until: base, now: base)

        let lines = try String(contentsOf: paths.commandsURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        let decoded = try lines.map { try MirrorCommand.decode(line: String($0)) }
        #expect(decoded.map(\.itemId) == ["a", "b"])
    }

    @Test("The board projection is never touched by a snooze")
    func leavesProjectionAlone() throws {
        let paths = try temporaryPaths()
        let board = WidgetBoard(
            generatedAt: base,
            nowCount: 1,
            items: [WidgetItem(
                sampleID: "calendar:event:a",
                title: "Design review",
                kind: Kind.review.rawValue,
                priority: Priority.high.rawValue,
                due: base.addingTimeInterval(2400),
                horizon: Horizon.now.rawValue
            )]
        )
        paths.ensureDirectory()
        let data = try ThirdHandJSON.makeEncoder().encode(board)
        try data.write(to: paths.boardURL)

        let before = try Data(contentsOf: paths.boardURL)
        try SnoozeCommandWriter(paths: paths).snooze(
            itemID: "calendar:event:a",
            until: base.addingTimeInterval(86400),
            now: base
        )
        let after = try Data(contentsOf: paths.boardURL)

        // Byte-identical: the snooze is a command, not a cache edit, so nothing the
        // widget renders has changed yet -- which is exactly the lost-update the
        // alternative write path would have introduced.
        #expect(before == after)
    }

    @Test("The board reader treats an absent file as the empty state")
    func readerMissingBoard() throws {
        let reader = try WidgetBoardReader(paths: temporaryPaths())
        #expect(reader.readBoard() == nil)
        let snapshot = reader.snapshot()
        #expect(snapshot.nowCount == 0)
        #expect(!snapshot.hasBoard)
        #expect(!reader.hasBoard)
    }

    @Test("The board reader round-trips what the app persists")
    func readerRoundTrip() throws {
        let paths = try temporaryPaths()
        let board = WidgetBoard(
            generatedAt: base,
            nowCount: 1,
            items: [WidgetItem(
                sampleID: "gmail:thread:x",
                title: "RSVP to Priya",
                kind: Kind.rsvp.rawValue,
                priority: Priority.high.rawValue,
                due: base.addingTimeInterval(3600),
                horizon: Horizon.now.rawValue
            )]
        )
        paths.ensureDirectory()
        try ThirdHandJSON.makeEncoder().encode(board).write(to: paths.boardURL)

        let snapshot = WidgetBoardReader(paths: paths).snapshot()
        #expect(snapshot.hasBoard)
        #expect(snapshot.nowCount == 1)
        #expect(snapshot.topItem?.title == "RSVP to Priya")
    }

    @Test("A corrupt projection reads as empty instead of crashing")
    func readerCorruptBoard() throws {
        let paths = try temporaryPaths()
        paths.ensureDirectory()
        try Data("{ not json".utf8).write(to: paths.boardURL)
        let snapshot = WidgetBoardReader(paths: paths).snapshot()
        // The file exists but cannot be decoded, so the reader's `hasBoard` is true
        // while the snapshot is empty: the widget renders "Nothing needs you" rather
        // than claiming a fresh install, and nothing crashes.
        #expect(WidgetBoardReader(paths: paths).hasBoard)
        #expect(snapshot.isEmpty)
        #expect(!snapshot.needsSetup)
    }

    @Test("Snooze durations resolve into the future")
    func snoozeDurations() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))

        #expect(SnoozeDuration.hour.date(from: base, calendar: calendar) == base.addingTimeInterval(3600))

        // 09:00 UTC -> 18:00 the same day is still ahead.
        let evening = SnoozeDuration.evening.date(from: base, calendar: calendar)
        #expect(calendar.component(.hour, from: evening) == 18)
        #expect(evening > base)

        // 20:00 UTC -> 18:00 has passed, so it must roll to tomorrow.
        let lateNight = base.addingTimeInterval(20 * 3600)
        let eveningTomorrow = SnoozeDuration.evening.date(from: lateNight, calendar: calendar)
        #expect(calendar.component(.hour, from: eveningTomorrow) == 18)
        #expect(eveningTomorrow > lateNight)
        #expect(calendar.component(.day, from: eveningTomorrow) == calendar.component(.day, from: lateNight) + 1)

        let morning = SnoozeDuration.tomorrowMorning.date(from: base, calendar: calendar)
        #expect(calendar.component(.hour, from: morning) == 9)
        #expect(calendar.component(.day, from: morning) == 28)
        #expect(calendar.component(.month, from: morning) == 10)
    }
}
