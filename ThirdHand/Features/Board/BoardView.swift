import ThirdHandCore
import SwiftUI

/// The board (#17): four sections, the filter bar, the capture capsule and the
/// FAB. It owns the `BoardViewModel` and nothing else — every rule lives in the
/// view model or in `ThirdHandCore`.
public struct BoardView: View {
    @State private var model: BoardViewModel
    @State private var route: ThirdHandItem?
    @State private var isClosedPresented = false
    @State private var isSettingsPresented = false
    @State private var isMailboxPresented = false
    @State private var isSettingsMailboxPresented = false
    /// The mailbox state the board last ran a pass against.
    ///
    /// Dismissing the form is not proof anything changed -- the user may have opened
    /// it and closed it -- so a pass is only worth spending when the account actually
    /// did change. Comparing the phase is the cheap version of that question: connect
    /// and disconnect both move it.
    @State private var passAimedAt: EmailAccountModel.Phase?
    @Namespace private var boardNamespace

    let permission: PermissionCoordinator
    var onOpenSettings: () -> Void

    /// The mailbox, when this build has one to configure.
    ///
    /// This is what makes the mailbox screen reachable at all. Until now the screen
    /// existed and nothing could open it: it was constructed only inside the DEBUG
    /// `DemoRoot`, and every "Open Settings" button on the board called
    /// `AppLinks.openSettings`, which opens *iOS* Settings — a place with no mailbox
    /// row, no form and no password field. A user told to connect a mailbox could
    /// walk the whole app and never find the form.
    ///
    /// Optional so previews, tests and the `EmptyCapture` builds still construct a
    /// board with exactly the arguments they already passed.
    var mailbox: EmailAccountModel?

    /// #29: an item id arrived from a widget tap (`thirdhand://item/<id>`). Consumed once
    /// on appear, then the board routes to that item's detail.
    var deepLinkItemID: String?

