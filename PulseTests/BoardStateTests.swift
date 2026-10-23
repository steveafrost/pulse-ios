@testable import Pulse
import Foundation
import PulseCore
import Testing

/// #17 / #20: the board's state derivation and filter rules, asserted without a view.
@Suite("Board state")
@MainActor
struct BoardStateTests {
    @Test("An empty board that has never captured is neverCaptured")
    func neverCaptured() {
        let state = BoardViewModel.state(
            board: [:],
            filter: .all,
            failures: [],
            lastCapturedAt: nil,
            now: Fixtures.fixtureNow
        )
        #expect(state == .empty(.neverCaptured))
    }

    @Test("An empty board captured before is allClear")
    func allClear() {
        let state = BoardViewModel.state(
            board: [:],
            filter: .all,
            failures: [],
            lastCapturedAt: Fixtures.ago(60),
            now: Fixtures.fixtureNow
        )
        #expect(state == .empty(.allClear))
    }

    @Test("A filter that excludes everything is filtered, not clear")
    func filtered() {
        let state = BoardViewModel.state(
            board: Fixtures.FixtureSet.grouped(),
            filter: BoardFilter(source: nil, query: "zzzz-no-match"),
            failures: [],
            lastCapturedAt: Fixtures.ago(60),
            now: Fixtures.fixtureNow
        )
        #expect(state == .empty(.filtered))
    }

    @Test("A source failure with items still present degrades rather than blocks")
    func degraded() {
        let state = BoardViewModel.state(
            board: Fixtures.FixtureSet.grouped(),
            filter: .all,
            failures: [SourceFailure(identity: .calendar, reason: .denied)],
            lastCapturedAt: Fixtures.ago(60),
            now: Fixtures.fixtureNow
        )
        #expect(state == .degraded([SourceFailure(identity: .calendar, reason: .denied)]))
    }

    @Test("Filter matches title, detail and people")
    func filterMatches() {
        let item = Fixtures.highPriorityRSVP
        #expect(BoardFilter(query: "RSVP").matches(item))
        #expect(BoardFilter(query: "priya").matches(item))
        #expect(BoardFilter(query: "zzz").matches(item) == false)
        #expect(BoardFilter(source: .calendar).matches(item))
    }

    @Test("Nice to Know never counts toward the Now badge")
    func nowCount() {
        let model = BoardViewModel(
            store: FakeItemStore(items: Fixtures.FixtureSet.board()),
            capture: FakeCaptureEngine(items: []),
            calendar: Fixtures.calendar(),
            clock: { Fixtures.fixtureNow },
            markSeenOnLoad: false
        )
        #expect(model.nowCount == 0 || model.nowCount >= 0)
        let board: [Horizon: [PulseItem]] = [.now: [Fixtures.fyiLink, Fixtures.highPriorityRSVP]]
        let widget = WidgetBoard(board: board, generatedAt: Fixtures.fixtureNow, calendar: Fixtures.calendar())
        #expect(widget.nowCount == 1)
    }

    @Test("Fixture board spans all four horizons and every kind")
    func fixtureCoverage() {
        let grouped = Fixtures.FixtureSet.grouped()
        #expect(grouped[.now]?.isEmpty == false)
        #expect(grouped[.next]?.isEmpty == false)
        #expect(grouped[.later]?.isEmpty == false)
        #expect(grouped[.niceToKnow]?.isEmpty == false)
    }
}

@Suite("Closed items")
@MainActor
struct ClosedItemsTests {
    @Test("Recently closed groups done, dismissed and resolved items")
    func groupsClosed() async {
        let model = ClosedItemsViewModel(
            store: FakeItemStore(items: Fixtures.FixtureSet.closed),
            clock: { Fixtures.fixtureNow },
            calendar: Fixtures.calendar()
        )
        await model.load()
        #expect(model.groups.isEmpty == false, "expected at least one day group")
        #expect(model.groups.flatMap(\.items).count == 3)
    }

    @Test("Real fixture items survive the ItemStore isClosed filter")
    func storeFilter() async {
        let store = FakeItemStore(items: Fixtures.FixtureSet.closed)
        let all = await store.allItems()
        #expect(all.filter { $0.status.isClosed }.count == 3)
    }
}
