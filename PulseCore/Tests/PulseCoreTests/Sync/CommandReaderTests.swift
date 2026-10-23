import Foundation
import Testing
@testable import PulseCore

@Suite("CommandReader")
struct CommandReaderTests {

    /// A store holding one open item whose `updatedAt` is `Fixture.now`, the
    /// boundary the stale rule is measured against.
    private func makeStore(id: String = "calendar:event:1", updatedAt: Date? = nil) async throws -> ItemStore {
        let store = ItemStore()
        try await store.upsert(
            detected: [Fixture.detected(id, title: "Standup", kind: .deadline)],
            run: "morning",
            now: updatedAt ?? Fixture.now
        )
        return store
    }

    private func reader(_ container: any CloudContainer, _ store: ItemStore, now: Date? = nil) -> CommandReader {
        SyncFixture.reader(container, store, now: now)
    }

    // MARK: Happy path

    @Test("a fresh command is applied through the user write path")
    func freshCommandApplied() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let id = UUID().uuidString
        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1")],
            to: container
        )

        let report = try await reader(container, store).consume()
        #expect(report.applied == [id])
        #expect(report.dropped.isEmpty)
        #expect(report.changedItemIDs == ["calendar:event:1"])

        let item = try #require(await store.item(id: "calendar:event:1"))
        #expect(item.status == .done)
        #expect(item.lastChangedBy == "mirror", "the contract records mirror-forwarded transitions as such")
        #expect(try SyncFixture.ackIDs(in: container) == [id])
    }

    @Test("three commands, one already acked, applies two and acks two")
    func alreadyAckedNotReapplied() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let acked = UUID().uuidString
        let second = UUID().uuidString
        let third = UUID().uuidString
        try SyncFixture.appendCommands([
            SyncFixture.commandLine(id: acked, at: Fixture.now.addingTimeInterval(10), itemId: "calendar:event:1"),
            SyncFixture.commandLine(id: second, at: Fixture.now.addingTimeInterval(20), op: "snooze", itemId: "calendar:event:1",
                                    until: PulseJSON.dates.string(from: Fixture.now.addingTimeInterval(3_600))),
            SyncFixture.commandLine(id: third, at: Fixture.now.addingTimeInterval(30), itemId: "calendar:event:1"),
        ], to: container)
        try container.append(Data(#"{"id":"\#(acked)"}"#.utf8) + Data("\n".utf8), to: CommandReader.ackFileName)

        let report = try await reader(container, store).consume()
        #expect(Set(report.applied) == [second, third])
        #expect(report.alreadyAcked == 1)
        #expect(try SyncFixture.ackIDs(in: container).sorted() == [acked, second, third].sorted())
        #expect(try await store.item(id: "calendar:event:1")?.status == .done)
    }

    // MARK: Stale rule

    @Test("a command older than the item's updatedAt is dropped stale and still acked")
    func staleCommandDropped() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()
        let before = try #require(await store.item(id: "calendar:event:1"))

        let id = UUID().uuidString
        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(-60), itemId: "calendar:event:1")],
            to: container
        )

        let report = try await reader(container, store).consume()
        #expect(report.applied.isEmpty)
        #expect(report.dropped.count == 1)
        #expect(report.dropped.first?.reason == .stale)
        #expect(report.dropped.first?.commandID == id)
        #expect(report.didChangeStore == false)
        // Acked anyway: the plugin must stop retrying a command iOS has decided
        // not to honour.
        #expect(try SyncFixture.ackIDs(in: container) == [id])
        #expect(await store.item(id: "calendar:event:1") == before)
    }

    @Test("a command at exactly the item's updatedAt is stale, not applied")
    func equalTimestampIsStale() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(at: Fixture.now, itemId: "calendar:event:1")],
            to: container
        )
        let report = try await reader(container, store).consume()
        #expect(report.dropped.first?.reason == .stale)
        #expect(try await store.item(id: "calendar:event:1")?.status == .open)
    }

    // MARK: Invalid and unknown

    @Test("a snooze with a past until is dropped invalidUntil and the item is unchanged")
    func pastSnoozeDropped() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let id = UUID().uuidString
        try SyncFixture.appendCommands([
            SyncFixture.commandLine(
                id: id,
                at: Fixture.now.addingTimeInterval(60),
                op: "snooze",
                itemId: "calendar:event:1",
                until: PulseJSON.dates.string(from: Fixture.now.addingTimeInterval(-60))
            ),
        ], to: container)

        let report = try await reader(container, store).consume()
        #expect(report.dropped.first?.reason == .invalidUntil)
        #expect(try await store.item(id: "calendar:event:1")?.status == .open)
        #expect(try SyncFixture.ackIDs(in: container) == [id])
    }

    @Test("a snooze with no until is dropped invalidUntil")
    func missingUntilDropped() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(at: Fixture.now.addingTimeInterval(60), op: "snooze", itemId: "calendar:event:1")],
            to: container
        )
        let report = try await reader(container, store).consume()
        #expect(report.dropped.first?.reason == .invalidUntil)
    }

    @Test("an unknown itemId is dropped and acked")
    func unknownItemDropped() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let id = UUID().uuidString
        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:missing")],
            to: container
        )
        let report = try await reader(container, store).consume()
        #expect(report.dropped.first?.reason == .unknownItem)
        #expect(try SyncFixture.ackIDs(in: container) == [id])
    }

    // MARK: Corruption and partial lines

    @Test("a malformed line is counted, skipped, and the rest still applied")
    func malformedLineSkipped() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let good = UUID().uuidString
        try SyncFixture.appendCommands([
            "{not json at all",
            SyncFixture.commandLine(id: good, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1"),
            #"{"id":"x","at":"yesterday","op":"done","itemId":"calendar:event:1"}"#,
        ], to: container)

        let report = try await reader(container, store).consume()
        #expect(report.corruptedLines == 2)
        #expect(report.applied == [good])
        // A corrupt line has no id, so it cannot be acked; the good one is.
        #expect(try SyncFixture.ackIDs(in: container) == [good])
    }

    @Test("an unterminated trailing line is ignored until it is complete")
    func partialTrailingLineIgnored() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let complete = UUID().uuidString
        let pending = UUID().uuidString
        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(id: complete, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1")],
            to: container
        )
        // A writer mid-append: bytes, no newline.
        let half = SyncFixture.commandLine(id: pending, at: Fixture.now.addingTimeInterval(120), itemId: "calendar:event:1")
        try container.append(Data(half.prefix(20).utf8), to: CommandReader.commandsFileName)

        let report = try await reader(container, store).consume()
        #expect(report.corruptedLines == 0, "a partial line is not corruption")
        #expect(report.applied == [complete])
        #expect(report.applied.contains(pending) == false)
    }

    @Test("a malformed line is reported once, not on every poll")
    func corruptLineCountedOnce() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        try SyncFixture.appendCommands(["{not json at all"], to: container)

        let subject = reader(container, store)
        #expect(try await subject.consume().corruptedLines == 1)

        // Nothing new, and nothing to ack -- but the same line must not be
        // rediscovered, or a 15 s poll turns one bad byte into a full log.
        let second = try await subject.consume()
        #expect(second.corruptedLines == 0)
        #expect(second.isEmpty)
    }

    @Test("a partial line completes later and is then applied")
    func partialLineCompletesLater() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let id = UUID().uuidString
        let whole = SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1")
        try container.append(Data(whole.prefix(25).utf8), to: CommandReader.commandsFileName)

        let subject = reader(container, store)
        #expect(try await subject.consume().applied.isEmpty)

        try container.append(Data((String(whole.dropFirst(25)) + "\n").utf8), to: CommandReader.commandsFileName)
        #expect(try await subject.consume().applied == [id])
    }

    @Test("a reset cursor re-reads a corrupt line but still does not reapply an acked command")
    func resetCursorIsSafe() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let id = UUID().uuidString
        try SyncFixture.appendCommands([
            "{broken",
            SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1"),
        ], to: container)

        let subject = reader(container, store)
        #expect(try await subject.consume().applied == [id])
        subject.resetCursor()

        let reread = try await subject.consume()
        #expect(reread.applied.isEmpty, "the ack log, not the cursor, is what prevents a replay")
        #expect(reread.alreadyAcked == 1)
        #expect(try SyncFixture.ackIDs(in: container) == [id])
    }

    @Test("a compacted command log is re-read rather than skipped")
    func compactionResetsCursor() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        // A long line establishes a watermark past the size of what comes next.
        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1")],
            to: container
        )
        let subject = reader(container, store)
        _ = try await subject.consume()

        // The plugin compacts: same path, far fewer bytes, a new command.
        let id = UUID().uuidString
        try container.write(
            Data((SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(120), itemId: "calendar:event:1") + "\n").utf8),
            to: CommandReader.commandsFileName
        )

        let report = try await subject.consume()
        #expect(report.applied == [id], "a compaction must not strand every later command")
    }

    @Test("a same-sized replacement log is not resumed mid-line")
    func equalLengthRewriteDetected() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        // Two lines of identical length, so a naive size check would resume at the
        // old offset and read only the tail of the second line.
        let first = #"{"id":"aaaaaaaa-0000","at":"2026-10-23T18:05:11.000Z","op":"done","itemId":"calendar:event:1"}"#
        try container.write(Data((first + "\n").utf8), to: CommandReader.commandsFileName)
        let subject = reader(container, store)
        _ = try await subject.consume()

        let replacement = #"{"id":"bbbbbbbb-0000","at":"2026-10-23T18:06:11.000Z","op":"done","itemId":"calendar:event:1"}"#
        #expect(Data((first + "\n").utf8).count == Data((replacement + "\n").utf8).count)
        try container.write(Data((replacement + "\n").utf8), to: CommandReader.commandsFileName)

        // Not acked, so the fingerprint is the only thing standing between a
        // rewrite and a silently skipped command.
        let report = try await subject.consume()
        #expect(report.applied == ["bbbbbbbb-0000"])
    }

    // MARK: Idempotency

    @Test("consuming twice applies nothing the second time and appends no duplicate acks")
    func idempotent() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let id = UUID().uuidString
        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1")],
            to: container
        )

        let subject = reader(container, store)
        let first = try await subject.consume()
        #expect(first.applied == [id])

        let second = try await subject.consume()
        #expect(second.applied.isEmpty)
        #expect(second.dropped.isEmpty)
        #expect(second.corruptedLines == 0)
        #expect(try SyncFixture.ackIDs(in: container) == [id], "the ack log must not grow")
    }

    @Test("no command file is an empty report, not an error")
    func absentFiles() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let report = try await reader(container, store).consume()
        #expect(report.isEmpty)
        #expect(try SyncFixture.ackIDs(in: container).isEmpty)
    }

    @Test("an oversized command log reports needsCompaction and still consumes")
    func compactionHint() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        // One valid command plus padding past the threshold.
        let id = UUID().uuidString
        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(id: id, at: Fixture.now.addingTimeInterval(60), itemId: "calendar:event:1")],
            to: container
        )
        let padding = Data(String(repeating: " ", count: CommandReader.compactionThreshold).utf8)
        try container.append(padding, to: CommandReader.commandsFileName)

        let report = try await reader(container, store).consume()
        #expect(report.needsCompaction)
        #expect(report.applied == [id])
    }

    // MARK: Round trip

    @Test("a store survives snapshot -> decode -> store with an equal item set")
    func snapshotRoundTrip() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let store = ItemStore()
        try await store.upsert(
            detected: [
                Fixture.detected("calendar:event:1", title: "Standup", kind: .deadline),
                Fixture.detected("reminders:reminder:2", title: "File expenses", kind: .followup, priority: .high),
            ],
            run: "morning",
            now: Fixture.now
        )
        _ = try await store.userAction(
            id: "calendar:event:1", verb: .snooze, until: Fixture.now.addingTimeInterval(3_600), now: Fixture.now
        )

        let writer = SnapshotWriter(container: container, deviceName: "iPhone") { Fixture.now }
        try writer.write(items: await store.allItems(), lastViewedAt: await store.lastViewed())

        let decoded = try #require(try writer.read())
        let restored = ItemStore(items: decoded.items, lastViewedAt: decoded.lastViewedAt)
        let restoredItems = await restored.allItems()
        let originalItems = await store.allItems()
        #expect(restoredItems == originalItems)
    }
}
