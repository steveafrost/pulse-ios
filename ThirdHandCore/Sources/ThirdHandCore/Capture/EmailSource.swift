import Foundation

/// The mail detector: unread IMAP messages, classified.
///
/// Same shape as `EventKitSource` and `RemindersSource` -- no classification here,
/// only fetching plus delegation to `EmailClassifier` and the pure `Self.detect`
/// overload. The one structural difference is that credentials come from two places:
/// the account from `EmailAccountProviding` (non-secret) and the password from
/// `SecretStoring` (Keychain), fetched at detect time and held only in a
/// `EmailCredentials` that dies with the call.
///
/// **This source refuses to be silently empty.** `detect` never returns `[]` as a
/// stand-in for a problem:
///
/// | Situation | Result |
/// | --- | --- |
/// | no mailbox configured | `CaptureError.denied(.gmail)` -- the "connect a mailbox" screen |
/// | secret missing from the Keychain | `CaptureError.denied(.gmail)` |
/// | `LOGIN` refused | `CaptureError.denied(.gmail)` |
/// | socket/TLS/DNS failure | `CaptureError.underlying` -- a failed pass, try again |
/// | malformed server response | `CaptureError.underlying` |
/// | genuinely no unread mail | `[]`, and the source is healthy |
///
/// `denied` (rather than a new case) is the honest mapping: "Pulse has no mail
/// access" is the same paused-source state Calendar shows when permission is off, and
/// `CaptureReport.pausedSources` already surfaces it.
public struct EmailSource: CaptureSource {
    /// Email is carried as `.gmail` because that is the raw value the contract
    /// reserves for mail and the prefix `ItemIdentity.mail` builds. A user on a
    /// non-Google IMAP host still gets `.gmail` items -- the alternative would be a
    /// new `Source` case, i.e. a contract change, and this milestone keeps
    /// `schemaVersion` at 1.
    public let sourceID: Source = .gmail

    private let transport: any IMAPTransport
    private let accounts: any EmailAccountProviding
    private let secrets: any SecretStoring
    private let limit: Int

    public init(
        transport: any IMAPTransport,
        accounts: any EmailAccountProviding,
        secrets: any SecretStoring,
        limit: Int = IMAPClient.defaultLimit
    ) {
        self.transport = transport
        self.accounts = accounts
        self.secrets = secrets
        self.limit = limit
    }

    public func detect(now: Date, window: DateInterval) async throws -> [DetectedItem] {
        let configured: EmailAccount?
        do {
            configured = try accounts.configuredAccount()
        } catch {
            throw CaptureError.underlying("mail account settings are unreadable: \(error.localizedDescription)")
        }
        guard let account = configured else {
            // Not configured is a *paused* source with a fix ("connect a mailbox"),
            // which is exactly the `denied` screen. Returning [] here would be the
            // silently-blind board.
            throw CaptureError.denied(.gmail)
        }

        let secret: String?
        do {
            secret = try secrets.secret(for: account.keychainAccount)
        } catch {
            // A Keychain that cannot be read is indistinguishable, from the board's
            // point of view, from a password that is not there: the user has to
            // reconnect either way.
            throw CaptureError.denied(.gmail)
        }
        guard let password = secret, !password.isEmpty else {
            throw CaptureError.denied(.gmail)
        }

        let client = IMAPClient(
            transport: transport,
            account: account,
            credentials: EmailCredentials(account: account, password: password),
            limit: limit
        )

        let messages: [EmailMessageSnapshot]
        do {
            messages = try await client.unreadMessages()
        } catch let error as IMAPError {
            throw Self.captureError(for: error)
        } catch let error as CaptureError {
            throw error
        } catch {
            throw CaptureError.underlying("mail fetch failed: \(error.localizedDescription)")
        }

        return Self.detect(messages: messages, account: account, now: now)
    }

    /// `LOGIN` refused and a missing credential are the same user-facing state, so
    /// both become `denied`; everything else is a real failure with a retry story.
    public static func captureError(for error: IMAPError) -> CaptureError {
        switch error {
        case .authenticationFailed:
            .denied(.gmail)
        case .connectionFailed, .commandFailed, .unexpectedResponse, .connectionClosed, .invalidCredential:
            .underlying(error.description)
        }
    }

    // MARK: - Rules

