import Foundation
import Testing
@testable import ThirdHandCore

@Suite("Horizon")
struct HorizonTests {

    /// A fixed "now": 2026-10-23 (a Friday) at 12:00 UTC.
    private let now = Fixture.date("2026-10-23T12:00:00.000Z")

    private func item(
        id: String = "calendar:event:1",
        kind: Kind = .deadline,
        priority: Priority = .normal,
        due: Date? = nil,
        status: Status = .open,
        firstSeenAt: Date = Fixture.now
    ) -> ThirdHandItem {
        ThirdHandItem(
            id: id,
            source: .calendar,
            kind: kind,
            title: "T",
            due: due,
            priority: priority,
            status: status,
            firstSeenAt: firstSeenAt,
            lastSeenAt: firstSeenAt,
            updatedAt: firstSeenAt,
            lastChangedBy: "run"
        )
    }

    private func horizon(_ item: ThirdHandItem) -> Horizon? {
        HorizonDerivation.horizon(of: item, at: now, calendar: Fixture.calendar)
    }

    // MARK: - The four buckets

    @Test("an undated high priority item lands in now")
    func undatedHighPriorityIsNow() {
        #expect(horizon(item(priority: .high)) == .now)
    }

    /// A due date outranks priority. This is a regression test: the rule used to be
    /// "high priority -> now" with no date check, so a high-priority reminder dated
    /// two months out sat in Now claiming it needed the user today.
    @Test("a due date outranks priority")
    func dueDateOutranksPriority() {
        // Two months out: Later, however high the priority.
        #expect(horizon(item(priority: .high, due: Fixture.date("2026-12-25T09:00:00.000Z"))) == .later)
        // Inside the three-day window but past today: Next, not Now.
        #expect(horizon(item(priority: .high, due: Fixture.date("2026-10-25T09:00:00.000Z"))) == .next)
        // Due today is still Now -- the date agrees with the priority.
        #expect(horizon(item(priority: .high, due: Fixture.date("2026-10-23T09:00:00.000Z"))) == .now)
    }

    @Test("due today or in the past lands in now")
    func dueTodayOrPastIsNow() {
        #expect(horizon(item(due: Fixture.date("2026-10-23T09:00:00.000Z"))) == .now)   // earlier today
        #expect(horizon(item(due: Fixture.date("2026-10-23T23:59:00.000Z"))) == .now)   // later today
        #expect(horizon(item(due: Fixture.date("2026-10-20T09:00:00.000Z"))) == .now)   // overdue
    }

    @Test("due within three days lands in next")
    func dueSoonIsNext() {
        #expect(horizon(item(due: Fixture.date("2026-10-24T09:00:00.000Z"))) == .next)  // tomorrow
        #expect(horizon(item(due: Fixture.date("2026-10-26T09:00:00.000Z"))) == .next)  // +3 days
    }

    @Test("due beyond three days lands in later")
    func dueLaterIsLater() {
        #expect(horizon(item(due: Fixture.date("2026-10-27T09:00:00.000Z"))) == .later) // +4 days
        #expect(horizon(item(due: Fixture.date("2026-12-01T09:00:00.000Z"))) == .later)
    }

    @Test("no due date with normal priority lands in later")
    func noDueIsLater() {
        #expect(horizon(item(due: nil)) == .later)
    }

    @Test("fyi is always nice to know, even when high priority or due now")
    func fyiIsAlwaysNiceToKnow() {
        #expect(horizon(item(kind: .fyi)) == .niceToKnow)
        #expect(horizon(item(kind: .fyi, priority: .high)) == .niceToKnow)
        #expect(horizon(item(kind: .fyi, due: Fixture.date("2026-10-20T09:00:00.000Z"))) == .niceToKnow)
    }

    // MARK: - Closed items

    @Test("closed items have no horizon")
    func closedHasNoHorizon() {
        for status in [Status.done, .dismissed, .resolved] {
            #expect(horizon(item(status: status)) == nil)
            #expect(horizon(item(priority: .high, status: status)) == nil)
            // The "would-be" bucket is still available for animation.
            #expect(HorizonDerivation.horizonIgnoringClosed(of: item(priority: .high, status: status), at: now, calendar: Fixture.calendar) == .now)
        }
    }

    @Test("isOnBoard is the closed-state predicate")
    func isOnBoardPredicate() {
        for status in [Status.done, .dismissed, .resolved] {
            #expect(!HorizonDerivation.isOnBoard(item(status: status), at: now))
        }
        for status in [Status.open, .waiting, .snoozed] {
            #expect(HorizonDerivation.isOnBoard(item(status: status), at: now))
        }
    }

    // MARK: - Snooze interaction

