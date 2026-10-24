import BackgroundTasks
import Foundation
import ThirdHandCore

/// The `BGAppRefreshTask` half of the loop.
///
/// Identifier `com.steveafrost.thirdhand.refresh`, declared in `project.yml` under
/// `BGTaskSchedulerPermittedIdentifiers` and backed by the `fetch` background mode.
/// The OS decides the real cadence; `earliestBeginDate` is a request, not a promise.
///
/// Registration must happen before the app finishes launching, so it is called from
/// `ThirdHandApp.init`, and the handler is a static closure that looks the coordinator
/// up through a registry rather than capturing it (SwiftUI constructs the app
/// struct, and therefore the coordinator, after `init` returns).
enum BackgroundRefresh {
    /// 30 minutes, per the plan. iOS treats this as "not before".
    static let earliestInterval: TimeInterval = 30 * 60

    /// Set once by `ThirdHandApp` so the static handler can reach the live coordinator.
    @MainActor private static var coordinator: SyncCoordinator?

    /// Registers the handler. Safe to call once; calling twice would trap in
    /// `BGTaskScheduler`, so the guard makes it idempotent for previews and tests.
    @MainActor
    static func register() {
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: SyncCoordinator.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
        #if DEBUG
        if isRegistered {
            print("[Third Hand] registered \(SyncCoordinator.backgroundTaskIdentifier)")
        }
        #endif
    }

    @MainActor private static var isRegistered = false

    /// Wires the live coordinator so the handler can do real work. Its
    /// `captureHandler` carries the capture pass; nothing else is needed here.
    @MainActor
    static func attach(coordinator: SyncCoordinator) {
        self.coordinator = coordinator
    }

    /// Asks for the next slot. Called on foreground and at the end of every run.
    static func schedule() async {
        let request = BGAppRefreshTaskRequest(identifier: SyncCoordinator.backgroundTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not fatal: no background slot just means freshness comes from the
            // foreground pass and the 15 s poll while active.
            #if DEBUG
            print("[Third Hand] couldn't schedule background refresh: \(error)")
            #endif
        }
    }

    /// The handler body.
    ///
    /// Expiration is handled by cancelling one task that owns the whole run, so a
    /// cancelled refresh cannot keep writing to the container after the system has
    /// taken the slot back, and `setTaskCompleted` is called exactly once.
    @MainActor
    private static func handle(_ task: BGAppRefreshTask) {
        // Reschedule first: if the work itself is slow, the next slot is already
        // queued and a failure here cannot starve the loop.
        let work = Task { @MainActor in
            await schedule()
            guard let coordinator else {
                task.setTaskCompleted(success: false)
                return
            }
            let success = await coordinator.performBackgroundRefresh()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}