    /// Every unread message as an item, de-duplicated by id (last wins, so a re-fetch
    /// of the same mail replaces rather than duplicates) and sorted by id so a pass is
    /// diffable.
    ///
    /// `window` is not consulted: `SEARCH UNSEEN` has no window, and an unread message
    /// from three weeks ago still wants the user. `now` is used only to decide whether
    /// a message is old enough to say so in its `reason`.
    public static func detect(
        messages: [EmailMessageSnapshot],
        account: EmailAccount,
        now: Date
    ) -> [DetectedItem] {
        var byID: [String: DetectedItem] = [:]
        // Input order is the server's ascending uid order, so "last wins" means the
        // newest copy of a duplicated Message-ID is the one that survives.
        for message in messages {
            let item = item(for: message, account: account, now: now)
            byID[item.id] = item
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    /// One message to one item. Never `nil`: every unread message becomes something,
    /// even one with no usable headers.
    public static func item(
        for message: EmailMessageSnapshot,
        account: EmailAccount,
        now: Date
    ) -> DetectedItem {
        let subject = message.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = subject.isEmpty ? fallbackTitle(for: message) : subject
        let classification = EmailClassifier.classify(
            subject: subject,
            detail: nil,
            recipients: message.recipients,
            userAddress: account.normalizedUsername,
            isReply: message.isReply
        )

        let sender = message.primarySender?.description
        let detail = detailText(for: message, now: now)

        return DetectedItem(
            id: identifier(for: message, account: account),
            source: .gmail,
            kind: classification.kind,
            title: String(title.prefix(200)),
            detail: detail,
            // No URL: an IMAP message has no https permalink without provider-specific
            // URL construction, and inventing a `gmail.com` link for a non-Google host
            // would be a lie. The card's action is "open your mail app", which is a
            // UI concern left to the design pass.
            url: nil,
            due: nil,
            priority: classification.priority,
            people: sender.map { [$0] } ?? [],
            reason: classification.reason
        )
    }

    /// `gmail:message:<Message-ID>`, falling back to a uid-derived id.
    ///
    /// **The fallback is what makes identity stable for a message with no
    /// `Message-ID`.** A missing id is not rare: some mailers omit it, and a draft
    /// always has none. `uid:<n>` is stable for as long as the message is in the
    /// mailbox, which is all an unread-message item needs -- "unread in the inbox" is
    /// the item's lifetime by definition, and a uid is assigned once per mailbox and
    /// never reused within it.
    ///
    /// The account is *not* part of the id: two mailboxes delivering the same
    /// `Message-ID` (a mailing list sent to both) are the same message, and the board
    /// should hold one card for it.
    public static func identifier(for message: EmailMessageSnapshot, account: EmailAccount) -> String {
        // Normalised exactly as `IMAPParser` normalises it, so a snapshot built from
        // an untrimmed fixture and one built from the wire agree on the id.
        if let messageID = message.messageID.flatMap(IMAPParser.normalizeMessageID) {
            return ItemIdentity.mail(messageID: messageID)
        }
        return ItemIdentity.mail(messageID: "uid:\(message.uid)")
    }

    /// "Unread mail from Ada Lovelace" -- a card with no subject still has to say
    /// something, and the sender is the only honest fact available.
    static func fallbackTitle(for message: EmailMessageSnapshot) -> String {
        if let sender = message.primarySender?.description {
            return "Message from \(sender)"
        }
        return "Unread message"
    }

    /// The card's second line: who sent it, when, and who else was on it.
    ///
    /// Built from headers only. It never quotes a body, because no body is fetched --
    /// see `EmailMessageSnapshot`.
    static func detailText(for message: EmailMessageSnapshot, now: Date) -> String {
        var parts: [String] = []
        if let sender = message.primarySender?.description {
            parts.append("From \(sender)")
        }
        if let sent = message.effectiveDate {
            parts.append(Self.phrase(for: sent, now: now))
        }
        let others = message.recipients.dropFirst()
        if !others.isEmpty {
            let names = others.map(\.description).joined(separator: ", ")
            parts.append("also to \(names)")
        }
        if message.isReply {
            parts.append("already a reply")
        }
        return parts.joined(separator: " · ")
    }

    /// A coarse, timezone-free age: "today", "yesterday", "3 days ago", "2 weeks
    /// ago". Deliberately not a formatted date -- the board shows relative ages
    /// everywhere else, and a locale-formatted date in a detail line would be the one
    /// place that needs a `DateFormatter` per render.
    static func phrase(for date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 {
            return "just now"
        }
        if seconds < 24 * 3600 {
            return "today"
        }
        let days = Int(seconds / (24 * 3600))
        if days == 1 {
            return "yesterday"
        }
        if days < 14 {
            return "\(days) days ago"
        }
        let weeks = days / 7
        return weeks < 9 ? "\(weeks) weeks ago" : "\(days) days ago"
    }
}
