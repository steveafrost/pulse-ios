import PulseCore
import SwiftUI

@main
struct PulseApp: App {
    @State private var permission = PermissionCoordinator()
    @State private var model: BoardViewModel

    init() {
        let shared = SharedStore()
        let store = StoreAdapter(DemoSeed.store())
        _model = State(initialValue: BoardViewModel(
            store: store,
            capture: PreviewCapture(),
            persistence: AppGroupBoardPersistence(),
            shared: shared
        ))
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

/// EventKit wiring belongs to the capture milestone; until it lands the board
/// captures nothing, which is the honest state for a device with no sources.
private struct PreviewCapture: CaptureProviding {
    func capture(now: Date) async -> CaptureOutcome {
        CaptureOutcome.empty(at: now)
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
}

enum AppLinks {
    @MainActor static func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
