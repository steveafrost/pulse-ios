import Foundation
import Testing
@testable import ThirdHandCore

/// Builds items for the placement tests. Deliberately separate from `Fixture.detected`:
/// these tests need a whole `ThirdHandItem` with mutable fields, not a detection.
private func makeItem(
    id: String = "reminders:1",
    title: String = "Something",
    detail: String = "",
    due: Date? = nil,
    priority: Priority = .normal,
    status: Status = .open,
    kind: Kind = .deadline,
    source: Source = .other,
    firstSeenAt: Date = Fixture.now,
    updatedAt: Date = Fixture.now
) -> ThirdHandItem {
    ThirdHandItem(
        id: id,
        source: source,
        kind: kind,
        title: title,
        detail: detail,
        due: due,
        priority: priority,
        status: status,
        firstSeenAt: firstSeenAt,
        lastSeenAt: Fixture.now,
        updatedAt: updatedAt,
        lastChangedBy: "capture"
    )
}

// MARK: - Signature

@Suite("PlacementSignature")
struct PlacementSignatureTests {
    @Test("an irrelevant field change does not invalidate a decision")
    func stableAcrossNoise() {
        let base = makeItem(detail: "first", updatedAt: Fixture.now)
        var noisy = base
        noisy.detail = "utterly different prose"
        noisy.updatedAt = Fixture.now.addingTimeInterval(3600)

        #expect(
            PlacementSignature.of(base, at: Fixture.now, calendar: Fixture.calendar)
                == PlacementSignature.of(noisy, at: Fixture.now, calendar: Fixture.calendar)
        )
    }

    @Test("a different due day changes the signature")
    func dueMatters() {
        let a = makeItem(due: Fixture.date("2026-10-24T09:00:00Z"))
        let b = makeItem(due: Fixture.date("2026-10-25T09:00:00Z"))

        #expect(
            PlacementSignature.of(a, at: Fixture.now, calendar: Fixture.calendar)
                != PlacementSignature.of(b, at: Fixture.now, calendar: Fixture.calendar)
        )
    }

    @Test("two times on the same day share a signature")
    func sameDaySameSignature() {
        let morning = makeItem(due: Fixture.date("2026-10-24T09:00:00Z"))
        let evening = makeItem(due: Fixture.date("2026-10-24T21:00:00Z"))

        #expect(
            PlacementSignature.of(morning, at: Fixture.now, calendar: Fixture.calendar)
                == PlacementSignature.of(evening, at: Fixture.now, calendar: Fixture.calendar)
        )
    }

    @Test("priority, title and status each change the signature")
    func meaningfulFieldsMatter() {
        let base = makeItem(title: "Water the plants")
        let baseSignature = PlacementSignature.of(base, at: Fixture.now, calendar: Fixture.calendar)

        var high = base
        high.priority = .high
        var renamed = base
        renamed.title = "Water the plants twice"
        var done = base
        done.status = .done

        for variant in [high, renamed, done] {
            #expect(
                PlacementSignature.of(variant, at: Fixture.now, calendar: Fixture.calendar)
                    != baseSignature
            )
        }
    }

    @Test("undated and dated items never collide")
    func datedVersusUndated() {
        let undated = makeItem()
        let dated = makeItem(due: Fixture.now)

        #expect(
            PlacementSignature.of(undated, at: Fixture.now, calendar: Fixture.calendar)
                != PlacementSignature.of(dated, at: Fixture.now, calendar: Fixture.calendar)
        )
    }
}

// MARK: - Policy

@Suite("PlacementPolicy")
struct PlacementPolicyTests {
    private func decision(
        for item: ThirdHandItem,
        horizon: Horizon,
        reason: String = "because"
    ) -> PlacementDecision {
        PlacementDecision(
            itemID: item.id,
            horizon: horizon,
            reason: reason,
            lens: .onDevice,
            decidedAt: Fixture.now,
            signature: PlacementSignature.of(item, at: Fixture.now, calendar: Fixture.calendar)
        )
    }