    @Test("a snoozed item respects the snooze window when deriving a bucket")
    func snoozeInteraction() {
        var snoozed = item(due: Fixture.date("2026-10-20T09:00:00.000Z")) // would be now
        snoozed.status = .snoozed
        snoozed.snoozedUntil = now.addingTimeInterval(3600)
        // Still snoozed, so it is not closed and still derives a bucket; the
        // bucket logic sees the due date, and the item stays on the board.
        #expect(HorizonDerivation.isOnBoard(snoozed, at: now))

        // A closed-by-user item that is also snoozed-in-the-past is closed.
        var doneSnoozed = snoozed
        doneSnoozed.status = .done
        #expect(horizon(doneSnoozed) == nil)
    }

    // MARK: - Store grouping

    @Test("the store groups items into the four buckets")
    func storeBuckets() async throws {
        let store = ItemStore()
        _ = try await store.upsert(
            detected: [
                Fixture.detected("calendar:event:now", title: "Now", priority: .high),
                Fixture.detected("calendar:event:next", title: "Next", due: Fixture.date("2026-10-25T09:00:00.000Z")),
                Fixture.detected("calendar:event:later", title: "Later", due: Fixture.date("2026-11-20T09:00:00.000Z")),
                Fixture.detected("calendar:event:fyi", title: "FYI", kind: .fyi, priority: .low),
            ],
            run: "run",
            now: Fixture.now
        )

        let board = await store.board(at: now, calendar: Fixture.calendar)
        #expect(board[.now]?.map(\.id) == ["calendar:event:now"])
        #expect(board[.next]?.map(\.id) == ["calendar:event:next"])
        #expect(board[.later]?.map(\.id) == ["calendar:event:later"])
        #expect(board[.niceToKnow]?.map(\.id) == ["calendar:event:fyi"])
    }

    @Test("board order matches the contract")
    func boardOrder() {
        #expect(Horizon.allCases.map(\.sortIndex) == [0, 1, 2, 3])
        #expect(Horizon.allCases == [.now, .next, .later, .niceToKnow])
    }

    // MARK: - Sorting

    @Test("sort is priority ascending, then due ascending with nil last, then firstSeenAt")
    func sortOrder() {
        let base = Fixture.now
        let items = [
            item(id: "d", priority: .low, due: nil, firstSeenAt: base),
            item(id: "c", priority: .normal, due: Fixture.date("2026-10-25T09:00:00.000Z"), firstSeenAt: base),
            item(id: "a", priority: .high, due: Fixture.date("2026-10-26T09:00:00.000Z"), firstSeenAt: base),
            item(id: "b", priority: .high, due: Fixture.date("2026-10-24T09:00:00.000Z"), firstSeenAt: base),
            item(id: "e", priority: .normal, due: nil, firstSeenAt: base),
            item(id: "f", priority: .normal, due: Fixture.date("2026-10-24T09:00:00.000Z"), firstSeenAt: base),
        ]

        // high first; within high, earlier due first; normal sorts its dated item
        // before its undated one; low (undated) last.
        #expect(ThirdHandItemSort.sorted(items).map(\.id) == ["b", "a", "f", "c", "e", "d"])
    }

    @Test("ties break by firstSeenAt, then id")
    func sortTieBreak() {
        let earlier = Fixture.date("2026-10-01T00:00:00.000Z")
        let items = [
            item(id: "second", priority: .high, due: nil, firstSeenAt: now),
            item(id: "first", priority: .high, due: nil, firstSeenAt: earlier),
        ]
        #expect(ThirdHandItemSort.sorted(items).map(\.id) == ["first", "second"])

        // Identical in every ranked field: the sort stays total and stable via id,
        // unlike the JS comparator which returns 1 for a tie.
        let twins = [item(id: "z", priority: .normal), item(id: "a", priority: .normal)]
        #expect(ThirdHandItemSort.sorted(twins).map(\.id) == ["a", "z"])
    }

    @Test("due dates sort as instants, not as strings")
    func sortUsesInstants() {
        // Same calendar day, different times: string and instant order agree here,
        // but an offset form would break string ordering, so assert instants.
        let earlier = item(id: "earlier", due: Fixture.date("2026-10-24T08:00:00.000Z"))
        let later = item(id: "later", due: Fixture.date("2026-10-24T18:00:00.000Z"))
        #expect(ThirdHandItemSort.sorted([later, earlier]).map(\.id) == ["earlier", "later"])
    }

    @Test("every bucket exists on the board even when empty")
    func emptyBucketsAbsent() async {
        let store = ItemStore()
        let board = await store.board(at: now, calendar: Fixture.calendar)
        #expect(board.isEmpty)
    }
}
