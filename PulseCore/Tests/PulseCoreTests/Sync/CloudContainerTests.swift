import Foundation
import Testing
@testable import PulseCore

@Suite("CloudContainer")
struct CloudContainerTests {

    private func makeTemp() throws -> FileCloudContainer {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-container-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return FileCloudContainer(root: root)
    }

    @Test("a write is readable and leaves no .tmp residue")
    func writeReadRoundTrip() throws {
        let container = try makeTemp()
        defer { try? FileManager.default.removeItem(at: container.rootURL) }

        try container.write(Data("hello".utf8), to: "snapshot.json")
        #expect(try container.read("snapshot.json") == Data("hello".utf8))

        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: container.rootURL.path)
            .filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test("read of a missing path is nil, not an error")
    func readMissingIsNil() throws {
        let container = try makeTemp()
        defer { try? FileManager.default.removeItem(at: container.rootURL) }
        #expect(try container.read("snapshot.json") == nil)
        #expect(container.fileExists("snapshot.json") == false)
    }

    @Test("append produces exactly the lines written, in order")
    func appendLines() throws {
        let container = try makeTemp()
        defer { try? FileManager.default.removeItem(at: container.rootURL) }

        for index in 1...3 {
            try container.append(Data("line\(index)\n".utf8), to: "commands.jsonl")
        }
        let text = String(decoding: try #require(try container.read("commands.jsonl")), as: UTF8.self)
        #expect(text == "line1\nline2\nline3\n")
    }

    @Test("append creates the file when it does not exist yet")
    func appendCreates() throws {
        let container = try makeTemp()
        defer { try? FileManager.default.removeItem(at: container.rootURL) }
        try container.append(Data("first\n".utf8), to: "commands.ack.jsonl")
        #expect(container.fileExists("commands.ack.jsonl"))
    }

    @Test("paths escaping the root are rejected")
    func pathEscapeRejected() throws {
        let container = try makeTemp()
        defer { try? FileManager.default.removeItem(at: container.rootURL) }

        #expect(throws: PulseSyncError.pathEscapesRoot("../escape")) {
            try container.read("../escape")
        }
        #expect(throws: PulseSyncError.pathEscapesRoot("/abs/path")) {
            try container.write(Data(), to: "/abs/path")
        }
        #expect(throws: PulseSyncError.pathEscapesRoot("a/../../b")) {
            try container.append(Data(), to: "a/../../b")
        }
    }

    @Test("a temp container cleans its directory up")
    func localContainerCleans() throws {
        let container = try LocalContainer.make()
        let root = container.rootURL
        try container.write(Data("x".utf8), to: "snapshot.json")
        #expect(FileManager.default.fileExists(atPath: root.path))
        container.cleanup()
        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }
}
