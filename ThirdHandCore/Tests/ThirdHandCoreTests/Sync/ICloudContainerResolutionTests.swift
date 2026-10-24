import Foundation
import Testing
@testable import ThirdHandCore

/// The ubiquity-container resolution path.
///
/// `ICloudContainer`'s *file semantics* are covered against `FileCloudContainer`
/// elsewhere; what is tested here is only the `init` that asks the system for a
/// container. That init is the single most likely thing to fail on real hardware
/// -- signed out, iCloud Drive off, no entitlement -- and until this suite it had
/// no test at all, because a signed-in iCloud account is not available on CI.
///
/// The seam is `FileManager`: `url(forUbiquityContainerIdentifier:)` and
/// `createDirectory` are both overridable, so a double can produce the nil
/// container and the un-creatable directory without any iCloud account.
@Suite("ICloudContainer resolution")
struct ICloudContainerResolutionTests {

    /// No ubiquity container: the signed-out / simulator / missing-entitlement
    /// case. Every one of those returns nil from the same call.
    private final class NoUbiquityContainer: FileManager, @unchecked Sendable {
        override func url(forUbiquityContainerIdentifier identifier: String?) -> URL? { nil }
    }

    /// A container that resolves to a path under a regular file, so
    /// `createDirectory` fails with ENOTDIR. This is the "container exists but
    /// the directory can't be created" case -- full storage, a read-only
    /// container, or a file where `Documents/ThirdHand` belongs.
    private final class UncreatableDirectory: FileManager, @unchecked Sendable {
        override func url(forUbiquityContainerIdentifier identifier: String?) -> URL? {
            // `/dev/null` is a character device, not a directory: any child of it
            // fails to create.
            URL(fileURLWithPath: "/dev/null", isDirectory: true)
        }
    }

    /// Resolves to a real temp directory, so the transport-directory creation can
    /// be observed. Not the nil case: this is the closest a machine without iCloud
    /// can get to the real path.
    private final class ResolvedContainer: FileManager, @unchecked Sendable {
        let base: URL
        init(base: URL) { self.base = base }
        override func url(forUbiquityContainerIdentifier identifier: String?) -> URL? { base }
    }

    // MARK: The nil container

    @Test("a nil ubiquity container throws iCloudUnavailable, never crashes")
    func nilContainerThrows() {
        #expect(throws: ThirdHandSyncError.iCloudUnavailable) {
            _ = try ICloudContainer(fileManager: NoUbiquityContainer())
        }
    }

    @Test("the nil-container error is not marked as requiring an app update")
    func nilContainerIsRetryable() {
        // The distinction drives the UI: `requiresUpdate` is the "update Third Hand"
        // banner, and a signed-out user must not see that.
        #expect(ThirdHandSyncError.iCloudUnavailable.requiresUpdate == false)
    }

    @Test("the nil-container description names the recovery")
    func nilContainerDescription() {
        #expect(ThirdHandSyncError.iCloudUnavailable.description.contains("sign in to iCloud"))
    }

    // MARK: The container that will not hold a directory

    @Test("a container whose directory cannot be created throws iCloudDirectoryUnavailable")
    func uncreatableDirectoryThrows() throws {
        // Distinct from `.iCloudUnavailable`: the account is fine, the filesystem
        // is not, and the user-facing recovery is different.
        let error = #expect(throws: ThirdHandSyncError.self) {
            _ = try ICloudContainer(fileManager: UncreatableDirectory())
        }
        guard case .iCloudDirectoryUnavailable = try #require(error) else {
            Issue.record("expected .iCloudDirectoryUnavailable, got \(String(describing: error))")
            return
        }
    }

    @Test("the directory error carries a non-empty reason and is not an update prompt")
    func uncreatableDirectoryDescription() {
        let error = ThirdHandSyncError.iCloudDirectoryUnavailable("No space left on device")
        #expect(error.description.contains("No space left on device"))
        #expect(error.description.contains("iCloud Drive"))
        #expect(error.requiresUpdate == false)
    }

    // MARK: The happy path, as far as it can be faked

    @Test("a resolvable container creates Documents/ThirdHand beneath it")
    func resolvableContainerCreatesTransportDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-ubiquity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let container = try ICloudContainer(fileManager: ResolvedContainer(base: base))

        #expect(container.rootURL.path.hasSuffix("Documents/ThirdHand"))
        #expect(FileManager.default.fileExists(atPath: container.rootURL.path))
        // A write through the resolved container lands where the contract says.
        try container.write(Data("{}".utf8), to: "snapshot.json")
        #expect(container.fileExists("snapshot.json"))
    }
}
