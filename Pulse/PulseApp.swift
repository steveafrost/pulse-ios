import PulseCore
import SwiftUI

@main
struct PulseApp: App {
    @State private var permission = PermissionCoordinator()
    @State private var model: BoardViewModel

    init() {
        let shared = SharedStore()
        let domain = DemoSeed.store()
        let store = StoreAdapter(domain)

        // One coordinator for the whole app: it is the only writer of the
        // transport files, so nothing else may construct a SnapshotWriter.
        let sync = SyncCoordinator.live(store: domain, paths: PulsePaths())
        let capture = DemoSeed.capture(store: domain)

        let model = BoardViewModel(
            store: store,
            capture: capture.providing,
            persistence: AppGroupBoardPersistence(),
            shared: shared,
            sync: sync
        )

        // The two directions the sync layer needs back into the UI, kept as
        // closures so `Pulse` is not a dependency of the sync types.
        sync.captureHandler = { await capture.runFull() }
        sync.onStoreChanged = { await model.reloadAfterSync() }
        sync.onPublished = { model.refreshSyncStatus() }

        _model = State(initialValue: model)

        // Registration must happen before launch finishes; BGTaskScheduler traps on
        // a late or duplicate register, so `register()` is idempotent.
        BackgroundRefresh.register()
        BackgroundRefresh.attach(coordinator: sync)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            DemoRoot(model: model, permission: permission)
            #else
            BoardView(
                model: model,
                permission: permission,
                onOpenSettings: AppLinks.openSettings
            )
            .pulseSyncPolling(model.sync)
            .task { await permission.load() }
            #endif
        }
    }
}

#if DEBUG
/// A debug-only root that can present any screen directly, so a visual check of
/// the detail, the snooze sheet, the closed review, the empty states and the
/// loading skeleton does not need a UI test target to drive the tap. Any build
/// without `-PulseDemoScreen` renders the ordinary board.
struct DemoRoot: View {
    let model: BoardViewModel
    let permission: PermissionCoordinator

    private var screen: DemoSeed.Screen { DemoSeed.screen }

    var body: some View {
        switch screen {
        case .board, .empty, .loading:
            BoardView(model: model, permission: permission, onOpenSettings: AppLinks.openSettings)
                .pulseSyncPolling(model.sync)
                .task { await permission.load() }
        case .detail:
            ItemDetailView(model: model.detailModel(for: Fixtures.withThreeQuickActions))
        case .snooze:
            /// `Fixtures.fixtureNow` is a fixed instant, so the demo uses the real
            /// calendar: the labels then read the local clock, as the app does.
            SnoozeMenu(now: Date()) { _ in }
        case .closed:
            ClosedItemsView(model: model.closedModel())
        case .preamble:
            PermissionPreambleView(onAllow: { _ in }, onNotNow: {})
        case .gallery:
            DesignSystemGallery()
        }
    }
}
#endif

extension DemoSeed {
    /// The capture wiring for this build: real EventKit sources on iOS, nothing on
    /// any other platform. Both shapes carry the same two entry points so the
    /// coordinator and the board do not have to care which one they got.
    struct Capture {
        var providing: any CaptureProviding
        var runFull: @MainActor () async -> Bool
        var runIncremental: @MainActor () async -> Bool
    }
}

/// Debug-only board seed, so a simulator run and the screenshot in the handoff
/// show the real interface instead of the first-launch empty state. Compiled out
/// of Release, so it cannot ship.
enum DemoSeed {
    #if DEBUG
    enum Screen: String {
        case board, detail, snooze, closed, preamble, gallery, empty, loading
    }

    /// `-PulseDemoScreen <name>` picks the screen; absent or unknown means the board.
    static var screen: Screen {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-PulseDemoScreen"), index + 1 < args.count else {
            return .board
        }
        return Screen(rawValue: args[index + 1]) ?? .board
    }
    #endif

    static func store() -> ItemStore {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-PulseDemoBoard") { return FixtureStore.make() }
        if args.contains("-PulseDemoEmpty") { return ItemStore() }
        #endif
        return ItemStore()
    }

    /// Real capture on iOS; an empty pass everywhere else (macOS previews, the
    /// gallery). A device with no permission still gets a pass -- it reports the
    /// denial as a source failure, which is the banner the board expects.
    static func capture(store: ItemStore) -> Capture {
        #if os(iOS)
        let engine = CaptureEngine(
            sources: [
                EventKitSource(provider: EventKitEventProvider()),
                RemindersSource(provider: EventKitReminderProvider()),
            ],
            store: store,
            now: { Date() }
        )
        let adapter = EngineCapture(engine: engine)
        return Capture(
            providing: adapter,
            runFull: { await adapter.runFull() },
            runIncremental: { await adapter.runIncremental() }
        )
        #else
        let empty = EmptyCapture()
        return Capture(
            providing: empty,
            runFull: { false },
            runIncremental: { false }
        )
        #endif
    }
}

/// The no-source capture: reports success with nothing found, which is the honest
/// state for a platform without EventKit.
struct EmptyCapture: CaptureProviding {
    func capture(now: Date) async -> CaptureOutcome {
        CaptureOutcome.empty(at: now)
    }
}

enum AppLinks {
    @MainActor static func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
