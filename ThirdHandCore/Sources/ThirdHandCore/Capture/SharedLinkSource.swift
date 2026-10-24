import Foundation

/// Where a shared link points, as far as the board is concerned.
///
/// A pure classification of the URL, so the identity and kind rules can be tested
/// without the share sheet. `SharedLinkTarget` is *not* a wire type: nothing
/// persists it, and a host we have never seen becomes `.other` rather than an
/// error.
public enum SharedLinkTarget: String, Sendable, CaseIterable, Hashable {
    /// A Slack permalink: `<workspace>.slack.com/...` or `app.slack.com/...`.
    case slack
    /// A GitHub pull request permalink (`/pull/<n>` or `/pulls/<n>`).
    case githubPullRequest
    /// Any other GitHub URL -- an issue, a repo, a gist.
    case githubOther
    /// A Gmail message permalink (`mail.google.com/mail/...#inbox/<id>`).
    case mail
    /// Any other https link.
    case other

    /// The `Source` a target's items carry, matching `ItemIdentity.source(for:)`
    /// for the same id prefix.
    public var source: Source {
        switch self {
        case .slack: .slack
        case .githubPullRequest, .githubOther: .github
        case .mail: .gmail
        case .other: .other
        }
    }
}

/// The shared-link detector: what the user shared, classified by host.
///
/// Same split as `EventKitSource` and `RemindersSource` -- no rules in `detect`,
/// only mapping, with every heuristic a pure static function. The URL parsing and
/// kind rules are unit-tested against plain arrays of `SharedLinkSnapshot`.
///
/// **This source can only ever be as complete as what the user shared.** That is
/// the point: Slack, Gmail and GitHub have no OAuth app for Third Hand, so a real
/// pull-from-the-API source would have no way to authenticate and would silently
/// return nothing. See `docs/DEFERRED-SOURCES.md`.
public struct SharedLinkSource: CaptureSource {
    /// `Source` is per item here, not per source: one share sheet feeds Slack,
    /// GitHub and mail. `.other` is reported for the source as a whole, and each
    /// item's own `source` (from its id prefix) wins in the engine's counts.
    public let sourceID: Source = .other

    private let provider: any SharedLinkProviding
    private let calendar: Calendar

    public init(provider: any SharedLinkProviding, calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
    }

    public func detect(now: Date, window: DateInterval) async throws -> [DetectedItem] {
        // A synchronous file read; wrapped in `throws` so an unreadable container is
        // reported as a source failure rather than an empty board.
        let links = try provider.sharedLinks()
        return Self.detect(links: links, now: now)
    }

    /// Every shared-link item, de-duplicated by id (last wins, so a re-share with a
    /// better title replaces the earlier one) and sorted by id for a diffable pass.
    public static func detect(links: [SharedLinkSnapshot], now: Date) -> [DetectedItem] {
        var byID: [String: DetectedItem] = [:]
        for link in links {
            guard let item = item(for: link) else { continue }
            byID[item.id] = item
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    /// One share to one item, or `nil` when the URL is not a link we can act on.
    public static func item(for link: SharedLinkSnapshot) -> DetectedItem? {
        guard let url = ItemIdentity.normalizedSharedURL(link.url) else { return nil }
        let target = self.target(for: url)
        guard let (kind, priority) = Classifier.classifySharedLink(
            target: target,
            text: link.text
        ) else { return nil }

        return DetectedItem(
            id: ItemIdentity.sharedLink(source: target.source, url: url),
            source: target.source,
            kind: kind,
            title: title(for: link, url: url, target: target),
            detail: detail(for: link),
            url: url,
            // The share instant, not the message's: it is the only time Third Hand can
            // honestly claim to know, and the board's Horizon uses `due` for
            // "when does this need me". A shared link is never urgent, so `due`
            // stays nil and the item lands in Next/Later by kind.
            due: nil,
            priority: priority,
            quickActions: [QuickAction(label: "Open", url: url)],
            reason: "shared from \(target.source.rawValue)"
        )
    }

    // MARK: - Host rules

    /// Which source a normalised URL belongs to. Host suffix matching, because a
    /// Slack workspace is a tenant (`acme.slack.com`).
    public static func target(for url: String) -> SharedLinkTarget {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else {
            return .other
        }
        let path = components.path.lowercased()

        if host == "slack.com" || host.hasSuffix(".slack.com") || host == "app.slack.com" {
            return .slack
        }
        if host == "github.com" || host.hasSuffix(".github.com") {
            // `/pull/12`, and the Enterprise/compare shape `/owner/repo/pull/12`.
            let segments = path.split(separator: "/").map(String.init)
            if segments.contains("pull") || segments.contains("pulls") { return .githubPullRequest }
            return .githubOther
        }
        if host == "mail.google.com" {
            return .mail
        }
        return .other
    }

    // MARK: - Text

    /// What the card is called.
    ///
    /// The share sheet's title wins when it has one -- a Gmail subject or a PR title
    /// is a far better sentence than the URL. Otherwise the first line of the shared
    /// text, then the last path component, then the host. Never empty: a card with
    /// no title is useless on the board.
    public static func title(for link: SharedLinkSnapshot, url: String, target: SharedLinkTarget) -> String {
        if let title = clean(link.title) { return title }
        if let text = clean(link.text) {
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(trimmed.prefix(140)) }
        }
        guard let components = URLComponents(string: url) else { return url }
        let last = components.path.split(separator: "/").last.map(String.init)
        let subject = last ?? components.host ?? url
        return "\(target.source.rawValue.capitalized): \(subject)"
    }

    /// The shared text, kept whole (a Slack thread quote is the useful part) and
    /// capped so one long message cannot bloat a snapshot.
    public static func detail(for link: SharedLinkSnapshot) -> String? {
        clean(link.text).map { String($0.prefix(1_000)) }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
