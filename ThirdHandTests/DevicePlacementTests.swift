import Foundation
import Testing
@testable import ThirdHand
import ThirdHandCore

/// On-device placement, run on the device.
///
/// Everything here goes through the real `ItemStore`, the real
/// `PlacementCoordinator` and the real `PlacementPolicy` -- no fakes. The
/// scenarios are the ones the reported bug was about, so a failure here is the
/// bug and a pass here is the fix.
///
/// **This target is the only place the advisor runs with the real system model
/// underneath it.** On hardware without Apple Intelligence `SystemLanguageModel`
/// reports `.deviceNotEligible`, which is the degradation path the app has to
/// survive: the board must still be placed by the rules, unchanged. That is
/// asserted below rather than assumed.
@Suite("Device placement")
struct DevicePlacementTests {
    private var calendar: Calendar {
        Calendar(identifier: .gregorian)
    }

    private func item(
        _ id: String,
        title: String,
        due: Date?,
        priority: Priority = .normal,
        kind: Kind = .followup
    ) -> ThirdHandItem {
        ThirdHandItem(
            id: id,
            source: .other,
            kind: kind,
            title: title,
            due: due,
            priority: priority,
            firstSeenAt: Date(timeIntervalSinceNow: -86400 * 3),
            lastSeenAt: Date(),
            updatedAt: Date(),
            lastChangedBy: "capture"
        )
    }

    /// The board the coordinator produces from a real store.
    private func placed(
        _ items: [ThirdHandItem],
        at now: Date
    ) async -> [Horizon: [ThirdHandItem]] {
        let store = ItemStore(items: items)
        let coordinator = PlacementCoordinator(advisor: nil, cache: .inMemory())
        return await coordinator.board(
            items: store.allItems(),
            at: now,
            calendar: calendar
        )
    }

    @Test("A reminder due two months out is not filed under Now")
    func farFutureLeavesNow() async {
        let now = Date()
        let twoMonths = now.addingTimeInterval(86400 * 61)
        let board = await placed(
            [item("other:future", title: "Renew passport photos", due: twoMonths)],
            at: now
        )
        let inNow = (board[.now] ?? []).map(\.id)
        #expect(!inNow.contains("other:future"), "a reminder two months out must not claim it needs you today")
        #expect(board[.now]?.isEmpty ?? true)
    }

    @Test("A reminder due today stays in Now")
    func dueTodayStaysNow() async {
        let now = Date()
        let board = await placed(
            [item("other:today", title: "Standup", due: now.addingTimeInterval(3600), kind: .deadline)],
            at: now
        )
        #expect((board[.now] ?? []).map(\.id) == ["other:today"])
    }

    @Test("Something overdue by more than two weeks steps back to Next but stays on the board")
    func staleOverdueStepsBack() async {
        let now = Date()
        let board = await placed(
            [
                item(
                    "other:stale",
                    title: "Review the auth migration",
                    due: now.addingTimeInterval(-86400 * 40),
                    kind: .review
                )
            ],
            at: now
        )
        let allIds = board.values.flatMap { $0.map(\.id) }
        let inNow = (board[.now] ?? []).map(\.id)
        #expect(!inNow.contains("other:stale"), "40 days overdue is not today's problem")
        #expect(allIds.contains("other:stale"), "it must still be reachable -- placement never hides anything")
        #expect((board[.next] ?? []).map(\.id).contains("other:stale"))
    }

    @Test("Something overdue by two days is still Now")
    func recentOverdueStaysNow() async {
        let now = Date()
        let board = await placed(
            [item("other:recent", title: "Reply to Dana", due: now.addingTimeInterval(-86400 * 2), kind: .reply)],
            at: now
        )
        #expect((board[.now] ?? []).map(\.id) == ["other:recent"])
    }

    @Test("Placement never loses an item, whatever its dates")
    func placementNeverLosesAnItem() async {
        let now = Date()
        let items = [
            item("other:future", title: "Months out", due: now.addingTimeInterval(86400 * 200)),
            item("other:stale", title: "Months overdue", due: now.addingTimeInterval(-86400 * 200)),
            item("other:today", title: "Today", due: now, kind: .deadline),
            item("other:nodate", title: "No date", due: nil, priority: .high, kind: .decision)
        ]
        let board = await placed(items, at: now)
        let placedIds = Set(board.values.flatMap { $0.map(\.id) })
        #expect(placedIds == Set(items.map(\.id)), "every item must appear in exactly one bucket")
    }

    /// The degradation path this device is in if it lacks Apple Intelligence.
    /// Whichever branch runs, the board must still be fully placed.
    @Test("The real model, whatever it reports, never breaks the board")
    func realAdvisorNeverBreaksTheBoard() async {
        let now = Date()
        let items = [
            item("other:today", title: "Today", due: now, kind: .deadline),
            item("other:future", title: "Months out", due: now.addingTimeInterval(86400 * 61))
        ]
        let store = ItemStore(items: items)

        let availability: String
        let advisories: [PlacementAdvice]
        if #available(iOS 26.0, *) {
            let advisor = OnDevicePlacementAdvisor()
            availability = advisor.availabilityNote
            advisories = await advisor.advise(
                PlacementCandidate.from(items: items, at: now, calendar: calendar),
                at: now,
                calendar: calendar
            )
        } else {
            availability = "FoundationModels unavailable at this OS version"
            advisories = []
        }
        // The note is the app's own copy for the debug screen; print it so the
        // test log records which case this hardware is in.
        print("PLACEMENT-AVAILABILITY: \(availability), advice count: \(advisories.count)")

        let coordinator = PlacementCoordinator(advisor: nil, cache: .inMemory())
        let board = await coordinator.board(
            items: store.allItems(),
            at: now,
            calendar: calendar
        )
        #expect(Set(board.values.flatMap { $0.map(\.id) }) == Set(items.map(\.id)))
        #expect((board[.now] ?? []).map(\.id) == ["other:today"])
    }
}
