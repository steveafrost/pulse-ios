import Foundation
import Testing
@testable import PulseCore

/// What a reader sees when a write is interrupted, and what a torn command log
/// costs.
///
/// The atomicity claim ("tmp + rename, so a reader sees the old file or the new
/// one") was only ever tested by observing that a *successful* write leaves no
/// residue and changes the inode. Neither of those proves the interesting case:
/// a process killed between the two steps. Both cases here make the interruption
/// explicit rather than hoping the OS provides one.
@Suite("Interruption")
struct InterruptionTests {

    private let clock = Fixture.now

    /// A store holding the one item the commands target, at the fixture instant.
    private func makeStore() async throws -> ItemStore {
        let store = ItemStore()
        try await store.upsert(
            detected: [Fixture.detected("calendar:event:1", title: "Standup", kind: .deadline)],
            run: "morning",
            now: Fixture.now
        )
        return store
    }

    /// A container that fails at the rename, after the tmp file is on disk.
    ///
    /// This is exactly the shape of a crash or a `kill -9` between
    /// `data.write(to: tmp)` and `moveItem`/`replaceItemAt`: the tmp file exists,
    /// the target file has not been touched. A reader must therefore still see
    /// the previous snapshot, byte for byte.
    private struct InterruptedWrite: CloudContainer {
        let base: any CloudContainer

        var rootURL: URL { base.rootURL }

        func read(_ relativePath: String) throws -> Data? { try base.read(relativePath) }
        func append(_ data: Data, to relativePath: String) throws { try base.append(data, to: relativePath) }
        func fileExists(_ relativePath: String) -> Bool { base.fileExists(relativePath) }
        func fileSize(_ relativePath: String) throws -> Int? { try base.fileSize(relativePath) }
        func modificationDate(_ relativePath: String) throws -> Date? { try base.modificationDate(relativePath) }

