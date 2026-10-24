import Foundation

/// Path handling shared by every container.
///
/// All transport paths are relative and must stay inside the root. A path is
/// rejected when it is absolute, empty, or contains a `..` component -- the
/// contract only ever names three files, so anything else is a bug or an attack.
enum SyncPaths {
    static func resolve(_ relativePath: String, in root: URL) throws -> URL {
        guard !relativePath.isEmpty else { throw ThirdHandSyncError.pathEscapesRoot(relativePath) }
        guard !relativePath.hasPrefix("/") else { throw ThirdHandSyncError.pathEscapesRoot(relativePath) }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            guard !component.isEmpty else { throw ThirdHandSyncError.pathEscapesRoot(relativePath) }
            guard component != ".." && component != "." else {
                throw ThirdHandSyncError.pathEscapesRoot(relativePath)
            }
        }
        let url = components.reduce(root) { $0.appendingPathComponent(String($1)) }
        // Belt and braces: the standardised path must still be under the root.
        let rootPath = root.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw ThirdHandSyncError.pathEscapesRoot(relativePath)
        }
        return url
    }
}

/// The plain-directory implementation.
///
/// This is the real code path for every test and for `THIRDHAND_HOME`-style runs, so
/// the atomic-write and append semantics the plugin depends on are covered by
/// `swift test` without iCloud. `ICloudContainer` reuses the same file semantics
/// and adds coordination plus eviction handling on top.
///
/// `@unchecked Sendable` for the same reason `WidgetBoardStore` is: `FileManager`
/// is documented safe to use from multiple threads, and every write here is a
/// self-contained tmp + rename with no shared mutable state of our own.
public struct FileCloudContainer: CloudContainer, @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.rootURL = root
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func read(_ relativePath: String) throws -> Data? {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// `<name>.<pid>.<uuid>.tmp` then `rename`, so a reader sees either the old
    /// file or the new one and never a half-written envelope.
    public func write(_ data: Data, to relativePath: String) throws {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fileManager.moveItem(at: tmp, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: tmp)
            throw ThirdHandSyncError.atomicWriteFailed("\(relativePath): \(error.localizedDescription)")
        }
    }

    public func append(_ data: Data, to relativePath: String) throws {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func fileExists(_ relativePath: String) -> Bool {
        guard let url = try? SyncPaths.resolve(relativePath, in: rootURL) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    public func fileSize(_ relativePath: String) throws -> Int? {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.intValue
    }

    public func modificationDate(_ relativePath: String) throws -> Date? {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
}

/// A throwaway directory container for tests and dry runs.
///
/// `LocalContainer.make()` creates a fresh `UUID` directory under the system temp
/// directory; `cleanup()` (also run from `deinit`) removes it. Tests that need to
/// inspect the directory before it is deleted should use
/// `FileCloudContainer(root:)` directly.
public final class LocalContainer: CloudContainer, @unchecked Sendable {
    public let rootURL: URL
    private let base: FileCloudContainer
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.rootURL = root
        self.base = FileCloudContainer(root: root, fileManager: fileManager)
        self.fileManager = fileManager
    }

    /// A fresh temp directory. Never touches iCloud, so it is safe on any machine.
    public static func make(fileManager: FileManager = .default) throws -> LocalContainer {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("pulse-sync-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return LocalContainer(root: url, fileManager: fileManager)
    }

    deinit { cleanup() }

    public func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }

    public func read(_ relativePath: String) throws -> Data? {
        try base.read(relativePath)
    }

    public func write(_ data: Data, to relativePath: String) throws {
        try base.write(data, to: relativePath)
    }

    public func append(_ data: Data, to relativePath: String) throws {
        try base.append(data, to: relativePath)
    }

    public func fileExists(_ relativePath: String) -> Bool {
        base.fileExists(relativePath)
    }

    public func fileSize(_ relativePath: String) throws -> Int? {
        try base.fileSize(relativePath)
    }

    public func modificationDate(_ relativePath: String) throws -> Date? {
        try base.modificationDate(relativePath)
    }
}
