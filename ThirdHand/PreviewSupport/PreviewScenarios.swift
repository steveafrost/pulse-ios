#if DEBUG
import ThirdHandCore
import SwiftUI

/// #23: one named preview per screen state, all driven by `Fixtures` and the
/// fakes, so nothing here touches EventKit, disk or the network.
@MainActor
public enum PreviewFactory {
    public static func boardViewModel(
        items: [ThirdHandItem] = Fixtures.FixtureSet.board(),
        failures: [SourceFailure] = [],
        lastCapturedAt: Date? = Fixtures.ago(120),
        filter: BoardFilter = .all,
        permission: PermissionState = PermissionState(calendar: .granted, reminders: .granted),
        clock: Date = Fixtures.fixtureNow
    ) -> BoardViewModel {
        let shared = SharedStore(defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)") ?? .standard)
        if let lastCapturedAt { shared.set(lastCapturedAt, for: .lastCaptureAt) }
        let model = BoardViewModel(
            store: FakeItemStore(items: items, lastViewedAt: Fixtures.ago(60 * 60 * 2)),
            capture: FakeCaptureEngine(items: items, failures: failures, at: clock),
            persistence: InMemoryBoardPersistence(),
            shared: shared,
            permissionState: permission,
            calendar: Fixtures.calendar(),
            clock: { clock },
            markSeenOnLoad: false
        )
        model.setFilter(filter)
        return model
    }

    public static func loadedBoard(
        items: [ThirdHandItem] = Fixtures.FixtureSet.board(),
        failures: [SourceFailure] = []
    ) -> BoardViewModel {
        let model = boardViewModel(items: items, failures: failures)
        Task { await model.load() }
        return model
    }

    public static func detail(_ item: ThirdHandItem) -> ItemDetailViewModel {
        ItemDetailViewModel(
            item: item,
            store: FakeItemStore(items: [item]),
            clock: { Fixtures.fixtureNow }
        )
    }

    public static func closedModel() -> ClosedItemsViewModel {
        ClosedItemsViewModel(
            store: FakeItemStore(items: Fixtures.FixtureSet.closed),
            clock: { Fixtures.fixtureNow },
            calendar: Fixtures.calendar()
        )
    }
}

// MARK: - Board

#Preview("Preview: Board — full") {
    BoardView(model: PreviewFactory.loadedBoard(), permission: PermissionCoordinator(defaults: previewDefaults()))
}

#Preview("Preview: Board — loading") {
    BoardView(model: PreviewFactory.boardViewModel(), permission: PermissionCoordinator(defaults: previewDefaults()))
}

#Preview("Preview: Board — all clear") {
    BoardView(
        model: PreviewFactory.boardViewModel(items: [], lastCapturedAt: Fixtures.ago(120)),
        permission: PermissionCoordinator(defaults: previewDefaults())
    )
}

#Preview("Preview: Board — never captured") {
    BoardView(
        model: PreviewFactory.boardViewModel(items: [], lastCapturedAt: nil),
        permission: PermissionCoordinator(defaults: previewDefaults())
    )
}

#Preview("Preview: Board — degraded, calendar denied") {
    BoardView(
        model: PreviewFactory.loadedBoard(
            failures: [SourceFailure(identity: .calendar, reason: .denied)]
        ),
        permission: PermissionCoordinator(
            state: PermissionState(calendar: .denied, reminders: .granted),
            defaults: previewDefaults()
        )
    )
}

#Preview("Preview: Board — dark") {
    BoardView(model: PreviewFactory.loadedBoard(), permission: PermissionCoordinator(defaults: previewDefaults()))
        .preferredColorScheme(.dark)
}

#Preview("Preview: Board — AX5") {
    BoardView(model: PreviewFactory.loadedBoard(), permission: PermissionCoordinator(defaults: previewDefaults()))
        .dynamicTypeSize(.accessibility5)
}

/// Previews must never share persisted defaults with the app.
@MainActor
private func previewDefaults() -> UserDefaults {
    UserDefaults(suiteName: "preview-\(UUID().uuidString)") ?? .standard
}

// MARK: - Empty states

#Preview("Preview: EmptyBoardView — all clear") {
    EmptyBoardView(reason: .allClear, lastCapturedAt: Fixtures.ago(120), now: Fixtures.fixtureNow)
}

#Preview("Preview: EmptyBoardView — never captured") {
    EmptyBoardView(reason: .neverCaptured, now: Fixtures.fixtureNow)
}

#Preview("Preview: EmptyBoardView — filtered") {
    EmptyBoardView(reason: .filtered, now: Fixtures.fixtureNow)
}

#Preview("Preview: EmptyBoardView — AX5") {
    EmptyBoardView(reason: .neverCaptured, now: Fixtures.fixtureNow)
        .dynamicTypeSize(.accessibility5)
}

// MARK: - Loading and error

#Preview("Preview: LoadingBoardView") {
    ScrollView { LoadingBoardView() }
        .background(ThirdHandColor.surfaceCanvas)
}

#Preview("Preview: ErrorBoardView — one source down") {
    ErrorBoardView(
        failures: [SourceFailure(identity: .calendar, reason: .denied)],
        onRetry: {},
        onOpenSettings: {}
    )
    .background(ThirdHandColor.surfaceCanvas)
}

#Preview("Preview: SourceBanner") {
    SourceBanner(failure: SourceFailure(identity: .calendar, reason: .denied), onOpenSettings: {})
        .background(ThirdHandColor.surfaceCanvas)
}

// MARK: - Detail

#Preview("Preview: ItemDetailView — open, three quick actions") {
    ItemDetailView(model: PreviewFactory.detail(Fixtures.withThreeQuickActions))
}

#Preview("Preview: ItemDetailView — waiting") {
    ItemDetailView(model: PreviewFactory.detail(Fixtures.waitingItem))
}

#Preview("Preview: ItemDetailView — snoozed") {
    ItemDetailView(model: PreviewFactory.detail(Fixtures.snoozedUntilTomorrow))
}

#Preview("Preview: ItemDetailView — done with reason") {
    ItemDetailView(model: PreviewFactory.detail(Fixtures.doneWithReason))
}

#Preview("Preview: ItemDetailView — no quick actions") {
    ItemDetailView(model: PreviewFactory.detail(Fixtures.imminentMeeting))
}

#Preview("Preview: ItemDetailView — AX5") {
    ItemDetailView(model: PreviewFactory.detail(Fixtures.withThreeQuickActions))
        .dynamicTypeSize(.accessibility5)
}

// MARK: - Snooze and closed

#Preview("Preview: SnoozeMenu — morning") {
    SnoozeMenu(now: Fixtures.fixtureNow, calendar: Fixtures.calendar()) { _ in }
}

#Preview("Preview: SnoozeMenu — after 18:00, no evening option") {
    SnoozeMenu(now: Fixtures.after(Fixtures.hour(11)), calendar: Fixtures.calendar()) { _ in }
}

#Preview("Preview: ClosedItemsView") {
    ClosedItemsView(model: PreviewFactory.closedModel())
}

// MARK: - Onboarding

#Preview("Preview: PermissionPreambleView — calendar") {
    PermissionPreambleView(onAllow: { _ in }, onNotNow: {})
}

#Preview("Preview: PermissionPreambleView — dark") {
    PermissionPreambleView(onAllow: { _ in }, onNotNow: {})
        .preferredColorScheme(.dark)
}

#Preview("Preview: PermissionPreambleView — AX5") {
    PermissionPreambleView(onAllow: { _ in }, onNotNow: {})
        .dynamicTypeSize(.accessibility5)
}
#endif
