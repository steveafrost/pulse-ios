import ThirdHandCore
import SwiftUI

/// The board (#17): four sections, the filter bar, the capture capsule and the
/// FAB. It owns the `BoardViewModel` and nothing else — every rule lives in the
/// view model or in `ThirdHandCore`.
public struct BoardView: View {
    @State private var model: BoardViewModel
    @State private var route: ThirdHandItem?
    @State private var isClosedPresented = false
    @Namespace private var boardNamespace

    let permission: PermissionCoordinator
    var onOpenSettings: () -> Void

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
        deepLinkItemID: String? = nil
    ) {
        _model = State(initialValue: model)
        self.permission = permission
        self.onOpenSettings = onOpenSettings
        self.deepLinkItemID = deepLinkItemID
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ThirdHandColor.surfaceCanvas.ignoresSafeArea()
                content
                floatingChrome
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: ThirdHandSpacing.xs) {
                    /// §8.1: the capture capsule sits with the filter bar, not over
                    /// the rows — floating it on top of the last card covers the
                    /// "show more" control.
                    HStack {
                        CaptureStatusCapsule(status: model.captureStatus, now: model.nowDate) {
                            Task { await model.refresh() }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, ThirdHandSpacing.screenMargin)

                    BoardFilterBar(
                        sources: model.availableSources,
                        totalCount: model.totalCount,
                        nowCount: model.nowCount,
                        filter: model.filter,
                        onChange: model.setFilter,
                        onReset: model.resetFilters
                    )
                }
                .padding(.bottom, ThirdHandSpacing.xs)
                .background(.bar)
            }
            .navigationTitle("Third Hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .navigationDestination(item: $route) { item in
                ItemDetailView(model: model.detailModel(for: item), namespace: boardNamespace)
            }
            .sheet(isPresented: $isClosedPresented) {
                ClosedItemsView(model: model.closedModel())
            }
            .task {
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
                    onOpenSettings: onOpenSettings
                )
            }
        case .empty(let reason):
            ScrollView {
                VStack(spacing: ThirdHandSpacing.s) {
                    ForEach(model.state.failures) { failure in
                        SourceBanner(failure: failure, onOpenSettings: onOpenSettings)
                    }
                    EmptyBoardView(
                        reason: reason,
                        lastCapturedAt: model.captureStatus.lastCapturedAt,
                        now: model.nowDate,
                        preferredSource: model.permissionState.preferredSource,
                        onRefresh: { Task { await model.refresh() } },
                        onConnect: { identity in Task { await connect(identity) } },
                        onNotNow: { permission.declineForNow() },
                        onOpenSettings: onOpenSettings,
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
                    SourceBanner(failure: failure, onOpenSettings: onOpenSettings)
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

    // MARK: Floating chrome (§6.3: capsule + FAB share one container)

    private var floatingChrome: some View {
        VStack(alignment: .trailing, spacing: ThirdHandSpacing.m) {
            ThirdHandFAB(
                title: model.fabTitle,
                caption: model.fabCaption,
                systemImage: model.topNowItem == nil ? "arrow.clockwise" : "checkmark"
            ) {
                if let item = model.topNowItem {
                    Task { await model.complete(item) }
                } else {
                    Task { await model.refresh() }
                }
            }
            .accessibilityIdentifier("board.fab")
        }
        .padding(.trailing, ThirdHandSpacing.screenMargin)
        .padding(.bottom, ThirdHandSpacing.m)
        .thirdHandGlassContainer(spacing: ThirdHandSpacing.m)
    }

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
