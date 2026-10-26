import Foundation

// MARK: - History

/// One entry in an item's audit trail. `change` is a free-form label or a
/// comma-joined list, exactly as `pushHistory` in `lib/store.mjs` writes it
/// (`"created"`, `"status,priority"`, `"reopened"`, `"done"`, ...).
public struct HistoryEntry: Codable, Sendable, Hashable {
    public var at: Date
    public var by: String
    public var change: String
    public var reason: String?
    public var until: Date?

    public init(at: Date, by: String, change: String, reason: String? = nil, until: Date? = nil) {
        self.at = at
        self.by = by
        self.change = change
        self.reason = reason
        self.until = until
    }

    private enum CodingKeys: String, CodingKey {
        case at, by, change, reason, until
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        by = try c.decode(String.self, forKey: .by)
        change = try c.decode(String.self, forKey: .change)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        until = try c.decodeIfPresent(Date.self, forKey: .until)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(at, forKey: .at)
        try c.encode(by, forKey: .by)
        try c.encode(change, forKey: .change)
        // The plugin writes `undefined` for absent keys, i.e. omits them.
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(until, forKey: .until)
    }
}

// MARK: - Quick actions

/// A one-click helper on a card: copy prepared text and/or open a link. It never
/// sends anything -- the user pastes and sends.
///
/// Invariants (enforced by `validateQuickActions`, mirrored in `lib/store.mjs`):
/// label 1-32 chars, `text` non-empty and at most 1500 chars, `url` https-only,
/// and at least one of `text`/`url`.
public struct QuickAction: Codable, Sendable, Hashable {
    public static let maxLabelLength = 32
    public static let maxTextLength = 1500

    public var label: String
    public var text: String?
    public var url: String?

    public init(label: String, text: String? = nil, url: String? = nil) {
        self.label = label
        self.text = text
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case label, text, url
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        url = try c.decodeIfPresent(String.self, forKey: .url)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(url, forKey: .url)
    }

    /// Throws the same errors the store raises, so a decoded payload can be
    /// checked before it is trusted.
    public func validate() throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, label.count <= Self.maxLabelLength else {
            throw ThirdHandStoreError
                .invalidQuickAction("label must be a short string (1-\(Self.maxLabelLength) chars)")
        }
        if let text {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, text.count <= Self.maxTextLength else {
                throw ThirdHandStoreError
                    .invalidQuickAction("text must be a non-empty string up to \(Self.maxTextLength) chars")
            }
        }
        if let url {
            guard url.hasPrefix("https://"), URL(string: url) != nil else {
                throw ThirdHandStoreError.invalidQuickAction("url must be an https URL")
            }
        }
        guard text != nil || url != nil else {
            throw ThirdHandStoreError.invalidQuickAction("needs text to copy, a url to open, or both")
        }
    }
}

public extension [QuickAction] {
    /// Throws when the list breaks the contract's max-3 rule or any element is
    /// malformed. Empty lists are fine.
    func validateQuickActions() throws {
        guard count <= 3 else {
            throw ThirdHandStoreError.tooManyQuickActions
        }
        for action in self {
            try action.validate()
        }
    }
}

// MARK: - Agent action thread

/// The agent thread the user handed an item to from the Mac panel. iOS never
/// authors one; it round-trips the value unchanged.
public struct ThirdHandItemAction: Codable, Sendable, Hashable {
    public var threadId: String
    public var status: ActionStatus
    public var startedAt: Date
    public var finishedAt: Date?
    public var summary: String?
    /// When the user opened the finished thread; `nil` means unread.
    public var seenAt: Date?

    public init(
        threadId: String,
        status: ActionStatus,
        startedAt: Date,
        finishedAt: Date? = nil,
        summary: String? = nil,
        seenAt: Date? = nil
    ) {
        self.threadId = threadId
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.seenAt = seenAt
    }

    private enum CodingKeys: String, CodingKey {
        case threadId, status, startedAt, finishedAt, summary, seenAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try c.decode(String.self, forKey: .threadId)
        status = try c.decode(ActionStatus.self, forKey: .status)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        seenAt = try c.decodeIfPresent(Date.self, forKey: .seenAt)
    }
}

// MARK: - ThirdHandItem

/// One thing that needs the user. Field-for-field identical to `ThirdHandItem` in
/// `bb-plugin-thirdhand/types.ts` and the table in `docs/DATA-CONTRACT.md`.
public struct ThirdHandItem: Codable, Sendable, Hashable, Identifiable {
    // `ID` is the name `Identifiable` asks for; it is two characters because it is the
    // protocol's own spelling, not a local choice we are free to lengthen.
    // swiftlint:disable:next type_name
    public typealias ID = String

    /// Hard cap on `history`; oldest entries are dropped. Matches `pushHistory`.
    public static let maxHistoryEntries = 50
    public static let maxQuickActions = 3

