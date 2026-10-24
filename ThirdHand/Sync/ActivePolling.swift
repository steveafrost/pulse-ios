import Foundation
import SwiftUI

/// Drives the active-scene poll from `scenePhase`.
///
/// A view modifier rather than logic inside `SyncCoordinator` so the coordinator
/// stays testable without SwiftUI: this is the only place that knows a scene exists.
///
/// `.active` starts the 15 s poll and does one immediate sync. `.inactive` keeps
/// polling and does not capture: the app is still foregrounded (a system sheet, the
/// app switcher, an incoming call) and the user can come straight back, but a pass
/// there would be wasted work the OS may charge for. `.background` publishes and
/// stops the poll.
///
/// `.inactive` starting the poll rather than `.active` alone matters because
/// `scenePhase` is not guaranteed to reach `.active` -- the simulator without a
/// focused window reports `.inactive` and nothing else, and a device can be
/// interrupted during launch. Mirroring must not depend on that.
struct ActivePolling: ViewModifier {
    /// `nil` when the view is a preview or a debug screen with no container: the
    /// modifier then does nothing at all rather than inventing a coordinator that
    /// would write files nobody asked for.
    let coordinator: SyncCoordinator?

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase) {
                guard let coordinator else { return }
                switch scenePhase {
                case .active:
                    await coordinator.didBecomeActive()
                case .inactive:
                    // Still foregrounded: drain what the Mac wrote, publish what is
                    // here, and keep the poll alive.
                    await coordinator.pollCommands()
                    await coordinator.publish()
                    coordinator.startPolling()
                case .background:
                    await coordinator.didEnterBackground()
                @unknown default:
                    await coordinator.didEnterBackground()
                }
            }
    }
}

extension View {
    /// Wires the sync loop to this view's scene phase.
    func pulseSyncPolling(_ coordinator: SyncCoordinator?) -> some View {
        modifier(ActivePolling(coordinator: coordinator))
    }
}
