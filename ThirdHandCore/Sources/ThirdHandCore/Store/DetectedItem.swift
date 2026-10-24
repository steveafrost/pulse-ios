import Foundation

/// What a capture source hands to the store.
///
/// Deliberately *not* a `ThirdHandItem`: a detector knows what it saw, not the item's
/// identity over time (first seen, history, sticky status). The store owns those.
/// Every field except `id` is optional, and `nil` means "the detector has no
/// opinion" -- exactly how a sparse object behaves in `upsert` in `lib/store.mjs`,
/// where `if (it[k] === undefined) continue`.
public struct DetectedItem: Sendable, Hashable {
    /// `"<source>:<stable id>"`. The prefix determines `source` when it is not given.
    public var id: String
    public var source: Source?
    public var kind: Kind?
    public var title: String?
    public var detail: String?
    public var url: String?
    public var due: Date?
    public var priority: Priority?
    public var people: [String]?
    /// A capture pass may assert only `open`, `waiting` or `resolved`.
    public var status: Status?
    public var quickActions: [QuickAction]?
    /// Ask the store to override a sticky state. Requires `reason`.
    public var reopen: Bool
    /// Human-readable why -- recorded in history, and the `resolution` on close.
    public var reason: String?

    public init(
        id: String,
        source: Source? = nil,
        kind: Kind? = nil,
        title: String? = nil,
        detail: String? = nil,
        url: String? = nil,
        due: Date? = nil,
        priority: Priority? = nil,
        people: [String]? = nil,
        status: Status? = nil,
        quickActions: [QuickAction]? = nil,
        reopen: Bool = false,
        reason: String? = nil
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.title = title
        self.detail = detail
        self.url = url
        self.due = due
        self.priority = priority
        self.people = people
        self.status = status
        self.quickActions = quickActions
        self.reopen = reopen
        self.reason = reason
    }

    /// The source implied by the id prefix (`"calendar:event:x"` -> `.calendar`),
    /// falling back to `.other` for an unknown prefix. Mirrors
    /// `SOURCES.includes(source) ? source : "other"` in `lib/store.mjs`.
    public static func source(fromIdentifier id: String) -> Source {
        guard let prefix = id.split(separator: ":", maxSplits: 1).first else { return .other }
        return Source(rawValue: String(prefix)) ?? .other
    }

    /// Whether `id` looks like `"<lowercase source prefix>:<something>"`.
    public static func isValidIdentifier(_ id: String) -> Bool {
        guard let colon = id.firstIndex(of: ":") else { return false }
        let prefix = id[id.startIndex..<colon]
        return !prefix.isEmpty
            && prefix.allSatisfy { $0.isASCII && $0.isLowercase }
            && id.index(after: colon) < id.endIndex
    }
}