    /// `"<source>:<stable id>"`. Immutable.
    public var id: String
    public var source: Source
    public var kind: Kind
    /// Non-empty, one line.
    public var title: String
    /// May be empty and multi-line.
    public var detail: String
    /// https only when present.
    public var url: String?
    public var due: Date?
    public var priority: Priority
    public var people: [String]
    public var status: Status
    /// Set only while `snoozed`.
    public var snoozedUntil: Date?
    /// Free-text reason recorded on close.
    public var resolution: String?
    /// Set once, on creation.
    public var firstSeenAt: Date
    /// Bumped by every capture pass that still finds the item.
    public var lastSeenAt: Date
    /// Any mutation.
    public var updatedAt: Date
    public var resolvedAt: Date?
    /// `"user"`, `"capture"`, `"mirror"`, or a run name.
    public var lastChangedBy: String
    public var history: [HistoryEntry]
    public var quickActions: [QuickAction]
    /// Plugin-computed. iOS writes `[]`.
    public var agentSkills: [String]?
    /// Mac-side agent thread. iOS round-trips unchanged.
    public var action: ThirdHandItemAction?

    public init(
        id: String,
        source: Source,
        kind: Kind,
        title: String,
        detail: String = "",
        url: String? = nil,
        due: Date? = nil,
        priority: Priority = .normal,
        people: [String] = [],
        status: Status = .open,
        snoozedUntil: Date? = nil,
        resolution: String? = nil,
        firstSeenAt: Date,
        lastSeenAt: Date,
        updatedAt: Date,
        resolvedAt: Date? = nil,
        lastChangedBy: String,
        history: [HistoryEntry] = [],
        quickActions: [QuickAction] = [],
        agentSkills: [String]? = nil,
        action: ThirdHandItemAction? = nil
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
        self.snoozedUntil = snoozedUntil
        self.resolution = resolution
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.lastChangedBy = lastChangedBy
        self.history = history
        self.quickActions = quickActions
        self.agentSkills = agentSkills
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, kind, title, detail, url, due, priority, people, status
        case snoozedUntil, resolution, firstSeenAt, lastSeenAt, updatedAt, resolvedAt
        case lastChangedBy, history, quickActions, agentSkills, action
    }

    /// Hand-written so `history` / `quickActions` can be absent (the Node store
    /// omits them when empty) and so `agentSkills` / `action` stay truly optional
    /// rather than required keys.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(Source.self, forKey: .source)
        kind = try c.decode(Kind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal
        people = try c.decodeIfPresent([String].self, forKey: .people) ?? []
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .open
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution)
        firstSeenAt = try c.decode(Date.self, forKey: .firstSeenAt)
        lastSeenAt = try c.decode(Date.self, forKey: .lastSeenAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        lastChangedBy = try c.decode(String.self, forKey: .lastChangedBy)
        history = try c.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        quickActions = try c.decodeIfPresent([QuickAction].self, forKey: .quickActions) ?? []
        agentSkills = try c.decodeIfPresent([String].self, forKey: .agentSkills)
        action = try c.decodeIfPresent(ThirdHandItemAction.self, forKey: .action)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source, forKey: .source)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(detail, forKey: .detail)
        try c.encode(url, forKey: .url)
        try c.encode(due, forKey: .due)
        try c.encode(priority, forKey: .priority)
        try c.encode(people, forKey: .people)
        try c.encode(status, forKey: .status)
        try c.encode(snoozedUntil, forKey: .snoozedUntil)
        try c.encode(resolution, forKey: .resolution)
        try c.encode(firstSeenAt, forKey: .firstSeenAt)
        try c.encode(lastSeenAt, forKey: .lastSeenAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(resolvedAt, forKey: .resolvedAt)
        try c.encode(lastChangedBy, forKey: .lastChangedBy)
        try c.encode(history, forKey: .history)
        try c.encode(quickActions, forKey: .quickActions)
        try c.encodeIfPresent(agentSkills, forKey: .agentSkills)
        try c.encodeIfPresent(action, forKey: .action)
    }
}

// MARK: - Derived helpers

public extension ThirdHandItem {
    /// The item's status right now, with an expired snooze reading as `open`.
    /// Pure -- the caller supplies the instant. See `ItemStore.effectiveStatus`.
    func effectiveStatus(at instant: Date) -> Status {
        ThirdHandItem.effectiveStatus(status: status, snoozedUntil: snoozedUntil, at: instant)
    }

    /// The shared rule from `effectiveStatus` in `lib/store.mjs`: a snooze whose
    /// `snoozedUntil` is at or before `instant` is no longer a snooze.
    static func effectiveStatus(status: Status, snoozedUntil: Date?, at instant: Date) -> Status {
        if status == .snoozed, let snoozedUntil, snoozedUntil <= instant {
            return .open
        }
        return status
    }

    /// Whether the user has locked this item's status against a capture pass
    /// (`userLocked` in `lib/store.mjs`): `done`/`dismissed`, or a snooze that
    /// has not expired yet.
    func isUserLocked(at instant: Date) -> Bool {
        status.isUserTerminal || (status == .snoozed && effectiveStatus(at: instant) == .snoozed)
    }

    /// Status of the agent thread, if the mirror started one.
    var actionStatus: ActionStatus? {
        action?.status
    }
}
