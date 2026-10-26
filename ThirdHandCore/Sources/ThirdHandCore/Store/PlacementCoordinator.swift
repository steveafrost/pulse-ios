import Foundation

/// Assembles the board: deterministic rules first, on-device judgement second.
///
/// **Why this exists as an actor.** Placement is the one place that touches three
/// pieces of mutable state at once -- the cached decisions, the advisor (which is
/// slow enough to be worth not repeating) and the current pass's items. Putting it
/// behind an actor means two concurrent board reads cannot interleave a cache write
/// with a cache read and see a half-updated set of decisions.
///
/// **Why the rules run first and always.** The advisor is asked to disagree with a
/// finished answer, not to produce one. If the model is absent, still downloading,
/// turned off, or simply fails, the board is still placed correctly by dates and
/// priority -- the caller never waits on an opinion to draw a board.
public actor PlacementCoordinator {
    private let advisor: PlacementAdvising?
    private let cache: PlacementCache
    private var decisions: [ThirdHandItem.ID: PlacementDecision]

    /// `advisor` is optional on purpose: on an OS without the system language model
    /// the app still builds a coordinator and gets rules-only placement, rather than
    /// having a second code path at every call site.
    public init(advisor: PlacementAdvising?, cache: PlacementCache = .appGroup()) {
        self.advisor = advisor
        self.cache = cache
        self.decisions = cache.load()
    }

    /// The board right now: cached decisions applied over the rules.
    ///
    /// Deliberately synchronous with respect to the advisor -- this is what the UI
    /// draws on first paint, so it must not wait for a model. Call `refresh` to ask
    /// for new judgements and redraw afterwards.
    public func board(
        items: [ThirdHandItem],
        at instant: Date,
        calendar: Calendar = .current
    ) -> [Horizon: [ThirdHandItem]] {
        PlacementPolicy.board(
            items: items,
            decisions: decisions,
            at: instant,
            calendar: calendar
        )
    }

    /// Asks the advisor to reconsider, then persists what it said.
    ///
    /// Returns whether anything changed, so the caller can skip a redraw when the
    /// model agreed with the rules -- which is the normal case, and redrawing on it
    /// would make the board flicker for no reason.
    ///
    /// Stale decisions are swept first. That is what keeps the cache small: a
    /// decision stops applying the moment its item changes underneath it, and the
    /// next pass drops it instead of piling up dead entries forever.
    @discardableResult
    public func refresh(
        items: [ThirdHandItem],
        at instant: Date,
        calendar: Calendar = .current
    ) async -> Bool {
        let before = decisions
        var swept = PlacementPolicy.sweep(decisions: decisions, items: items, at: instant, calendar: calendar)

        guard let advisor else {
            if swept.count != decisions.count {
                decisions = swept
                cache.save(swept)
            }
            return swept != before
        }

        let candidates = PlacementCandidate.from(items: items, at: instant, calendar: calendar)
        guard !candidates.isEmpty else {
            if swept.count != decisions.count {
                decisions = swept
                cache.save(swept)
            }
            return swept != before
        }

        let advice = await advisor.advise(candidates, at: instant, calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        for suggestion in advice {
            // Recommendation against an item that vanished mid-pass is dropped: the
            // model answered about a board that no longer exists.
            guard let item = byID[suggestion.itemID] else { continue }
            swept[suggestion.itemID] = PlacementDecision(
                itemID: suggestion.itemID,
                horizon: suggestion.horizon,
                reason: suggestion.reason,
                lens: .onDevice,
                decidedAt: instant,
                signature: PlacementSignature.of(item, at: instant, calendar: calendar)
            )
        }

        decisions = swept
        cache.save(swept)
        return swept != before
    }

    /// The stored decision for one item, for a detail screen that wants to explain
    /// why the item sits where it does.
    public func decision(for id: ThirdHandItem.ID) -> PlacementDecision? {
        decisions[id]
    }

    /// Every decision at once, for a caller building a reason map across a board.
    /// A single actor hop instead of one per item.
    public func allDecisions() -> [ThirdHandItem.ID: PlacementDecision] {
        decisions
    }

    /// Forgets everything. Used by the debug screen so a bad set of judgements can be
    /// cleared without deleting the app.
    public func reset() {
        decisions = [:]
        cache.save([:])
    }
}