        func write(_ data: Data, to relativePath: String) throws {
            // Write the tmp file the real implementation would have written,
            // then stop -- as if the process died before the rename.
            let url = try SyncPaths.resolve(relativePath, in: rootURL)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).interrupted.tmp")
            try data.write(to: tmp, options: .atomic)
            throw PulseSyncError.atomicWriteFailed("\(relativePath): simulated interruption before rename")
        }
    }

    private func writer(
        _ container: any CloudContainer,
        now: Date? = nil
    ) -> SnapshotWriter {
        SnapshotWriter(container: container, deviceName: "Test iPhone") { now ?? clock }
    }

    // MARK: Snapshot interrupted between tmp-write and rename

    @Test("a write interrupted before the rename leaves the previous snapshot byte-identical")
    func interruptedWritePreservesPreviousSnapshot() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        // A good snapshot first.
        try writer(container).write(items: [SyncFixture.item(id: "calendar:event:old", updatedAt: clock)])
        let before = try #require(try container.read(SnapshotWriter.fileName))
        let decodedBefore = try PulseJSON.decode(PulseSnapshot.self, from: before)
        #expect(decodedBefore.items.map(\.id) == ["calendar:event:old"])

        // Now a write that dies after the tmp file lands.
        let interrupted = InterruptedWrite(base: container)
        #expect(throws: PulseSyncError.self) {
            try writer(interrupted).write(items: [SyncFixture.item(id: "calendar:event:new", updatedAt: clock)])
        }

        // The reader sees the old snapshot, whole -- not a fragment, not empty.
        let after = try #require(try container.read(SnapshotWriter.fileName))
        #expect(after == before, "the interrupted write modified the target file")
        let decodedAfter = try PulseJSON.decode(PulseSnapshot.self, from: after)
        #expect(decodedAfter.items.map(\.id) == ["calendar:event:old"])
        #expect(decodedAfter.generatedAt == clock)
    }

    @Test("the interrupted write leaves a .tmp file but no partial target")
    func interruptedWriteLeavesTmpOnly() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        try writer(container).write(items: [])
        let before = try #require(try container.read(SnapshotWriter.fileName))

        #expect(throws: PulseSyncError.self) {
            try writer(InterruptedWrite(base: container)).write(items: [])
        }

        let names = try FileManager.default.contentsOfDirectory(atPath: container.rootURL.path)
        // The interrupted tmp is still there -- which is what the real
        // implementation's cleanup would remove on its own error path, and what a
        // crash cannot. The point is that the *target* is untouched either way.
        #expect(names.contains { $0.hasSuffix(".tmp") }, "expected the interrupted tmp to remain: \(names)")
        #expect(try container.read(SnapshotWriter.fileName) == before)
    }

    @Test("an interrupted first-ever write leaves no snapshot at all, not an empty one")
    func interruptedFirstWriteLeavesNothing() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        // No previous snapshot: the state after a crash on the very first publish.
        #expect(throws: PulseSyncError.self) {
            try writer(InterruptedWrite(base: container)).write(items: [])
        }

        // Critically *not* a zero-length or partially-decoded file: the plugin
        // must keep seeing "no snapshot yet", never "iOS has no items".
        #expect(try container.read(SnapshotWriter.fileName) == nil)
        #expect(try writer(container).read() == nil)
    }

    // MARK: Torn command log

    @Test("a torn final line does not lose the complete commands before it")
    func tornFinalLineKeepsEarlierCommands() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let first = UUID().uuidString
        let second = UUID().uuidString
        try SyncFixture.appendCommands([
            SyncFixture.commandLine(id: first, at: clock.addingTimeInterval(60), itemId: "calendar:event:1"),
            SyncFixture.commandLine(id: second, at: clock.addingTimeInterval(120), itemId: "calendar:event:1"),
        ], to: container)

        // The plugin was killed mid-append on a third line: bytes, no newline.
        let torn = SyncFixture.commandLine(
            id: UUID().uuidString,
            at: clock.addingTimeInterval(180),
            itemId: "calendar:event:1"
        )
        try container.append(Data(torn.prefix(30).utf8), to: CommandReader.commandsFileName)

        let report = try await SyncFixture.reader(container, store).consume()

        // Both complete commands applied; the torn one is not corruption and is
        // not applied.
        #expect(report.applied == [first, second])
        #expect(report.corruptedLines == 0, "a torn tail is a writer mid-append, not corruption")
        #expect(try SyncFixture.ackIDs(in: container) == [first, second])
    }

    @Test("the torn line is applied once its newline arrives on a later poll")
    func tornLineCompletesOnNextPoll() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        let first = UUID().uuidString
        let pending = UUID().uuidString
        try SyncFixture.appendCommands([
            SyncFixture.commandLine(id: first, at: clock.addingTimeInterval(60), itemId: "calendar:event:1"),
        ], to: container)
        let whole = SyncFixture.commandLine(id: pending, at: clock.addingTimeInterval(120), itemId: "calendar:event:1")
        let cut = 30
        try container.append(Data(whole.prefix(cut).utf8), to: CommandReader.commandsFileName)

        let subject = SyncFixture.reader(container, store)
        #expect(try await subject.consume().applied == [first])

        // The plugin finishes the append.
        try container.append(Data((String(whole.dropFirst(cut)) + "\n").utf8), to: CommandReader.commandsFileName)
        #expect(try await subject.consume().applied == [pending])
    }

    @Test("nothing was lost: the torn bytes are still in the file after the drain")
    func tornBytesSurviveTheDrain() async throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = try await makeStore()

        try SyncFixture.appendCommands(
            [SyncFixture.commandLine(at: clock.addingTimeInterval(60), itemId: "calendar:event:1")],
            to: container
        )
        let tornText = #"{"id":"torn-line-still-writ"#
        try container.append(Data(tornText.utf8), to: CommandReader.commandsFileName)

        _ = try await SyncFixture.reader(container, store).consume()

        // The reader must not truncate or rewrite the log -- it is append-only on
        // the plugin side, and a drain that "cleaned up" a torn tail would destroy
        // a command the plugin is still writing.
        let text = String(decoding: try #require(try container.read(CommandReader.commandsFileName)), as: UTF8.self)
        #expect(text.hasSuffix(tornText))
    }
}
