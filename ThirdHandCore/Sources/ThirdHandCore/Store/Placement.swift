import CryptoKit
import Foundation

// MARK: - Lens

/// Who placed an item in its bucket.
///
/// The board has two places a horizon can come from: the deterministic rules in
/// `HorizonDerivation`, and a judgement made on the device by the system language
/// model. Recording which one fired is not bookkeeping for its own sake -- it is
/// what lets the UI say "the model moved this" and lets a bug be attributed to
/// the rules or to the model. Without it, "why is this in Later?" has no answer.
public enum PlacementLens: String, Codable, Sendable, CaseIterable, Hashable {
    /// `HorizonDerivation` alone: dates and priority.
    case rules
    /// A judgement from the on-device model.
    case onDevice
}

// MARK: - Decision

/// One item's placement, as decided by whoever could decide it.
///
/// `signature` is the guard against staleness: it is a digest of the fields the
/// decision was made from, so a decision silently stops applying when the item
/// changes underneath it. A reminder rescheduled from today to next month must
/// not keep a "this can wait" verdict it earned while it was overdue.
public struct PlacementDecision: Codable, Sendable, Hashable {
    public var itemID: ThirdHandItem.ID
    public var horizon: Horizon
    /// Human-readable, shown on the card. Never empty.
    public var reason: String
    public var lens: PlacementLens
    public var decidedAt: Date
    public var signature: String

    public init(
        itemID: ThirdHandItem.ID,
        horizon: Horizon,
        reason: String,
        lens: PlacementLens,
        decidedAt: Date,
        signature: String
    ) {
        self.itemID = itemID
        self.horizon = horizon
        self.reason = reason
        self.lens = lens
        self.decidedAt = decidedAt
        self.signature = signature
    }
}

// MARK: - Signature

/// The cache key for a placement decision.
///
/// Only fields that can change *why* an item belongs somewhere go in. Deliberately
/// excluded: `detail`, `people`, `history`, `quickActions`, `updatedAt` and every
/// other field that churns on each capture pass without altering the item's
/// meaning. Including them would invalidate the cache on every pass and re-run the
/// model for no gain, which on a phone means battery and a stutter.
public enum PlacementSignature {
    /// Fields that can change a placement: what it is, when it is due, how urgent
    /// it claims to be, and whether it is still open.
    public static func of(_ item: ThirdHandItem, at instant: Date, calendar: Calendar = .current) -> String {
        let due: String
        if let itemDue = item.due {
            // Day resolution, not instant: an item due at 09:00 and one due at
            // 17:00 the same day are the same placement question, and capture
            // re-reads dates with second-level noise.
            let day = calendar.startOfDay(for: itemDue)
            due = String(Int(day.timeIntervalSince1970))
        } else {
            due = "undated"
        }
        let payload = [
            item.id,
            item.kind.rawValue,
            item.source.rawValue,
            item.effectiveStatus(at: instant).rawValue,
            item.priority.rawValue,
            due,
            item.title
        ].joined(separator: "\u{1F}")

        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Policy

/// Applies placement decisions on top of the deterministic rules.
///
/// The rules remain the floor: an item with no decision (or a decision that has
/// gone stale) is placed exactly as `HorizonDerivation` says. A decision only ever
/// *replaces* the bucket, never removes the item -- moving something to Later must
/// not become a way to hide it.
public enum PlacementPolicy {
    /// The board, with decisions applied.
    ///
    /// A decision whose `signature` no longer matches the item is ignored rather
    /// than trusted, and so is one for an item that is no longer on the board.
    /// Ignoring stale decisions rather than deleting them keeps the cache simple:
    /// it is swept on the next advisor run, and a transient mismatch (a pass that
    /// briefly moved a due date) does not permanently lose a judgement.
    public static func board(
        items: [ThirdHandItem],
        decisions: [ThirdHandItem.ID: PlacementDecision],
        at instant: Date,
        calendar: Calendar = .current
    ) -> [Horizon: [ThirdHandItem]] {
        var buckets: [Horizon: [ThirdHandItem]] = [:]
        for item in items {
            let horizon = horizon(
                of: item,
                decision: decisions[item.id],
                at: instant,
                calendar: calendar
            )
            guard let horizon else { continue }
            buckets[horizon, default: []].append(item)
        }
        for key in buckets.keys {
            buckets[key] = ThirdHandItemSort.sorted(buckets[key] ?? [])
        }
        return buckets
    }

    /// One item's bucket, decisions first, rules second.
    public static func horizon(
        of item: ThirdHandItem,
        decision: PlacementDecision?,
        at instant: Date,
        calendar: Calendar = .current
    ) -> Horizon? {
        // Closed items stay closed no matter what any advisor thinks: a decision
        // must never resurrect something the user finished.
        guard HorizonDerivation.isOnBoard(item, at: instant) else { return nil }

        if let decision, isFresh(decision, for: item, at: instant, calendar: calendar) {
            return decision.horizon
        }
        return HorizonDerivation.horizon(of: item, at: instant, calendar: calendar)
    }

    /// Whether a decision still describes the item it was made about.
    public static func isFresh(
        _ decision: PlacementDecision,
        for item: ThirdHandItem,
        at instant: Date,
        calendar: Calendar = .current
    ) -> Bool {
        decision.itemID == item.id
            && decision.signature == PlacementSignature.of(item, at: instant, calendar: calendar)
    }

    /// Drops decisions that no longer match their item. Cheap enough to run on
    /// every advisor pass, which is what keeps the cache from growing forever.
    public static func sweep(
        decisions: [ThirdHandItem.ID: PlacementDecision],
        items: [ThirdHandItem],
        at instant: Date,
        calendar: Calendar = .current
    ) -> [ThirdHandItem.ID: PlacementDecision] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return decisions.filter { id, decision in
            guard let item = byID[id] else { return false }
            return isFresh(decision, for: item, at: instant, calendar: calendar)
        }
    }
}

// MARK: - Candidate

/// The compact view of an item that the on-device model sees.
///
/// Built deliberately narrow. The model gets no ids it could echo back wrongly, no
/// people, no URLs and no history: everything it needs to answer "does this need
/// the user today", and nothing that would let a hallucinated field reach storage.
/// The caller re-attaches the real item by `index`, which the model cannot alter.
public struct PlacementCandidate: Sendable, Hashable {
    /// Position in the batch. The only handle the model is given.
    public var index: Int
    /// The real item this candidate stands for.
    ///
    /// Carried here so a verdict can be traced back to an item, and deliberately
    /// **never** written into the prompt: the model is given `index` and nothing
    /// else, so it cannot echo back an id it was shown and could get wrong. The
    /// mapping index -> itemID is done by us, after the fact, from data the model
    /// never touched.
    public var itemID: ThirdHandItem.ID
    public var kind: Kind
    public var title: String
    /// Days from today: negative past, 0 today, positive future, nil undated.
    public var dueInDays: Int?
    public var priority: Priority
    /// Which bucket the deterministic rules chose, so the model argues with the
    /// rules rather than starting from nothing.
    public var ruleHorizon: Horizon
    /// Why the rules chose it. Gives the model the same evidence a person would
    /// have, and keeps its answer traceable to a rule.
    public var ruleReason: String