    @Test("no decision means the rules decide")
    func rulesAreTheDefault() {
        // Due today, so the rules say Now.
        let item = makeItem(due: Fixture.now)
        let placed = PlacementPolicy.horizon(
            of: item,
            decision: nil,
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(placed == .now)
    }

    @Test("a fresh decision overrides the rules")
    func decisionWins() {
        let item = makeItem(due: Fixture.now)
        let placed = PlacementPolicy.horizon(
            of: item,
            decision: decision(for: item, horizon: .later),
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(placed == .later)
    }

    @Test("a stale decision is ignored and the rules win")
    func staleDecisionIgnored() {
        let original = makeItem(due: Fixture.now)
        let stale = decision(for: original, horizon: .later)

        // The reminder was rescheduled two months out. The "this can wait" verdict it
        // earned while overdue no longer describes it.
        var rescheduled = original
        rescheduled.due = Fixture.date("2026-12-25T09:00:00Z")

        let placed = PlacementPolicy.horizon(
            of: rescheduled,
            decision: stale,
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(placed == .later) // later by rule now, not by the stale decision
        #expect(
            !PlacementPolicy.isFresh(
                stale,
                for: rescheduled,
                at: Fixture.now,
                calendar: Fixture.calendar
            )
        )
    }

    @Test("a decision never resurrects a closed item")
    func closedStaysClosed() {
        let item = makeItem(due: Fixture.now, status: .done)
        let placed = PlacementPolicy.horizon(
            of: item,
            decision: decision(for: item, horizon: .now),
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(placed == nil)
    }

    @Test("the board groups by decision and keeps every open item")
    func boardGroups() {
        let nowItem = makeItem(id: "reminders:now", due: Fixture.now)
        let deferred = makeItem(id: "reminders:deferred", due: Fixture.now)
        let untouched = makeItem(id: "reminders:untouched", due: Fixture.now)
        let closed = makeItem(id: "reminders:closed", due: Fixture.now, status: .dismissed)

        let board = PlacementPolicy.board(
            items: [nowItem, deferred, untouched, closed],
            decisions: [deferred.id: decision(for: deferred, horizon: .later)],
            at: Fixture.now,
            calendar: Fixture.calendar
        )

        let nowIDs = (board[.now] ?? []).map(\.id)
        let laterIDs = (board[.later] ?? []).map(\.id)
        #expect(nowIDs.contains("reminders:now"))
        #expect(nowIDs.contains("reminders:untouched"))
        #expect(laterIDs == ["reminders:deferred"])
        // Nothing is dropped: a decision moves an item, it does not hide it.
        let all = board.values.flatMap(\.self).map(\.id)
        #expect(!all.contains("reminders:closed"))
        #expect(all.count == 3)
    }

    @Test("sweeping drops decisions whose item changed or vanished")
    func sweepDropsDeadDecisions() {
        let kept = makeItem(id: "reminders:kept", due: Fixture.now)
        let changed = makeItem(id: "reminders:changed", due: Fixture.now)

        let decisions: [ThirdHandItem.ID: PlacementDecision] = [
            kept.id: decision(for: kept, horizon: .later),
            changed.id: decision(for: changed, horizon: .later),
            "reminders:vanished": decision(for: changed, horizon: .later)
        ]

        var movedOn = changed
        movedOn.title = "Something else entirely"

        let swept = PlacementPolicy.sweep(
            decisions: decisions,
            items: [kept, movedOn],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(Set(swept.keys) == ["reminders:kept"])
    }
}

// MARK: - Cache round trip

@Suite("PlacementCache")
struct PlacementCacheTests {
    @Test("saving and loading round-trips the decisions")
    func roundTrip() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("placements-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = PlacementCache(fileURL: url)
        let item = makeItem(id: "reminders:1")
        let stored = PlacementDecision(
            itemID: item.id,
            horizon: .later,
            reason: "a chore you have ignored for months",
            lens: .onDevice,
            decidedAt: Fixture.date("2026-10-23T18:04:11Z"),
            signature: PlacementSignature.of(item, at: Fixture.now, calendar: Fixture.calendar)
        )
        cache.save([item.id: stored])

        let loaded = cache.load()
        #expect(loaded[item.id]?.horizon == .later)
        #expect(loaded[item.id]?.reason == "a chore you have ignored for months")
    }

    @Test("a missing file reads as an empty cache, never an error")
    func missingFileIsEmpty() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).json")
        #expect(PlacementCache(fileURL: url).load().isEmpty)
    }

    @Test("garbage in the file reads as an empty cache")
    func corruptFileIsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("junk-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json at all".utf8).write(to: url)
        #expect(PlacementCache(fileURL: url).load().isEmpty)
    }
}

// MARK: - Coordinator

@Suite("PlacementCoordinator")
struct PlacementCoordinatorTests {
    @Test("with no advisor the board is placed by the rules alone")
    func rulesOnlyWithoutAdvisor() async {
        let coordinator = PlacementCoordinator(advisor: nil, cache: .inMemory())
        let item = makeItem(due: Fixture.now)

        let changed = await coordinator.refresh(
            items: [item],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(changed == false)

        let board = await coordinator.board(
            items: [item],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect((board[.now] ?? []).map(\.id) == [item.id])
    }

    @Test("an advisor's advice reaches the board and is persisted")
    func adviceApplied() async {
        let item = makeItem(due: Fixture.now)
        let coordinator = PlacementCoordinator(
            advisor: StubAdvisor(advice: [PlacementAdvice(itemID: item.id, horizon: .later, reason: "can wait")]),
            cache: .inMemory()
        )

        let changed = await coordinator.refresh(
            items: [item],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect(changed)

        let board = await coordinator.board(
            items: [item],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        #expect((board[.later] ?? []).map(\.id) == [item.id])
        #expect((board[.now] ?? []).isEmpty)

        let decision = await coordinator.decision(for: item.id)
        #expect(decision?.lens == .onDevice)
        #expect(decision?.reason == "can wait")
    }

    @Test("advice about an item that is not on the board is dropped")
    func unknownItemDropped() async {
        let item = makeItem(due: Fixture.now)
        let coordinator = PlacementCoordinator(
            advisor: StubAdvisor(advice: [
                PlacementAdvice(itemID: "reminders:ghost", horizon: .later, reason: "not real")
            ]),
            cache: .inMemory()
        )

        _ = await coordinator.refresh(items: [item], at: Fixture.now, calendar: Fixture.calendar)
        let decisions = await coordinator.allDecisions()
        #expect(decisions.isEmpty)
    }

    @Test("a reset forgets every decision")
    func resetClears() async {
        let item = makeItem(due: Fixture.now)
        let coordinator = PlacementCoordinator(
            advisor: StubAdvisor(advice: [PlacementAdvice(itemID: item.id, horizon: .later, reason: "x")]),
            cache: .inMemory()
        )
        _ = await coordinator.refresh(items: [item], at: Fixture.now, calendar: Fixture.calendar)
        await coordinator.reset()
        let decisions = await coordinator.allDecisions()
        #expect(decisions.isEmpty)
    }
}

/// A advisor that answers with a fixed list, so the coordinator can be tested without
/// the system language model.
private struct StubAdvisor: PlacementAdvising {
    let advice: [PlacementAdvice]

    func advise(
        _ candidates: [PlacementCandidate],
        at instant: Date,
        calendar: Calendar
    ) async -> [PlacementAdvice] {
        advice
    }
}

// MARK: - Candidate construction

@Suite("PlacementCandidate")
struct PlacementCandidateTests {
    @Test("only Now and Next are sent to the model")
    func onlyActionableBucketsBecomeCandidates() {
        let nowItem = makeItem(id: "reminders:now", due: Fixture.now)
        let nextItem = makeItem(id: "reminders:next", due: Fixture.now.addingTimeInterval(2 * 86400))
        let laterItem = makeItem(id: "reminders:later", due: Fixture.date("2027-06-01T09:00:00Z"))
        let fyi = makeItem(id: "reminders:fyi", kind: .fyi)

        let candidates = PlacementCandidate.from(
            items: [nowItem, nextItem, laterItem, fyi],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        let ids = Set(candidates.map(\.itemID))
        #expect(ids == ["reminders:now", "reminders:next"])
    }

    @Test("dueInDays counts whole days from today")
    func dueInDays() {
        let overdue = makeItem(id: "reminders:a", due: Fixture.date("2026-10-20T09:00:00Z"))
        let today = makeItem(id: "reminders:b", due: Fixture.now)
        let candidates = PlacementCandidate.from(
            items: [overdue, today],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.itemID, $0) })
        #expect(byID["reminders:a"]?.dueInDays == -3)
        #expect(byID["reminders:b"]?.dueInDays == 0)
    }

    @Test("the candidate carries the item id but the prompt never shows it")
    func idNotLeakedIntoPrompt() {
        let item = makeItem(id: "reminders:secret-id", title: "Water the plants", due: Fixture.now)
        let candidates = PlacementCandidate.from(
            items: [item],
            at: Fixture.now,
            calendar: Fixture.calendar
        )
        let candidate = candidates.first

        #expect(candidate?.itemID == "reminders:secret-id")
        let prompt = PlacementValidation.prompt(for: candidates)
        #expect(!prompt.contains("reminders:secret-id"))
        #expect(prompt.contains("Water the plants"))
    }
}

// MARK: - Advisor validation (no model required)

@Suite("PlacementValidation")
struct AdvisorValidationTests {
    /// A batch of candidates with the given rule buckets, for exercising `sanitize`
    /// and `isReachable` without a model.
    private func candidates(_ buckets: [Horizon]) -> [PlacementCandidate] {
        buckets.enumerated().map { index, horizon in
            PlacementCandidate(
                index: index,
                itemID: "reminders:\(index)",
                kind: .deadline,
                title: "Item \(index)",
                dueInDays: 0,
                priority: .normal,
                ruleHorizon: horizon,
                ruleReason: "due today"
            )
        }
    }

    @Test("an index outside the batch is dropped")
    func outOfRangeIndex() {
        let batch = candidates([.now])
        let advice = PlacementValidation.sanitize(
            [PlacementValidation.RawVerdict(index: 7, horizon: "later", reason: "nope")],
            against: batch
        )
        #expect(advice.isEmpty)
    }

    @Test("a repeated index is only honoured once")
    func duplicateIndex() {
        let batch = candidates([.now])
        let advice = PlacementValidation.sanitize(
            [
                PlacementValidation.RawVerdict(index: 0, horizon: "later", reason: "first"),
                PlacementValidation.RawVerdict(index: 0, horizon: "next", reason: "second")
            ],
            against: batch
        )
        #expect(advice.count == 1)
        #expect(advice.first?.reason == "first")
    }

    @Test("an invented bucket is dropped")
    func unknownBucket() {
        let batch = candidates([.now])
        let advice = PlacementValidation.sanitize(
            [PlacementValidation.RawVerdict(index: 0, horizon: "someday", reason: "nope")],
            against: batch
        )
        #expect(advice.isEmpty)
    }

    @Test("the model may never file something as nice to know")
    func niceToKnowRefused() {
        let batch = candidates([.now])
        let advice = PlacementValidation.sanitize(
            [PlacementValidation.RawVerdict(index: 0, horizon: "niceToKnow", reason: "nope")],
            against: batch
        )
        #expect(advice.isEmpty)
    }

    @Test("a verdict that agrees with the rule produces no advice")
    func agreeingVerdictIsNotAdvice() {
        let batch = candidates([.now])
        let advice = PlacementValidation.sanitize(
            [PlacementValidation.RawVerdict(index: 0, horizon: "now", reason: "agrees")],
            against: batch
        )
        #expect(advice.isEmpty)
    }

    @Test("deferring is always allowed")
    func deferralAlwaysAllowed() {
        let batch = candidates([.now])
        let advice = PlacementValidation.sanitize(
            [PlacementValidation.RawVerdict(index: 0, horizon: "later", reason: "can wait")],
            against: batch
        )
        #expect(advice.first?.horizon == .later)
    }

    @Test("a one-step promotion is allowed, a two-step leap is not")
    func promotionDistanceIsBounded() {
        #expect(PlacementValidation.isReachable(.now, from: .next))
        #expect(!PlacementValidation.isReachable(.now, from: .later))

        let fromLater = candidates([.later])
        let advice = PlacementValidation.sanitize(
            [PlacementValidation.RawVerdict(index: 0, horizon: "now", reason: "urgent")],
            against: fromLater
        )
        #expect(advice.isEmpty)
    }

    @Test("an empty reason becomes a plain statement of the bucket")
    func emptyReasonGetsFallback() {
        let batch = candidates([.now])
        let advice = PlacementValidation.sanitize(
            [PlacementValidation.RawVerdict(index: 0, horizon: "later", reason: "   ")],
            against: batch
        )
        #expect(advice.first?.reason == PlacementValidation.fallbackReason(for: .later))
    }

    @Test("a runaway reason is truncated at a word boundary")
    func longReasonTruncated() {
        let long = String(repeating: "word ", count: 60)
        let bounded = PlacementValidation.bound(long, horizon: .later)
        #expect(bounded.count <= PlacementValidation.maxReasonLength + 3)
        #expect(bounded.hasSuffix("..."))
        #expect(!bounded.contains("  "))
    }

    @Test("a short reason is passed through untouched")
    func shortReasonUntouched() {
        #expect(PlacementValidation.bound("can wait", horizon: .later) == "can wait")
    }
}
