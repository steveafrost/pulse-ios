import Foundation
import ThirdHandCore
import Testing
@testable import ThirdHand

/// The degraded-mirror path, end to end at the coordinator.
///
/// The bug this suite pins down: with iCloud unavailable the coordinator writes
/// to the app-group fallback, and `publish()` used to clear `lastError` and set
/// `phase = .idle`. The capsule then rendered "Mac · 2m ago" -- a claim that the
/// Mac has the data -- over a file the Mac can never read, and `isMirroring`
/// (derived from `lastError`) read `true`. The device protocol checks this state
/// on hardware, so it had to be correct before that check could mean anything.
@Suite("SyncCoordinator degraded mirror")
@MainActor
struct SyncContainerTests {

    /// 2026-10-23T18:04:11.000Z, the instant from the data contract.
    private let now = Date(timeIntervalSince1970: 1_792_778_651)

    private func makePaths() -> ThirdHandPaths {
        ThirdHandPaths(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-degraded-\(UUID().uuidString)", isDirectory: true))
    }

    private func coordinator(
        paths: ThirdHandPaths,
        unavailable: MirrorUnavailable?
    ) -> SyncCoordinator {
        SyncCoordinator(
            store: ItemStore(),
            container: FileCloudContainer(root: paths.appGroupRoot),
            deviceName: "Test iPhone",
            paths: paths,
            log: SyncLog(paths: paths) { now },
            mirrorUnavailable: unavailable,
            now: { now }
        )
    }

    // MARK: Resolution

    @Test("a synchronous failure to resolve the container yields a reason, not nil")
    func resolveReportsReason() {
        // On this machine (no signed-in ubiquity container in a test process) the
        // real resolve falls back. The assertion is the shape, not the cause: a
        // fallback container must always carry a reason, or the coordinator would
        // treat it as a mirror.
        let resolved = SyncContainer.resolve(paths: makePaths())
        if resolved.unavailable == nil {
            // iCloud genuinely resolved. Nothing to assert about the fallback.
            return
        }
        #expect(!resolved.unavailable!.shortReason.isEmpty)
        #expect(!resolved.unavailable!.message.isEmpty)
    }

    @Test("the no-container reason reads 'Not connected to iCloud', not a failure")
    func noContainerReason() {
        #expect(MirrorUnavailable.noContainer("x").shortReason == "Not connected to iCloud")
    }

    @Test("the no-directory reason is distinct from the signed-out one")
    func noDirectoryReason() {
        #expect(MirrorUnavailable.noDirectory("x").shortReason == "iCloud folder unavailable")
        #expect(MirrorUnavailable.noDirectory("x").shortReason != MirrorUnavailable.noContainer("x").shortReason)
    }

    // MARK: The bug this suite exists for

    @Test("a successful publish to the fallback does not claim the Mac has the data")
    func publishToFallbackStaysNotConnected() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let subject = coordinator(paths: paths, unavailable: .noContainer("signed out"))

        await subject.publish()

        // The write itself succeeded: there is a snapshot on disk.
        #expect(subject.lastPublishedAt != nil)
        // ...but the phase must not be `.idle`, because `.idle` is what renders
        // "Mac · 2m ago".
        #expect(subject.phase == .notConnected("Not connected to iCloud"))
        #expect(subject.lastError == nil, "a working local write is not an error")
        #expect(subject.isMirroring == false, "the Mac cannot see this container")
    }

    @Test("isMirroring is derived from the container, not from lastError")
    func isMirroringSurvivesASuccessfulPublish() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let subject = coordinator(paths: paths, unavailable: .noDirectory("full disk"))

        #expect(subject.isMirroring == false)
        await subject.publish()
        // The dangerous regression: clearing lastError on success must not flip
        // this back to true.
        #expect(subject.isMirroring == false)
    }

    @Test("a healthy container reports the Mac as the destination")
    func healthyContainerIsMirroring() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let subject = coordinator(paths: paths, unavailable: nil)

        await subject.publish()
        #expect(subject.isMirroring)
        #expect(subject.phase == .idle)
    }

    // MARK: No silent hang or drop

    @Test("polling the fallback is a no-op rather than a repeated failure")
    func pollingFallbackDoesNothing() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let subject = coordinator(paths: paths, unavailable: .noContainer("signed out"))

        let changed = await subject.pollCommands()
        #expect(changed == false)
        #expect(subject.lastError == nil, "a missing mirror is not a drain failure")
    }

    @Test("a background refresh that only reached the fallback does not report success")
    func backgroundRefreshReportsHonestly() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let subject = coordinator(paths: paths, unavailable: .noContainer("signed out"))

        let succeeded = await subject.performBackgroundRefresh()
        // The local work happened, but the OS should not keep granting slots for
        // a refresh that cannot reach the Mac until the user signs in.
        #expect(succeeded == false)
        #expect(subject.lastPublishedAt != nil, "the local write still happened")
    }

    @Test("the debug log names the fallback so a tester can find it")
    func logNamesTheFallback() async {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let subject = coordinator(paths: paths, unavailable: .noContainer("signed out"))

        await subject.publish()
        let lines = SyncLog(paths: paths) { now }.readLines()
        #expect(lines.contains { $0.contains("local fallback") }, "log was \(lines)")
    }
}
