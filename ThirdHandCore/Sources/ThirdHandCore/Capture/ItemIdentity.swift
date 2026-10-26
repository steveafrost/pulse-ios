import CryptoKit
import Foundation

/// The four id templates from `docs/DATA-CONTRACT.md` ("Capture identity"), plus
/// the parsing rules for reading a source back out of an id.
///
/// | Source | Id template |
/// | --- | --- |
/// | calendar | `calendar:event:<ekEvent.eventIdentifier>` |
/// | calendar conflict | `calendar:conflict:<YYYYMMDD>:<8-char hash of sorted participant set>` |
/// | reminders | `reminders:reminder:<calendarItemIdentifier>` |
/// | mail (share sheet) | `gmail:message:<rfc822 Message-ID>` |
/// | shared link | `<source>:link:<8-char hash of the normalised URL>` |
///
/// **Hash choice.** The conflict hash is the first 8 hex characters of
/// SHA-256 over the UTF-8 encoding of the sorted participant identifiers joined
/// with `U+001F` (unit separator). SHA-256 was chosen over FNV-1a because the id
/// is persisted, synced to the Mac plugin and compared across devices and
/// Swift standard-library versions: a stdlib-independent, collision-resistant
/// digest is worth the milliseconds, and `CryptoKit` is already available on both
/// platforms. The `U+001F` separator cannot appear in a name or an email, which
/// makes `["ab","c"]` and `["a","bc"]` hash differently.
public enum ItemIdentity {
    /// The separator between sorted participant identifiers. Not producible by a
    /// person typing a name, so the join is unambiguous.
    public static let participantSeparator: Character = "\u{1F}"

    /// How many hex characters of the digest the id carries.
    public static let conflictHashLength = 8

    /// The same width for a shared link's id.
    public static let sharedLinkHashLength = 8

    // MARK: - Builders

    /// `calendar:event:<eventIdentifier>`.
    public static func event(_ eventIdentifier: String) -> String {
        "calendar:event:\(eventIdentifier)"
    }

    /// `calendar:conflict:<YYYYMMDD>:<hash>`.
    ///
    /// `participants` is order-insensitive: the set is sorted before hashing, so
    /// the same pair named in either order yields the same id. Duplicates are
    /// collapsed (it is a *set*), and blank entries are dropped.
    public static func calendarConflict(day: Date, participants: [String], calendar: Calendar = .current) -> String {
        "calendar:conflict:\(dayStamp(day, calendar: calendar)):\(conflictHash(participants))"
    }

    /// `reminders:reminder:<calendarItemIdentifier>`.
    public static func reminder(_ identifier: String) -> String {
        "reminders:reminder:\(identifier)"
    }

    /// `gmail:message:<rfc822 Message-ID>`.
    public static func mail(messageID: String) -> String {
        "gmail:message:\(messageID)"
    }

    /// `<source>:link:<hash>` for a link the user shared into Pulse (M7.1).
    ///
    /// The URL is normalised here rather than trusted from the caller: passing a raw
    /// share would otherwise mint a different id for every `utm_` variant, which is
    /// exactly the bug this template exists to avoid. Normalisation is idempotent,
    /// so a caller that already normalised (as `SharedLinkSource` does) gets the
    /// same id.
    ///
    /// A string that is not a parseable `http(s)` URL is still hashed, trimmed and
    /// lowercased, so the function stays total; `SharedLinkSource` is where an
    /// unusable URL is turned into `nil` instead of an item.
    public static func sharedLink(source: Source, url: String) -> String {
        let canonical = normalizedSharedURL(url)
            ?? url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(source.rawValue):link:\(sharedLinkHash(canonical))"
    }