    public init(
        index: Int,
        itemID: ThirdHandItem.ID,
        kind: Kind,
        title: String,
        dueInDays: Int?,
        priority: Priority,
        ruleHorizon: Horizon,
        ruleReason: String
    ) {
        self.index = index
        self.itemID = itemID
        self.kind = kind
        self.title = title
        self.dueInDays = dueInDays
        self.priority = priority
        self.ruleHorizon = ruleHorizon
        self.ruleReason = ruleReason
    }
}

extension PlacementCandidate {
    /// Builds the model's view of a board.
    ///
    /// Only items the rules placed in `now` or `next` are candidates: those are
    /// the two buckets where being wrong actually costs the user attention. An
    /// item already in Later or Nice to Know cannot be made less intrusive, so
    /// sending it to the model would burn an inference to learn "leave it alone".
    public static func from(
        items: [ThirdHandItem],
        at instant: Date,
        calendar: Calendar = .current
    ) -> [PlacementCandidate] {
        let today = calendar.startOfDay(for: instant)
        let candidates = items.compactMap { item -> (ThirdHandItem, Horizon)? in
            guard let horizon = HorizonDerivation.horizon(of: item, at: instant, calendar: calendar),
                  horizon == .now || horizon == .next else { return nil }
            return (item, horizon)
        }
        // Stable order so a cached decision maps to the same item next run.
        .sorted { $0.0.id < $1.0.id }

        return candidates.enumerated().map { index, pair in
            let (item, horizon) = pair
            let dueInDays = item.due.map { due -> Int in
                let dueDay = calendar.startOfDay(for: due)
                return calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
            }
            return PlacementCandidate(
                index: index,
                itemID: item.id,
                kind: item.kind,
                title: item.title,
                dueInDays: dueInDays,
                priority: item.priority,
                ruleHorizon: horizon,
                ruleReason: Self.ruleReason(for: item, at: instant, calendar: calendar, horizon: horizon)
            )
        }
    }

    /// A plain-English statement of the rule that fired. This is what the model is
    /// asked to argue with, so it has to be readable, not a raw enum case.
    static func ruleReason(
        for item: ThirdHandItem,
        at instant: Date,
        calendar: Calendar,
        horizon: Horizon
    ) -> String {
        guard let due = item.due else {
            return item.priority == .high ? "high priority, no due date" : "no due date"
        }
        let today = calendar.startOfDay(for: instant)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        switch horizon {
        case .now:
            if days < 0 {
                return "overdue by \(-days) day\(days == -1 ? "" : "s")"
            }
            return "due today"
        case .next:
            return "due in \(days) day\(days == 1 ? "" : "s")"
        default:
            return "due in \(days) days"
        }
    }
}

// MARK: - Advice

/// What an advisor is asked to do.
///
/// Kept to two verbs on purpose. "Promote" is not offered: the whole complaint is
/// that Now is full of things that do not belong, so the only useful judgement is
/// whether something in Now can wait, or whether something in Next cannot. A model
/// allowed to promote would reintroduce the noise this exists to remove.
public enum PlacementVerdict: String, Codable, Sendable, CaseIterable, Hashable {
    /// Leave the rules' answer alone.
    case keep
    /// It can wait: move it out of Now, or further down Next.
    case defer_
    /// It cannot wait: move it up.
    case promote
}

/// One advisor's answer for one item.
public struct PlacementAdvice: Sendable, Hashable {
    public var itemID: ThirdHandItem.ID
    public var horizon: Horizon
    public var reason: String

    public init(itemID: ThirdHandItem.ID, horizon: Horizon, reason: String) {
        self.itemID = itemID
        self.horizon = horizon
        self.reason = reason
    }
}

/// Anything that can second-guess the rules.
///
/// Async and throwing-free by design: an advisor that cannot answer returns an
/// empty array, and the board falls back to the rules. Placement must never be a
/// reason the board fails to draw.
public protocol PlacementAdvising: Sendable {
    /// Advice for the given candidates. An empty result means "no opinion".
    func advise(
        _ candidates: [PlacementCandidate],
        at instant: Date,
        calendar: Calendar
    ) async -> [PlacementAdvice]
}
