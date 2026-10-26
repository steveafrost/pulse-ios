import Foundation
import Testing
@testable import ThirdHandCore

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

        for index in 1 ... 3 {
            try container.append(Data("line\(index)\n".utf8), to: "commands.jsonl")
        }
        // A test that reads back what the container wrote, so the assertion is on the
        // bytes rather than on a decoded model.
        // swiftlint:disable:next optional_data_string_conversion
        let text = try String(decoding: #require(try container.read("commands.jsonl")), as: UTF8.self)
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

        #expect(throws: ThirdHandSyncError.pathEscapesRoot("../escape")) {
            try container.read("../escape")
        }
        #expect(throws: ThirdHandSyncError.pathEscapesRoot("/abs/path")) {
            try container.write(Data(), to: "/abs/path")
        }
        #expect(throws: ThirdHandSyncError.pathEscapesRoot("a/../../b")) {
            try container.append(Data(), to: "a/../../b")
        }
    }

    @Test("every non-relative component still rejects once the root is canonicalised")
    func componentValidationSurvivesCanonicalisation() throws {
        let container = try makeTemp()
        defer { try? FileManager.default.removeItem(at: container.rootURL) }

        for path in ["", "/abs/path", "..", ".", "a//b", "a/./b", "a/../b"] {
            #expect(throws: ThirdHandSyncError.pathEscapesRoot(path)) {
                try SyncPaths.resolve(path, in: container.rootURL)
            }
        }
        #expect(try SyncPaths.resolve("snapshot.json", in: container.rootURL).lastPathComponent == "snapshot.json")
    }

    /// The device failure this file guards against: the real iCloud container lives under
    /// `/private`, which `standardizedFileURL` folds away for the root (it exists) but not
    /// for a child that has not been created yet -- so the first write of any file threw
    /// `pathEscapesRoot`. That spelling asymmetry cannot be rebuilt from a test (a symlinked
    /// root standardises symmetrically, and `/private` is not addressable in a sandbox), so
    /// these assert the invariant instead of replaying the symptom: resolution stays inside
    /// the root for the contract's three filenames whether or not they exist yet. They hold
    /// before and after canonicalising the root -- they are here so a future containment
    /// change that reintroduces the asymmetry fails loudly.
    @Test("the contract's three filenames resolve inside an existing root")
    func transportPathsResolveInsideRoot() throws {
        let root = try makeTemp().rootURL
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.resolvingSymlinksInPath().path

        for name in ["snapshot.json", "commands.jsonl", "commands.ack.jsonl"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) == false)
            let url = try SyncPaths.resolve(name, in: root)
            #expect(url.path.hasPrefix(canonicalRoot + "/"))
            #expect(url.path.hasSuffix("/" + name))
        }
    }

    @Test("a first write of a not-yet-existing file lands and reads back")
    func firstWriteOfMissingFile() throws {
        let container = try makeTemp()
        defer { try? FileManager.default.removeItem(at: container.rootURL) }

        for name in ["snapshot.json", "commands.jsonl", "commands.ack.jsonl"] {
            try container.write(Data(name.utf8), to: name)
            #expect(try container.read(name) == Data(name.utf8))
        }
    }

    @Test("a symlinked root keeps a not-yet-created child inside the canonical root")
    func symlinkedRootResolvesInside() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("pulse-symlink-\(UUID().uuidString)", isDirectory: true)
        let real = base.appendingPathComponent("real", isDirectory: true)
        let link = base.appendingPathComponent("link", isDirectory: true)
        try fileManager.createDirectory(at: real, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? fileManager.removeItem(at: base) }

        #expect(fileManager.fileExists(atPath: link.appendingPathComponent("snapshot.json").path) == false)
        let url = try SyncPaths.resolve("snapshot.json", in: link)
        #expect(url.path.hasPrefix(link.resolvingSymlinksInPath().path + "/"))
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
