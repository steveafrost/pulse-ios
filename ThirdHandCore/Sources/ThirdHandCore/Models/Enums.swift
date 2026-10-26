import Foundation

// MARK: - Wire enums

//
// Every enum here uses the exact string raw values from `docs/DATA-CONTRACT.md`
// and `bb-plugin-thirdhand/types.ts`. The JSON on disk is the contract, so the raw
// values are never derived from the Swift case names.
//
// All of them decode leniently (see `LenientDecoding.swift`): an unknown string
// substitutes a documented fallback and is recorded instead of throwing, so a
// newer peer cannot make a whole snapshot unparseable.

/// Where an item came from. Derived from the id prefix on creation
/// (`"calendar:event:x"` -> `.calendar`).
public enum Source: String, Sendable, CaseIterable, Hashable, LenientWireEnum {
    case slack, gmail, calendar, github, docs, other

    /// `.other` is the contract's own catch-all bucket, so it is the fallback
    /// for a source string this build does not know.
    public static var fallback: Source {
        .other
    }
}

/// What the item asks of the user.
public enum Kind: String, Sendable, CaseIterable, Hashable, LenientWireEnum {
    case reply, decision, rsvp, conflict, deadline, review, followup, fyi

    /// `.followup` is the generic classification: it does not claim urgency the
    /// way `deadline` would, and unlike `fyi` it is not hidden under
    /// "Nice to Know", so an unknown kind stays visible where the user can see it.
    public static var fallback: Kind {
        .followup
    }
}

/// Item lifecycle. See the state machine in `docs/DATA-CONTRACT.md`.
public enum Status: String, Sendable, CaseIterable, Hashable, LenientWireEnum {
    case open, waiting, snoozed, resolved, done, dismissed

    /// `.open` never hides an item and is the only state a capture pass can
    /// safely reason about. Falling back to `.done`/`.resolved` would silently
    /// drop something the user may still need.
    public static var fallback: Status {
        .open
    }

    /// Closed items are not on the board and are pruned from the snapshot
    /// after three days. `resolved` is non-sticky; `done`/`dismissed` are
    /// only ever set by a user action.
    public var isClosed: Bool {
        switch self {
        case .resolved, .done, .dismissed: true
        case .open, .waiting, .snoozed: false
        }
    }

    /// Only a user action can produce these, and they are sticky against
    /// capture passes.
    public var isUserTerminal: Bool {
        self == .done || self == .dismissed
    }

    /// The statuses a capture pass is allowed to assert.
    public var isCapturable: Bool {
        self == .open || self == .waiting || self == .resolved
    }
}

public enum Priority: String, Sendable, CaseIterable, Hashable, LenientWireEnum {
    case high, normal, low

    /// `.normal` neither jumps the Now queue nor disappears from the board.
    public static var fallback: Priority {
        .normal
    }

    /// Ascending rank used by the board sort (high first), matching `PR` in
    /// `lib/store.mjs`.
    public var sortRank: Int {
        switch self {
        case .high: 0
        case .normal: 1
        case .low: 2
        }
    }
}

/// Status of the agent thread the user handed an item to from the Mac panel.
public enum ActionStatus: String, Sendable, CaseIterable, Hashable, LenientWireEnum {
    case running, ready, failed

    /// A status we cannot interpret is treated as `failed` so the UI stops
    /// showing a spinner that will never resolve.
    public static var fallback: ActionStatus {
        .failed
    }
}

/// The four transitions a user (or the Mac mirror forwarding a user) can assert.
/// Raw values match `ItemAction` in `types.ts` and `op` in `commands.jsonl`.
///
/// This one is *not* lenient: an unknown op is an instruction we must not
/// guess at, so it throws and the sync layer drops the command.
public enum ItemActionVerb: String, Codable, Sendable, CaseIterable, Hashable {
    case done, dismiss, snooze, reopen
}

/// The mirror-side name for the same value, so command decoding can read as
/// `MirrorOp` in the sync layer and `ItemActionVerb` in the store.
public typealias MirrorOp = ItemActionVerb
