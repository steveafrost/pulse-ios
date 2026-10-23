import Foundation
import PulseCore

/// Why the Mac mirror is not reachable, when it is not.
///
/// An enum rather than a `String?` because the two cases want different words in
/// the UI and different recovery steps in the device protocol, and because a
/// bare string let the coordinator's `isMirroring` be derived from "a string
/// exists" -- which is exactly the kind of thing that silently reports healthy
/// later on.
public enum MirrorUnavailable: Equatable {
    /// `url(forUbiquityContainerIdentifier:)` returned nil: signed out of
    /// iCloud, iCloud Drive off for Pulse, or the entitlement is missing. On a
    /// simulator this is the normal case.
    case noContainer(String)
    /// The container resolved, but `Documents/Pulse/` could not be made. The
    /// account is fine; the filesystem is not (full storage, read-only).
    case noDirectory(String)

    public var message: String {
        switch self {
        case .noContainer(let detail), .noDirectory(let detail): detail
        }
    }

    /// The one-line reason shown in the capture capsule and the sync log. Short
    /// enough for the capsule's second line, explicit enough that a tester knows
    /// which Settings screen to visit.
    public var shortReason: String {
        switch self {
        case .noContainer: "Not connected to iCloud"
        case .noDirectory: "iCloud folder unavailable"
        }
    }
}

/// Resolves where the transport files live.
///
/// Prefers the real iCloud Drive ubiquity container (`iCloud.com.steveafrost.pulse`,
/// `Documents/Pulse/`) because that is what the Mac plugin reads. Falls back to
/// the app group's `Documents/Pulse/` when iCloud is not signed in, which keeps
/// the board working and lets the simulator integration check inspect the files
/// with `xcrun simctl get_app_container`.
///
/// A fallback container is *not* a mirror: the Mac never sees it. The fallback
/// exists so a sync failure is a degraded state rather than a crash, and the
/// caller must surface `unavailable` distinctly -- see `SyncCoordinator.Phase`.
enum SyncContainer {
    /// `(container, unavailable)` where `unavailable` is non-nil when the
    /// container is the local fallback and the Mac will not see its writes.
    static func resolve(paths: PulsePaths = PulsePaths()) -> (container: any CloudContainer, unavailable: MirrorUnavailable?) {
        do {
            return (try ICloudContainer(), nil)
        } catch {
            let reason: MirrorUnavailable
            if case .iCloudDirectoryUnavailable(let why) = error as? PulseSyncError ?? .iCloudUnavailable {
                reason = .noDirectory(why)
            } else {
                reason = .noContainer((error as? PulseSyncError)?.description ?? "\(error)")
            }
            paths.ensureDirectory()
            return (FileCloudContainer(root: paths.appGroupRoot), reason)
        }
    }
}
