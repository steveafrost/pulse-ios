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
