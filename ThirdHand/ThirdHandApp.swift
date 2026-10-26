import ThirdHandCore
import SwiftUI

@main
struct ThirdHandApp: App {
    @State private var permission = PermissionCoordinator()
    @State private var model: BoardViewModel
    /// The mailbox screen's state, created once so the form the user fills in and the
    /// status the board reports are the same object.
    @State private var mailbox: EmailAccountModel

    init() {
        let shared = SharedStore()
        let domain = DemoSeed.store()
        let store = StoreAdapter(domain)

        // One coordinator for the whole app: it is the only writer of the
        // transport files, so nothing else may construct a SnapshotWriter.
        let sync = SyncCoordinator.live(store: domain, paths: ThirdHandPaths())
        let capture = DemoSeed.capture(store: domain)

        let model = BoardViewModel(
            store: store,
            capture: capture.providing,
            persistence: AppGroupBoardPersistence(),
            shared: shared,
            sync: sync
        )

        // The mailbox screen's state. Constructed here so the same instance is used by
        // the Settings row, the form and the status line -- and so a capture pass can
        // report back into it.
        let mailbox = EmailAccountModel(
            accounts: UserDefaultsEmailAccountProvider(),
            accountsWriter: UserDefaultsEmailAccountProvider(),
            secrets: KeychainSecretStore()
        )
        _mailbox = State(initialValue: mailbox)

        // Every pass tells the mailbox screen what the mailbox did. Without this the
        // screen's status is whatever it was at launch. Set before the model is stored
        // so the first pass already reports.
        model.onCaptureOutcome = { outcome in mailbox.apply(outcome) }

        // The two directions the sync layer needs back into the UI, kept as
        // closures so `Pulse` is not a dependency of the sync types.
        sync.captureHandler = { await capture.runFull() }
        sync.onStoreChanged = { await model.reloadAfterSync() }
        sync.onPublished = { model.refreshSyncStatus() }

        #if canImport(ActivityKit) && os(iOS)
        // #31: one owner for the single Live Activity, kicked by every persist.
        model.liveActivity = ImminentMeetingController()
        #endif

        _model = State(initialValue: model)

        // Registration must happen before launch finishes; BGTaskScheduler traps on
        // a late or duplicate register, so `register()` is idempotent.
        BackgroundRefresh.register()
        BackgroundRefresh.attach(coordinator: sync)
    }

    /// #29: the widget's deep links. `thirdhand://board` is the whole-widget tap and needs
    /// no navigation; `thirdhand://item/<id>` opens that item's detail. An id the board no
    /// longer has is ignored rather than opening an empty sheet -- the item may have
    /// been closed from the Mac a second ago.
    @MainActor
    private func handle(_ url: URL) {
        if let id = DeepLink.itemID(from: url) {
            pendingItemID = id
        }
    }


    /// Read by `BoardView` on appear, then cleared.
    @State private var pendingItemID: String?

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            DemoRoot(model: model, permission: permission)
            #else
            BoardView(
                model: model,
                permission: permission,
                onOpenSettings: AppLinks.openSettings,
                deepLinkItemID: pendingItemID,
                mailbox: mailbox
            )
            .pulseSyncPolling(model.sync)
            .task { await permission.load() }
            .onOpenURL { url in handle(url) }
            #endif
        }
    }
}

#if DEBUG
/// A debug-only root that can present any screen directly, so a visual check of
/// the detail, the snooze sheet, the closed review, the empty states and the
/// loading skeleton does not need a UI test target to drive the tap. Any build
/// without `-ThirdHandDemoScreen` renders the ordinary board.
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
        case .settings:
            SettingsView(
                sources: DemoSeed.settingsSources,
                emailStatus: .unread(3),
                lastChecked: Fixtures.fixtureNow,
                onOpenEmail: {}
            )
        case .email:
            EmailAccountView(model: demoEmailModel(.notConnected))
        case .emailConnected:
            EmailAccountView(model: demoEmailModel(.connected))
        case .emailNeedsPassword:
            EmailAccountView(model: demoEmailModel(.needsPassword))
        }
    }
}

/// The three account states, wired to in-memory stores so a demo never touches the
/// real Keychain or a real mailbox.
enum EmailDemoState { case notConnected, connected, needsPassword }

