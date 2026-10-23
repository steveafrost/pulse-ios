import PulseCore
import SwiftUI

/// The board (#17): four sections, the filter bar, the capture capsule and the
/// FAB. It owns the `BoardViewModel` and nothing else — every rule lives in the
/// view model or in `PulseCore`.
public struct BoardView: View {
    @State private var model: BoardViewModel
    @State private var route: PulseItem?
    @State private var isClosedPresented = false
    @Namespace private var boardNamespace

    let permission: PermissionCoordinator
    var onOpenSettings: () -> Void

    @Environment(\.pulseMotion) private var motion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: BoardViewModel,
        permission: PermissionCoordinator,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.permission = permission
        self.onOpenSettings = onOpenSettings
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                PulseColor.surfaceCanvas.ignoresSafeArea()
                content
                floatingChrome
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: PulseSpacing.xs) {
                    /// §8.1: the capture capsule sits with the filter bar, not over
                    /// the rows — floating it on top of the last card covers the
                    /// "show more" control.
                    HStack {
                        CaptureStatusCapsule(status: model.captureStatus, now: model.nowDate) {
                            Task { await model.refresh() }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, PulseSpacing.screenMargin)

                    BoardFilterBar(
                        sources: model.availableSources,
                        totalCount: model.totalCount,
                        nowCount: model.nowCount,
                        filter: model.filter,
                        onChange: model.setFilter,
                        onReset: model.resetFilters
                    )
                }
                .padding(.bottom, PulseSpacing.xs)
                .background(.bar)
            }
            .navigationTitle("Pulse")
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
            .task { await load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { Task { await model.markSeen() } }
            }
            .accessibilityIdentifier("board.root")
        }
        .pulseMotionScope()
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
                VStack(spacing: PulseSpacing.s) {
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
            LazyVStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                ForEach(model.state.failures) { failure in
                    SourceBanner(failure: failure, onOpenSettings: onOpenSettings)
                }

                ForEach(model.visibleHorizons, id: \.self) { horizon in
                    BoardSectionView(
                        horizon: horizon,
                        items: model.items(in: horizon),
                        visibleCount: model.visibleItems(in: horizon).count,
                        isExpanded: model.isExpanded(horizon),
                        now: model.nowDate,
                        lastViewedAt: model.lastViewedAt,
                        onToggle: {
                            withAnimation(motion.sectionExpansion) { model.toggleExpansion(horizon) }
                        },
                        onRowOpen: { item in route = item },
                        onRowAction: handle
                    )
                    .transition(.opacity)
                }
            }
            .padding(.top, PulseSpacing.m)
            /// Room for the capture capsule and the FAB, which are a floating
            /// overlay rather than a safe-area inset, so the last row is reachable.
            .padding(.bottom, bottomInset)
            .frame(maxWidth: PulseSpacing.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .animation(motion.listGap, value: model.visibleHorizons)
    }

    /// The FAB floats over the scroll view and grows with Dynamic Type, so a fixed
    /// inset leaves the last row underneath it. Derived from the size class rather
    /// than measured, which keeps the scroll view's layout pure.
    private var bottomInset: CGFloat {
        var inset = PulseSpacing.boardBottomInset + 160
        switch dynamicTypeSize {
        case .accessibility1: inset += 60
        case .accessibility2: inset += 110
        case .accessibility3: inset += 170
        case .accessibility4: inset += 230
        case .accessibility5: inset += 290
        default: break
        }
        return inset
    }

    // MARK: Floating chrome (§6.3: capsule + FAB share one container)

    private var floatingChrome: some View {
        VStack(alignment: .trailing, spacing: PulseSpacing.m) {
            PulseFAB(
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
        .padding(.trailing, PulseSpacing.screenMargin)
        .padding(.bottom, PulseSpacing.m)
        .pulseGlassContainer(spacing: PulseSpacing.m)
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

    private func handle(_ item: PulseItem, _ action: BoardItemRow.LocalAction) {
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
