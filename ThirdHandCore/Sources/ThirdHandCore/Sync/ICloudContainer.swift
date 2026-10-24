import Foundation

/// The iCloud Drive ubiquity container the Mac plugin mirrors from.
///
/// Container identifier `iCloud.com.steveafrost.thirdhand`, transport directory
/// `Documents/ThirdHand/` inside it -- exactly what `docs/DATA-CONTRACT.md`
/// "Transport layout" specifies.
///
/// **Not unit-tested.** Resolving a ubiquity container needs a signed-in iCloud
/// account and the entitlement applied through a provisioning profile, neither of
/// which exists on a CI machine. The interesting semantics (atomic write, append,
/// path rejection, schema guard, staleness) live in the container-agnostic types
/// above this one and are covered against `LocalContainer` / `FileCloudContainer`
/// on macOS. What is untested here is only the coordination wrapper.
///
/// Every read and write is wrapped in `NSFileCoordinator`. Two reasons: iCloud may
/// *evict* the file body and keep a placeholder (an uncoordinated `Data(contentsOf:)`
/// then fails or returns nothing), and a coordinated write is how iCloud is told
/// the new body is ready to upload. Un-downloaded files are pulled with
/// `startDownloadingUbiquitousItem`; if that does not settle within
/// `downloadTimeout` the read throws `iCloudDownloadTimedOut` rather than
/// pretending the file is empty -- an empty snapshot would look to the plugin like
/// "iOS has no items" and it would wipe the board.
public struct ICloudContainer: CloudContainer, @unchecked Sendable {
    public static let containerIdentifier = "iCloud.com.steveafrost.thirdhand"
    public static let transportDirectory = "Documents/ThirdHand"

    public let rootURL: URL
    private let fileManager: FileManager
    private let downloadTimeout: TimeInterval

    public init(
        containerURL: URL,
        fileManager: FileManager = .default,
        downloadTimeout: TimeInterval = 10
    ) {
        self.rootURL = containerURL
        self.fileManager = fileManager
        self.downloadTimeout = downloadTimeout
        try? fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }

    /// Resolves the user's ubiquity container.
    ///
    /// Throws `iCloudUnavailable` when `url(forUbiquityContainerIdentifier:)`
    /// returns nil -- the signed-out, iCloud-Drive-off, and missing-entitlement
    /// cases all arrive here, and on a simulator it is nil almost always. Throws
    /// `iCloudDirectoryUnavailable` when the container resolved but
    /// `Documents/ThirdHand/` could not be created inside it.
    ///
    /// The two are deliberately distinct. `nil` means "the account is the
    /// problem"; a failed `createDirectory` means "the account is fine, the
    /// filesystem is not" -- full storage, a read-only container, or a regular
    /// file sitting where the directory belongs. `try?` here would collapse both
    /// into "iCloud is unavailable", which would send a signed-in user with full
    /// storage to the wrong Settings screen.
    public init(
        fileManager: FileManager = .default,
        containerIdentifier: String = ICloudContainer.containerIdentifier,
        downloadTimeout: TimeInterval = 10
    ) throws {
        guard let base = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw ThirdHandSyncError.iCloudUnavailable
        }
        let root = base.appendingPathComponent(Self.transportDirectory, isDirectory: true)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw ThirdHandSyncError.iCloudDirectoryUnavailable(error.localizedDescription)
        }
        self.init(containerURL: root, fileManager: fileManager, downloadTimeout: downloadTimeout)
    }

    // MARK: Reads

    public func read(_ relativePath: String) throws -> Data? {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        try ensureDownloaded(url)

        var coordinatorError: NSError?
        var result: Result<Data?, any Error> = .success(nil)
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinated in
            result = Result { try Data(contentsOf: coordinated) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    public func modificationDate(_ relativePath: String) throws -> Date? {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        var coordinatorError: NSError?
        var date: Date?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinated in
            date = (try? fileManager.attributesOfItem(atPath: coordinated.path))?[.modificationDate] as? Date
        }
        if let coordinatorError { throw coordinatorError }
        return date
    }

    public func fileSize(_ relativePath: String) throws -> Int? {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.intValue
    }

    public func fileExists(_ relativePath: String) -> Bool {
        guard let url = try? SyncPaths.resolve(relativePath, in: rootURL) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: Writes

    public func write(_ data: Data, to relativePath: String) throws {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp")

        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: tmp)
            throw ThirdHandSyncError.atomicWriteFailed("\(relativePath): \(error.localizedDescription)")
        }

        var coordinatorError: NSError?
        var thrown: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinatorError
        ) { coordinated in
            do {
                if fileManager.fileExists(atPath: coordinated.path) {
                    _ = try fileManager.replaceItemAt(coordinated, withItemAt: tmp)
                } else {
                    try fileManager.moveItem(at: tmp, to: coordinated)
                }
            } catch {
                thrown = error
            }
        }
        if let coordinatorError { try? fileManager.removeItem(at: tmp); throw coordinatorError }
        if let thrown {
            try? fileManager.removeItem(at: tmp)
            throw ThirdHandSyncError.atomicWriteFailed("\(relativePath): \(thrown.localizedDescription)")
        }
    }

    public func append(_ data: Data, to relativePath: String) throws {
        let url = try SyncPaths.resolve(relativePath, in: rootURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var coordinatorError: NSError?
        var thrown: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinated in
            do {
                if !fileManager.fileExists(atPath: coordinated.path) {
                    try data.write(to: coordinated, options: .atomic)
                    return
                }
                let handle = try FileHandle(forWritingTo: coordinated)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                thrown = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let thrown { throw thrown }
    }

    // MARK: Eviction

    /// Pulls an evicted file body down before it is read. iCloud reports an
    /// un-downloaded file through `.ubiquitousItemDownloadingStatusKey ==
    /// .notDownloaded`; a file already local is a no-op.
    private func ensureDownloaded(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard values?.ubiquitousItemDownloadingStatus == .notDownloaded else { return }

        try fileManager.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(downloadTimeout)
        while Date() < deadline {
            let current = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if current?.ubiquitousItemDownloadingStatus == .current { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw ThirdHandSyncError.iCloudDownloadTimedOut(url.lastPathComponent)
    }
}
