import Foundation
import Testing
@testable import PulseCore

@Suite("SnapshotWriter")
struct SnapshotWriterTests {

    private let clock = Fixture.now

    private func writer(
        _ container: any CloudContainer,
        now: Date? = nil
    ) -> SnapshotWriter {
        let instant = now ?? clock
        return SnapshotWriter(container: container, deviceName: "Test iPhone") { instant }
    }

    // MARK: Envelope

    @Test("the envelope carries every contract field")
    func envelopeShape() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let snapshot = try writer(container).write(
            items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)],
            runs: [CaptureRun(run: "foreground", finishedAt: clock, summary: "1 item")],
            lastViewedAt: clock.addingTimeInterval(-60)
        )

        #expect(snapshot.schemaVersion == PulseSnapshot.currentSchemaVersion)
        #expect(snapshot.deviceName == "Test iPhone")
        #expect(snapshot.generatedAt == clock)
        #expect(snapshot.items.count == 1)

        let data = try #require(try container.read(SnapshotWriter.fileName))
        let text = String(decoding: data, as: UTF8.self)
        for key in ["schemaVersion", "generatedAt", "deviceName", "lastViewedAt", "items", "runs", "draft"] {
            #expect(text.contains("\"\(key)\""), "missing key \(key)")
        }
        #expect(text.contains("\"generatedAt\" : \"2026-10-23T18:04:11.000Z\""))
    }

    // MARK: Atomicity

    @Test("a write never leaves a partial snapshot or a tmp file behind")
    func atomicWriteLeavesNoResidue() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-atomic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = FileCloudContainer(root: root)

        let subject = writer(container)
        try subject.write(items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)])
        try subject.write(items: [SyncFixture.item(id: "calendar:event:2", updatedAt: clock)])

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names == [SnapshotWriter.fileName], "unexpected files: \(names)")

        // Whatever is on disk is a complete envelope, not a fragment.
        let data = try #require(try container.read(SnapshotWriter.fileName))
        let decoded = try PulseJSON.decode(PulseSnapshot.self, from: data)
        #expect(decoded.items.map(\.id) == ["calendar:event:2"])
    }

    @Test("the snapshot file is only ever created by the rename, never written in place")
    func writeGoesThroughATmp() throws {
        // Asserted structurally: the container writes `<name>.<pid>.<uuid>.tmp`
        // and renames, so after a write the target's inode differs from any file
        // that existed before. A direct write would keep the inode.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-inode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = FileCloudContainer(root: root)
        let subject = writer(container)

        try subject.write(items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)])
        let first = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent(SnapshotWriter.fileName).path
        )[.systemFileNumber] as? NSNumber

        try subject.write(items: [SyncFixture.item(id: "calendar:event:2", updatedAt: clock)])
        let second = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent(SnapshotWriter.fileName).path
        )[.systemFileNumber] as? NSNumber

        #expect(first != nil)
        #expect(first != second, "the file was rewritten in place instead of replaced")
    }

    // MARK: Schema guard

    @Test("a higher schemaVersion on disk refuses the write and is left byte-identical")
    func higherSchemaRefused() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let foreign = Data(#"{"schemaVersion":2,"generatedAt":"2026-10-23T18:04:11.000Z","deviceName":"Newer","items":[],"runs":[],"draft":null}"#.utf8)
        try container.write(foreign, to: SnapshotWriter.fileName)

        #expect(throws: PulseSyncError.unsupportedSchemaVersion(2, supported: PulseSnapshot.currentSchemaVersion)) {
            try writer(container).write(items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)])
        }
        #expect(try container.read(SnapshotWriter.fileName) == foreign)
    }

    @Test("a duplicate id is refused and the previous snapshot survives")
    func duplicateIDsRefused() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let subject = writer(container)
        try subject.write(items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)])
        let before = try container.read(SnapshotWriter.fileName)

        #expect(throws: PulseSyncError.duplicateItemID("calendar:event:1")) {
            try subject.write(items: [
                SyncFixture.item(id: "calendar:event:1", updatedAt: clock),
                SyncFixture.item(id: "calendar:event:1", updatedAt: clock),
            ])
        }
        #expect(try container.read(SnapshotWriter.fileName) == before)
    }

    // MARK: Determinism

    @Test("two writes with nothing changed are byte-identical")
    func noOpRewriteIsByteIdentical() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let items = [
            SyncFixture.item(id: "calendar:event:b", updatedAt: clock),
            SyncFixture.item(id: "calendar:event:a", updatedAt: clock),
            SyncFixture.item(id: "calendar:event:c", updatedAt: clock),
        ]
        let subject = writer(container)
        try subject.write(items: items)
        let first = try #require(try container.read(SnapshotWriter.fileName))
        try subject.write(items: items.reversed())
        let second = try #require(try container.read(SnapshotWriter.fileName))

        #expect(first == second)
    }

    @Test("items are emitted in id order regardless of input order")
    func itemsSortedByID() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let snapshot = try writer(container).write(items: [
            SyncFixture.item(id: "calendar:event:c", updatedAt: clock),
            SyncFixture.item(id: "calendar:event:a", updatedAt: clock),
            SyncFixture.item(id: "calendar:event:b", updatedAt: clock),
        ])
        #expect(snapshot.items.map(\.id) == ["calendar:event:a", "calendar:event:b", "calendar:event:c"])
    }

    @Test("generatedAt advances between two writes with a stepped clock")
    func generatedAtAdvances() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let later = clock.addingTimeInterval(60)
        try SnapshotWriter(container: container, deviceName: "iPhone") { clock }
            .write(items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)])
        let first = try #require(try writer(container).read())

        try SnapshotWriter(container: container, deviceName: "iPhone") { later }
            .write(items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)])
        let second = try #require(try writer(container).read())

        #expect(second.generatedAt > first.generatedAt)
        #expect(second.generatedAt == later)
    }

    // MARK: Pruning

    @Test("a closed item 2 days old survives, 4 days old is pruned, open items always survive")
    func threeDayPruning() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let twoDays = clock.addingTimeInterval(-2 * 86_400)
        let fourDays = clock.addingTimeInterval(-4 * 86_400)

        let snapshot = try writer(container).write(items: [
            SyncFixture.item(id: "calendar:event:recent", status: .done, updatedAt: twoDays, resolvedAt: twoDays),
            SyncFixture.item(id: "calendar:event:old", status: .done, updatedAt: fourDays, resolvedAt: fourDays),
            SyncFixture.item(id: "calendar:event:ancient-open", status: .open, updatedAt: fourDays),
            SyncFixture.item(id: "calendar:event:ancient-waiting", status: .waiting, updatedAt: fourDays),
        ])

        #expect(snapshot.items.map(\.id) == [
            "calendar:event:ancient-open",
            "calendar:event:ancient-waiting",
            "calendar:event:recent",
        ])
    }

    @Test("pruning falls back to updatedAt when resolvedAt is nil")
    func pruningFallsBackToUpdatedAt() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let snapshot = try writer(container).write(items: [
            SyncFixture.item(
                id: "calendar:event:dismissed-old",
                status: .dismissed,
                updatedAt: clock.addingTimeInterval(-4 * 86_400),
                resolvedAt: nil
            ),
        ])
        #expect(snapshot.items.isEmpty)
    }

    // MARK: Reads

    @Test("read returns nil before the first write and the envelope after")
    func readBack() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let subject = writer(container)
        #expect(try subject.read() == nil)
        try subject.write(items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)])
        #expect(try subject.read()?.items.count == 1)
    }

    @Test("runs are kept newest first and capped at 12")
    func runsCapped() throws {
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }

        let runs = (0..<20).map { index in
            CaptureRun(run: "run\(index)", finishedAt: clock.addingTimeInterval(Double(index)), summary: "")
        }
        let snapshot = try writer(container).write(
            items: [SyncFixture.item(id: "calendar:event:1", updatedAt: clock)],
            runs: runs
        )
        #expect(snapshot.runs.count == SnapshotWriter.maxRuns)
        #expect(snapshot.runs.first?.run == "run19")
    }

    @Test("appending a run drops the oldest past the cap")
    func appendRun() {
        let runs = [CaptureRun(run: "old", finishedAt: clock, summary: "")]
        let appended = SnapshotWriter.appending(
            CaptureRun(run: "new", finishedAt: clock.addingTimeInterval(60), summary: ""),
            to: runs
        )
        #expect(appended.map(\.run) == ["new", "old"])

        let full = (0..<SnapshotWriter.maxRuns).map {
            CaptureRun(run: "r\($0)", finishedAt: clock, summary: "")
        }
        let capped = SnapshotWriter.appending(
            CaptureRun(run: "newest", finishedAt: clock.addingTimeInterval(60), summary: ""),
            to: full
        )
        #expect(capped.count == SnapshotWriter.maxRuns)
        #expect(capped.first?.run == "newest")
        #expect(capped.last?.run == "r10", "the oldest run should have been dropped")
    }
}