    @Environment(\.pulseMotion) private var motion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: BoardViewModel,
        permission: PermissionCoordinator,
        onOpenSettings: @escaping () -> Void = {},
        deepLinkItemID: String? = nil,
        mailbox: EmailAccountModel? = nil
    ) {
        _model = State(initialValue: model)
        self.permission = permission
        self.onOpenSettings = onOpenSettings
        self.deepLinkItemID = deepLinkItemID
        self.mailbox = mailbox
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ThirdHandColor.surfaceCanvas.ignoresSafeArea()
                content
            }
            /// The top inset that used to hold the capture capsule and the source
            /// chips is gone. Both moved for the same reason: the board is the
            /// product, and a permanent chrome strip above it pushed row one further
            /// down on every launch. Connections are a Settings fact, and the sync
            /// readout is now one glyph in the navigation bar (`SyncStatusButton`)
            /// that opens on demand instead of spending a row of height always.
            .navigationTitle("Pulse")
            .navigationBarTitleDisplayMode(.inline)
            /// Search is native, replacing the "Search" chip the removed filter bar
            /// carried. `.automatic` rather than `.always` on purpose: `.always`
            /// pins a search field under the title and rebuilds the permanent
            /// chrome row this change exists to remove. Here it is reachable by
            /// pulling the board down, and costs no height until used.
            .searchable(
                text: Binding(
                    get: { model.filter.query },
                    set: { model.setFilter(BoardFilter(query: $0)) }
                ),
                /// `.navigationBarDrawer`, not `.toolbar`. On iOS 26 `.toolbar`
                /// promotes search to a floating bar pinned to the *bottom* of the
                /// screen, where it sits on top of the last card — confirmed on a
                /// simulator. The drawer keeps it in the navigation bar's own
                /// drawer: one compact row, in the space the removed capsule and
                /// chip rows used to occupy.
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: BoardCopy.searchPrompt
            )
            .toolbar {
                if mailbox != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("board.settings")
                    }
                }
                /// Sync state sits next to History, both on the right. It is a
                /// status glyph, not a button that captures: tapping opens the
                /// detail popover, and pull-to-refresh on the board is what
                /// actually runs a pass.
                ToolbarItem(placement: .topBarTrailing) {
                    SyncStatusButton(
                        status: model.captureStatus,
                        failures: model.state.failures,
                        now: model.nowDate
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isClosedPresented = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Recently closed")
                    .accessibilityIdentifier("board.closed")
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                if let mailbox { settingsSheet(mailbox) }
            }
            // The mailbox form opened straight from a board banner. It needs its own
            // sheet slot because the Settings sheet is not up in that path -- SwiftUI
            // drops a second `.sheet` presented from the same view while the first is
            // still on screen.
            .sheet(isPresented: $isMailboxPresented, onDismiss: checkMailboxIfChanged) {
                if let mailbox { EmailAccountView(model: mailbox) }
            }
            .navigationDestination(item: $route) { item in
                ItemDetailView(model: model.detailModel(for: item), namespace: boardNamespace)
            }
            .sheet(isPresented: $isClosedPresented) {
                ClosedItemsView(model: model.closedModel())
            }
            .task {
                passAimedAt = mailbox?.phase
                await load()
                routeDeepLinkIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { Task { await model.markSeen() } }
            }
            .accessibilityIdentifier("board.root")
        }
        .pulseMotionScope()
    }

    /// The in-app Settings screen, with the mailbox row wired to the real form.
    ///
    /// `onOpenEmail` used to be `{}` — the row was drawn, tapped, and did nothing.
    /// It now opens the mailbox screen, which is the only place a mailbox can be
    /// connected.
    @ViewBuilder
    private func settingsSheet(_ mailbox: EmailAccountModel) -> some View {
        SettingsView(
            sources: settingsSources,
            emailStatus: mailbox.status,
            lastChecked: model.captureStatus.lastCapturedAt,
            onOpenEmail: { isSettingsMailboxPresented = true }
        )
        // Presented *inside* the Settings sheet: a sheet presented from the board
        // while Settings is already up is silently dropped.
        .sheet(isPresented: $isSettingsMailboxPresented, onDismiss: checkMailboxIfChanged) {
            EmailAccountView(model: mailbox)
        }
    }

    /// Runs a capture pass when the mailbox was connected or disconnected while the
    /// sheet was up.
    ///
    /// Without it the screen reports "Not connected" until the next scheduled pass, so
    /// connecting a mailbox looks like it did nothing. A pass is the only thing that
    /// can turn a saved credential into a real answer.
    private func checkMailboxIfChanged() {
        guard let mailbox else { return }
        defer { passAimedAt = mailbox.phase }
        guard passAimedAt != mailbox.phase else { return }
        Task { await model.refresh() }
    }

    /// The source truth table, read from the same permission state the board uses.
    ///
    /// Each row carries its own label and glyph because the wire enum does not line
    /// up with the user's words: reminders and shared links both travel as `.other`,
    /// so reading `source.title` would label Reminders "Link".
    private var settingsSources: [SettingsView.SourceRow] {
        func status(_ value: PermissionStatus) -> (String, Bool) {
            switch value {
            case .granted: ("Connected", false)
            case .notDetermined: ("Not turned on", true)
            case .denied: ("Off in iOS Settings", true)
            case .restricted: ("Not allowed on this device", true)
            }
        }
        let calendar = status(model.permissionState.calendar)
        let reminders = status(model.permissionState.reminders)
        return [
            .init(id: "calendar", source: .calendar, title: "Calendar", systemImage: "calendar", state: calendar.0, needsAttention: calendar.1),
            .init(id: "reminders", source: .other, title: "Reminders", systemImage: "checklist", state: reminders.0, needsAttention: reminders.1),
        ]
    }

    /// Where "Open Settings" should go for one failure.
    ///
    ///
    /// A paused *mailbox* has no fix in iOS Settings — there is no row there to turn
    /// on — so that button has to open the form the user can actually complete. Every
    /// other source really is fixed in iOS Settings.
    private func settingsDestination(for identity: SourceIdentity) -> () -> Void {
        if identity == .email, mailbox != nil {
            return { isMailboxPresented = true }
        }
        return onOpenSettings
    }

    /// Opens the item a widget row pointed at, if the board still has it.
    ///
    /// Resolved from the board rather than from the id alone, so a link to an item that
    /// was closed from the Mac since the widget rendered simply opens the board instead
    /// of a sheet with no backing item.
    private func routeDeepLinkIfNeeded() {
        guard let id = deepLinkItemID else { return }
        route = Horizon.allCases.flatMap { model.board[$0] ?? [] }.first { $0.id == id }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView { LoadingBoardView() }
        case .failed(let message):
            ScrollView {
                ErrorBoardView(
                    failures: [SourceFailure(identity: .calendar, reason: .failed(message))],
                    onRetry: { Task { await model.refresh() } },
                    onOpenSettings: settingsDestination(for: .calendar)
                )
            }
        case .empty(let reason):
            ScrollView {
                VStack(spacing: ThirdHandSpacing.s) {
                    ForEach(model.state.failures) { failure in
                        SourceBanner(
                            failure: failure,
                            onOpenSettings: settingsDestination(for: failure.identity)
                        )
                    }
                    EmptyBoardView(
                        reason: reason,
                        lastCapturedAt: model.captureStatus.lastCapturedAt,
                        now: model.nowDate,
                        preferredSource: model.permissionState.preferredSource,
                        onRefresh: { Task { await model.refresh() } },
                        onConnect: { identity in Task { await connect(identity) } },
                        onNotNow: { permission.declineForNow() },
                        onOpenSettings: settingsDestination(for: reason.pausedSource),
                        onResetFilters: model.resetFilters
                    )
                }
            }
        case .ready, .degraded:
            boardScroll
        }
    }

    private var boardScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ThirdHandSpacing.xxl) {
                ForEach(model.state.failures) { failure in
                    SourceBanner(
                        failure: failure,
                        onOpenSettings: settingsDestination(for: failure.identity)
                    )
                }

                ForEach(Array(model.visibleHorizons.enumerated()), id: \.element) { sectionIndex, horizon in
                    BoardSectionView(
                        horizon: horizon,
                        items: model.items(in: horizon),
                        visibleCount: model.visibleItems(in: horizon).count,
                        isExpanded: model.isExpanded(horizon),
                        now: model.nowDate,
                        lastViewedAt: model.lastViewedAt,
                        /// §7.5: the stagger runs across the board, so each section
                        /// starts where the previous one left off. Derived from the
                        /// same collapse limits the rows use.
                        loadInOffset: loadInOffset(forSection: sectionIndex),
                        onToggle: {
                            withAnimation(motion.sectionExpansion) { model.toggleExpansion(horizon) }
                        },
                        onRowOpen: { item in route = item },
                        onRowAction: handle
                    )
                    .transition(.opacity)
                }
            }
            .padding(.top, ThirdHandSpacing.m)
            /// Room for the capture capsule and the FAB, which are a floating
            /// overlay rather than a safe-area inset, so the last row is reachable.
            .padding(.bottom, bottomInset)
            .frame(maxWidth: ThirdHandSpacing.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        /// This is the board's refresh gesture, and it is load-bearing: the capture
        /// capsule that used to sit at the top and force a pass is gone, and the
        /// sync status pill that replaced it does not capture on tap. A board you
        /// cannot ask to update by pulling on it is a snapshot.
        .refreshable { await model.refresh() }
        .animation(motion.listGap, value: model.visibleHorizons)
    }

    /// How many rows rendered before `sectionIndex` — the starting index for that
    /// section's staggered load-in (§7.5). Counts what is actually on screen, so an
    /// expanded section pushes the following sections' delay along with it.
    private func loadInOffset(forSection sectionIndex: Int) -> Int {
        model.visibleHorizons.prefix(sectionIndex).reduce(0) { total, horizon in
            total + model.visibleItems(in: horizon).count
        }
    }

    /// The FAB floats over the scroll view and grows with Dynamic Type, so the
    /// scroll content needs an inset at least as tall as the floating chrome or
    /// the last row sits underneath it.
    ///
    /// This used to be a hand-tuned table of per-size-class offsets, which drifted:
    /// at AX5 the chrome still covered row content, because a table of constants
    /// cannot track a type size that scales continuously. `@ScaledMetric` scales
    /// with the same text metrics the FAB's own label uses, so the two cannot
    /// disagree at any size, including the AX sizes the table never covered well.
    @ScaledMetric(relativeTo: .body) private var scaledChromeHeight: CGFloat = 160

    private var bottomInset: CGFloat {
        ThirdHandSpacing.boardBottomInset + scaledChromeHeight
    }

    // MARK: No floating action button
    //
    // The FAB used to sit bottom-right and complete whatever the topmost Now item
    // was. That is the wrong gesture for this product: Pulse is a board you work
    // item by item, and a single button that silently finishes "the most important
    // thing" both guesses which thing you meant and hides the one action that
    // should stay deliberate. Completion lives on each row's own control, where the
    // item you touched is the item that closes.
    //
    // Refresh did not depend on it either: the capture capsule at the top and
    // pull-to-refresh both drive `model.refresh()`, so removing the FAB stranded no
    // behaviour.

    // MARK: Intents

    private func load() async {
        await permission.load()
        model.setPermissionState(permission.state)
        await model.load()
        if model.state == .empty(.neverCaptured) {
            // §9.2: nothing has ever been captured, so make the first pass.
            await model.refresh()
        }
    }

    private func connect(_ identity: SourceIdentity) async {
        let status = await permission.allow(identity)
        model.setPermissionState(permission.state)
        if status.isUsable { await model.refresh() }
    }

    private func handle(_ item: ThirdHandItem, _ action: BoardItemRow.LocalAction) {
        switch action {
        case .done: Task { await model.complete(item) }
        case .dismiss: Task { await model.dismiss(item) }
        case .snooze:
            route = item
        case .reopen:
            route = item
        case .copy(let text):
            Pasteboard.write(text)
        case .open(let url):
            openURL(url)
        }
    }
}