    /// The digest half of a shared-link id: SHA-256 over the normalised URL, hex,
    /// truncated to `sharedLinkHashLength`.
    ///
    /// SHA-256 for the same reason as the conflict hash: this id is persisted,
    /// synced to the Mac and compared across devices, so it must not depend on a
    /// stdlib hash seed.
    public static func sharedLinkHash(_ url: String, length: Int = sharedLinkHashLength) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(length))
    }

    /// The canonical form of a shared URL: the thing an id is hashed over.
    ///
    /// Returns `nil` when the string is not a usable `http(s)` URL, so a share of
    /// something that is not a link produces no item instead of a junk one.
    ///
    /// Normalisation, and why each part:
    ///   * scheme and host lowercased; host's leading `www.` dropped -- `https://`
    ///     and `HTTPS://`, `www.x.com` and `x.com`, are the same page.
    ///   * default ports (`:443` on https, `:80` on http) dropped.
    ///   * a fragment (`#reply-42`) dropped: it addresses a position in a page, not
    ///     a different thing, and Slack and GitHub both churn it. The one exception
    ///     is a host on `fragmentCarriesIdentityHosts`: Gmail's message permalink is
    ///     `mail.google.com/mail/u/0/#inbox/<id>`, where the fragment *is* the
    ///     message, and dropping it would collapse every mail into one item.
    ///   * tracking query parameters dropped (`utm_*`, `fbclid`, `gclid`,
    ///     `mc_cid`, `mc_eid`, `igshid`, `si`, `ref_src`). Gmail and Slack append
    ///     these on share; keeping them would make one message produce many items.
    ///   * the remaining query parameters sorted, so `?a=1&b=2` and `?b=2&a=1` are
    ///     one link.
    ///   * a trailing slash dropped, so `https://x.com/` and `https://x.com` agree;
    ///     an otherwise non-empty path is left as given, because a path *is* the
    ///     identity (`/pull/1` and `/pull/2` are different reviews).
    public static func normalizedSharedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        guard var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard !host.isEmpty else { return nil }

        components.scheme = scheme
        components.host = host
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if !fragmentCarriesIdentity(host: host) { components.fragment = nil }

        if let items = components.queryItems {
            let kept = items
                .filter { !isTrackingParameter($0.name) }
                .sorted { lhs, rhs in
                    lhs.name == rhs.name ? (lhs.value ?? "") < (rhs.value ?? "") : lhs.name < rhs.name
                }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        // A trailing slash addresses the same resource (`/pull/3/` is `/pull/3`);
        // trimming it also collapses the root path to `""`, so `https://x.com` and
        // `https://x.com/` agree.
        var path = components.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        components.path = path == "/" ? "" : path

        // `URLComponents` percent-encodes on the way out and can return nil for a
        // malformed host; treat that as "not a link" rather than hashing a guess.
        guard let string = components.string else { return nil }
        return string
    }

    /// Hosts whose URL keeps its meaning in the fragment. Deliberately a short,
    /// explicit list with a comment, not a pattern: silently keeping fragments
    /// would undo the de-duplication for every other site.
    public static let fragmentCarriesIdentityHosts: Set<String> = ["mail.google.com"]

    /// Whether `host` needs its fragment kept. Suffix match, so a Gmail tenant host
    /// (`mail.google.com`) and any future `mail.google.co.uk` style variant agree.
    public static func fragmentCarriesIdentity(host: String) -> Bool {
        fragmentCarriesIdentityHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Whether a query parameter is a tracking tag rather than part of the identity.
    ///
    /// `utm_` is a prefix family; the rest are the single parameters the large
    /// senders (Facebook, Google, Mailchimp, Instagram, Slack, Twitter) append.
    public static func isTrackingParameter(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.hasPrefix("utm_") { return true }
        return ["fbclid", "gclid", "mc_cid", "mc_eid", "igshid", "si", "ref_src", "ref_url"].contains(lowered)
    }

    // MARK: - Hash

    /// The 8-char digest of the sorted participant set. Stable across runs,
    /// processes and devices.
    public static func conflictHash(
        _ participants: [String],
        length: Int = conflictHashLength
    ) -> String {
        let canonical = canonicalParticipants(participants).joined(separator: String(participantSeparator))
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(length))
    }

    /// The participant set in canonical form: trimmed, lowercased (so "Ada@x"
    /// and "ada@x" are one participant), blank entries dropped, de-duplicated and
    /// sorted. Sorting is what makes the id order-insensitive.
    public static func canonicalParticipants(_ participants: [String]) -> [String] {
        let cleaned = participants
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0).inserted }.sorted()
    }

    // MARK: - Parsing

    /// `YYYYMMDD` in `calendar` (UTC in tests), the day half of a conflict id.
    public static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The source an id belongs to. `reminders:` maps to `.other` because
    /// `Source` has no `reminders` case and `docs/DATA-CONTRACT.md` lists the
    /// contract's set as `slack|gmail|calendar|github|docs|other`; Reminders is
    /// deliberately carried in the catch-all bucket.
    public static func source(for id: String) -> Source? {
        guard let prefix = id.split(separator: ":", maxSplits: 1).first else { return nil }
        switch prefix {
        case "reminders": return .other
        default: return Source(rawValue: String(prefix))
        }
    }

    /// `^[a-z]+:.+` -- the shape the contract requires and the store enforces.
    public static func isValid(_ id: String) -> Bool {
        DetectedItem.isValidIdentifier(id)
    }
}
