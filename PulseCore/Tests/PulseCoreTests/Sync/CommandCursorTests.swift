import Foundation
import Testing
@testable import PulseCore

@Suite("CommandCursor")
struct CommandCursorTests {

    @Test("a file cursor round-trips across reader instances")
    func fileCursorPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-cursor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("commands.cursor")

        FileCommandCursor(url: url).save("42:1234")
        #expect(FileCommandCursor(url: url).load() == "42:1234")

        // A fresh file cursor sees the same record, which is what lets a relaunch
        // resume instead of re-reading the whole log.
        let container = try SyncFixture.makeContainer()
        defer { container.cleanup() }
        let store = ItemStore()
        let reader = SyncFixture.reader(container, store, cursor: FileCommandCursor(url: url))
        #expect(reader.readCursor(in: Data()) == 0, "an offset past the file is not trusted")
    }

    @Test("an absent bookmark means offset zero")
    func absentBookmark() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-cursor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(FileCommandCursor(url: directory.appendingPathComponent("missing")).load() == nil)
    }

    @Test("fingerprints are stable across processes")
    func fingerprintIsStable() {
        // FNV-1a, pinned: `Hasher` is seeded per process and would invalidate every
        // stored bookmark on relaunch.
        #expect(CommandReader.fingerprint(Data()) == 0xcbf2_9ce4_8422_2325)
        #expect(CommandReader.fingerprint(Data("a".utf8)) == 0xaf63_dc4c_8601_ec8c)
        #expect(CommandReader.fingerprint(Data("ab".utf8)) == CommandReader.fingerprint(Data("ab".utf8)))
        #expect(CommandReader.fingerprint(Data("ab".utf8)) != CommandReader.fingerprint(Data("ba".utf8)))
    }
}
