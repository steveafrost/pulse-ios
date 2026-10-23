import Foundation
import PulseCore

/// Resolves where the transport files live.
///
/// Prefers the real iCloud Drive ubiquity container (`iCloud.com.steveafrost.pulse`,
/// `Documents/Pulse/`) because that is what the Mac plugin reads. Falls back to the
/// app group's `Documents/Pulse/` when iCloud is not signed in, which keeps the
/// board working and lets the simulator integration check inspect the files with
/// `xcrun simctl get_app_container`.
///
/// A fallback container is *not* a mirror: the Mac never sees it. It exists so a
/// sync failure is a degraded state rather than a crash, and `SyncCoordinator`
/// surfaces the difference through `lastError`.
enum SyncContainer {
    /// `(container, reason)` where `reason` is non-nil when iCloud was unavailable.
    static func resolve(paths: PulsePaths = PulsePaths()) -> (container: any CloudContainer, fallbackReason: String?) {
        if let iCloud = try? ICloudContainer() {
            return (iCloud, nil)
        }
        paths.ensureDirectory()
        return (
            FileCloudContainer(root: paths.appGroupRoot),
            PulseSyncError.iCloudUnavailable.description
        )
    }

}