@MainActor
private func demoEmailModel(_ state: EmailDemoState) -> EmailAccountModel {
    let account = EmailAccount.gmail(username: "steve@example.com")
    switch state {
    case .notConnected:
        return EmailAccountModel(
            accounts: StaticEmailAccountProvider(account: nil),
            accountsWriter: nil,
            secrets: InMemorySecretStore()
        )
    case .connected:
        return EmailAccountModel(
            accounts: StaticEmailAccountProvider(account: account),
            accountsWriter: nil,
            secrets: InMemorySecretStore(secrets: [account.keychainAccount: "demo"])
        )
    case .needsPassword:
        return EmailAccountModel(
            accounts: StaticEmailAccountProvider(account: account),
            accountsWriter: nil,
            secrets: InMemorySecretStore()
        )
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
        /// §8.3 surfaces, added in the craft pass.
        case settings, email, emailConnected, emailNeedsPassword
    }

    /// `-ThirdHandDemoScreen <name>` picks the screen; absent or unknown means the board.
    static var screen: Screen {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ThirdHandDemoScreen"), index + 1 < args.count else {
            return .board
        }
        return Screen(rawValue: args[index + 1]) ?? .board
    }
    #endif

    /// The source rows the demo Settings screen lists. Real values, so the screen is
    /// judged on realistic copy rather than placeholders.
    static var settingsSources: [SettingsView.SourceRow] {
        [
            .init(id: "calendar", source: .calendar, title: "Calendar", systemImage: "calendar", state: "Connected", needsAttention: false),
            .init(id: "reminders", source: .other, title: "Reminders", systemImage: "checklist", state: "Connected", needsAttention: false),
            .init(id: "slack", source: .slack, title: "Shared links", systemImage: "link", state: "Off in iOS Settings", needsAttention: true),
        ]
    }

    static func store() -> ItemStore {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ThirdHandDemoBoard") { return FixtureStore.make() }
        if args.contains("-ThirdHandDemoEmpty") { return ItemStore() }
        #endif
        return ItemStore()
    }

    /// Real capture on iOS; an empty pass everywhere else (macOS previews, the
    /// gallery). A device with no permission still gets a pass -- it reports the
    /// denial as a source failure, which is the banner the board expects.
    static func capture(store: ItemStore) -> Capture {
        #if os(iOS)
        #if DEBUG
        // Screenshot runs (`-ThirdHandDemoBoard`) must not touch EventKit.
        // `EventKitEventProvider.events` calls `requestFullAccessToEvents()` on
        // every pass, so on a simulator that has not been granted access the
        // system prompt covers the board on every capture -- which made every
        // App Store screenshot unusable. The board draws from `FixtureStore` in
        // this mode anyway, so capture has nothing to contribute.
        if ProcessInfo.processInfo.arguments.contains("-ThirdHandDemoBoard")
            || ProcessInfo.processInfo.arguments.contains("-ThirdHandDemoEmpty") {
            let inert = EmptyCapture()
            return Capture(
                providing: inert,
                runFull: { false },
                runIncremental: { false }
            )
        }
        #endif
        let engine = CaptureEngine(
            sources: [
                EventKitSource(provider: EventKitEventProvider()),
                RemindersSource(provider: EventKitReminderProvider()),
                // M7.1: the links the user shared from Slack, Gmail or GitHub via
                // the Share Extension. No OAuth, no network -- what the user
                // shared is what the board gets. See `docs/DEFERRED-SOURCES.md`
                // for the API path that would replace it.
                SharedLinkSource(provider: FileSharedLinkProvider()),
                // IMAP email. Inert until the user saves a mailbox in Settings:
                // with no account it throws `denied(.gmail)`, which the board
                // shows as "connect a mailbox" rather than an empty success.
                // See docs/DEFERRED-SOURCES.md for why IMAP, not Gmail OAuth.
                EmailSource(
                    transport: TLSIMAPTransport(),
                    accounts: UserDefaultsEmailAccountProvider(),
                    secrets: KeychainSecretStore()
                ),
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

/// The widget deep links, parsed as a value so the scheme contract is testable.
///
/// `App.onOpenURL` cannot be driven from a unit test, and the bug this replaces was
/// invisible precisely for that reason: the app registered `thirdhand` in its
/// Info.plist while the handler compared against `pulse`, so every widget tap was
/// silently dropped and both sides still "looked" correct in isolation.
enum DeepLink {
    /// The scheme in `project.yml` → `CFBundleURLSchemes`, and the one every
    /// `widgetURL` / `Link` in `ThirdHandWidgets` uses. One constant, so those cannot
    /// disagree again without this line changing.
    static let scheme = "thirdhand"

    /// The item id in `thirdhand://item/<id>`, or `nil` for the whole-widget tap
    /// (`thirdhand://board`) and for any URL that is not ours.
    ///
    /// An unknown id is not an error here: the board ignores an id it no longer has,
    /// because the item may have been closed from the Mac a second ago.
    static func itemID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "item" else { return nil }
        let raw = url.pathComponents.dropFirst().joined()
        guard !raw.isEmpty else { return nil }
        return raw.removingPercentEncoding ?? raw
    }
}
