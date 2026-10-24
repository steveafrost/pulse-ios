import Foundation

/// One IMAP mailbox the user has connected, as plain values.
///
/// **There is deliberately no password field.** The app-specific password lives in
/// the Keychain (`KeychainSecretStore`, key `EmailAccount.keychainAccount`) and is
/// fetched only at the moment a connection is opened, so it can never be encoded
/// into a snapshot, written to the app group, synced to the Mac, or logged as part
/// of an account value. `EmailCredentials` is the one type that carries a password,
/// and it is neither `Codable` nor printable in the clear.
///
/// Everything here is the *non-secret* half of a connection: host, port, username.
/// Gmail's IMAP endpoint is `imap.gmail.com:993`; any other provider that speaks
/// IMAP over TLS with a password works the same way, which is why this is modelled
/// as an arbitrary account rather than a Gmail-specific type.
public struct EmailAccount: Sendable, Hashable, Codable {
    /// The IANA-assigned IMAPS port. TLS from the first byte; there is no
    /// plaintext-then-STARTTLS path in this client, so a server that only offers
    /// STARTTLS is not supported (see `docs/DEFERRED-SOURCES.md`).
    public static let defaultIMAPPort = 993

    /// The mailbox `SELECT`ed for capture. Only the inbox is read in v1.2.
    public static let defaultMailbox = "INBOX"

    public var host: String
    public var port: Int
    /// The full email address, which IMAP's `LOGIN` takes as the user name and which
    /// the classifier uses to decide whether the user is a recipient.
    public var username: String
    public var mailbox: String

    public init(
        host: String,
        port: Int = EmailAccount.defaultIMAPPort,
        username: String,
        mailbox: String = EmailAccount.defaultMailbox
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.mailbox = mailbox
    }

    /// A mail provider whose IMAP endpoint is known, so the screen can fill the host
    /// in rather than asking the user to look it up.
    ///
    /// Every entry here is reachable with plain `LOGIN` over implicit TLS, which is
    /// the only authentication this client implements. That was measured, not assumed:
    /// a `LOGIN` with a deliberately wrong password returns `NO [AUTHENTICATIONFAILED]`
    /// from both endpoints -- a rejected credential, not an unsupported command. A
    /// provider that advertised only `AUTH=OAUTH2` would need a different client.
    public enum Provider: String, CaseIterable, Sendable, Hashable, Codable {
        case icloud
        case gmail
        case outlook
        case yahoo
        case fastmail
        /// Anything else: the user supplies the host.
        case other

        public var displayName: String {
            switch self {
            case .icloud: "iCloud"
            case .gmail: "Gmail"
            case .outlook: "Outlook"
            case .yahoo: "Yahoo"
            case .fastmail: "Fastmail"
            case .other: "Other"
            }
        }

        /// The IMAPS host, or `nil` for `.other`.
        public var imapHost: String? {
            switch self {
            case .icloud: "imap.mail.me.com"
            case .gmail: "imap.gmail.com"
            case .outlook: "outlook.office365.com"
            case .yahoo: "imap.mail.yahoo.com"
            case .fastmail: "imap.fastmail.com"
            case .other: nil
            }
        }

        /// What the user has to do to get a password, in the provider's own terms.
        ///
        /// This is the single most common failure point, and "app-specific password"
        /// is Gmail's phrase, not iCloud's -- iCloud calls it an app password and
        /// creates it at appleid.apple.com, where the account's normal password will
        /// simply be rejected.
        public var passwordGuidance: String {
            switch self {
            case .icloud:
                "Use an app password, not your Apple Account password: appleid.apple.com → Sign-In and Security → App-Specific Passwords."
            case .gmail:
                "Use an app-specific password: myaccount.google.com → Security → 2-Step Verification → App passwords."
            case .outlook:
                "Use an app password if your account has two-step verification on. Microsoft has retired basic auth for many accounts, so this may not be available."
            case .yahoo:
                "Generate an app password: account.yahoo.com → Account Security."
            case .fastmail:
                "Use an app password: app.fastmail.com → Settings → Privacy & Security → App passwords. Your normal password may also work."
            case .other:
                "Your provider's IMAP password. If two-step verification is on, this is usually an app-specific password."
            }
        }

        /// The provider that owns a host, for showing the right guidance once a host
        /// has been typed rather than picked.
        public static func matching(host: String) -> Provider? {
            let needle = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return nil }
            return allCases.first { $0 != .other && $0.imapHost?.lowercased() == needle }
        }
    }

    /// A Gmail account using an app-specific password.
    public static func gmail(username: String) -> EmailAccount {
        EmailAccount(host: "imap.gmail.com", username: username)
    }

    /// An iCloud Mail account ("Apple Mail") using an app-specific password.
    public static func icloud(username: String) -> EmailAccount {
        EmailAccount(host: "imap.mail.me.com", username: username)
    }

    /// An account for a known provider, or `nil` for `.other` / an unknown host.
    public static func make(provider: Provider, username: String) -> EmailAccount? {
        guard let host = provider.imapHost else { return nil }
        return EmailAccount(host: host, username: username)
    }

    /// The Keychain account key this mailbox's password is stored under.
    ///
    /// Derived from the non-secret half only, and stable across launches, so a
    /// second configuration of the same mailbox finds the same secret. Lowercased
    /// because addresses and hostnames are case-insensitive and a user who typed
    /// `Host` in one build and `host` in the next must not lose their password.
    public var keychainAccount: String {
        "imap:\(username.lowercased())@\(host.lowercased()):\(port)"
    }

    /// The user's own address, normalised for recipient matching.
    public var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case host, port, username, mailbox
    }
}

// MARK: - Printing

extension EmailAccount: CustomStringConvertible, CustomDebugStringConvertible {
    /// Host, port and username only. There is no password in this type to leak, and
    /// this description is what appears in a log line or an error message.
    public var description: String {
        "\(username) at \(host):\(port)"
    }

    public var debugDescription: String {
        "EmailAccount(host: \(host), port: \(port), username: \(username), mailbox: \(mailbox))"
    }
}

/// The one type that holds a password, and the reason it can never be printed.
///
/// `EmailCredentials` exists so the password's journey is visible in the type
/// system: `EmailSource` reads it from the Keychain, wraps it here, hands it to an
/// `IMAPTransport` for exactly one `LOGIN`, and the value dies with the call.
/// `description` and `debugDescription` are both redacted, and there is no `Codable`
/// conformance, so `String(describing:)`, `dump`, `print` and `JSONEncoder` are safe
/// by construction. (A Swift `String` cannot be marked non-inspectable, so this is
/// the strongest guarantee available without a separate storage type: do not add
/// `Codable`, `Hashable` or an accessor that returns the secret under a printable
/// name.)
public struct EmailCredentials: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// What a redacted description prints instead of the secret.
    public static let redaction = "<redacted>"

    public let account: EmailAccount
    /// The app-specific password. Deliberately not `Codable`, `Hashable` or
    /// `Equatable`: the less machinery that can copy or serialise it, the better.
    public let password: String

    public init(account: EmailAccount, password: String) {
        self.account = account
        self.password = password
    }

    public var description: String {
        "EmailCredentials(\(account.description), password: \(Self.redaction))"
    }

    public var debugDescription: String { description }

    /// `description` alone is not enough to keep this type out of a log.
    ///
    /// `dump(_:)` reflects a value's *stored properties*, so it would print
    /// `password: "..."` no matter what `description` says -- and `dump` is exactly
    /// what gets pasted into a bug report. Overriding the mirror makes redaction hold
    /// for `String(reflecting:)`, `dump`, and any debugger view built on `Mirror`.
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "account": String(describing: account),
                "password": Self.redaction,
            ],
            displayStyle: .struct
        )
    }
}

// MARK: - Addresses

/// One mail address, parsed from a header value.
///
/// `name` is the display name when the header carried one (`Ada Lovelace
/// <ada@x.com>`), because that is what a card shows; `address` is always the machine
/// half and is lowercased for comparison. Header values arrive from a remote server,
/// so the parser is tolerant: anything it cannot make sense of is dropped rather
/// than throwing.
public struct EmailAddress: Sendable, Hashable, CustomStringConvertible {
    /// The display name, RFC 2047-decoded, or `nil` when the header had only an
    /// address.
    public var name: String?
    /// The bare address, lowercased, no angle brackets.
    public var address: String

    public init(name: String? = nil, address: String) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmedName?.isEmpty ?? true) ? nil : trimmedName
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// What a card should show: the display name when there is one, else the address.
    public var description: String { name ?? address }

    /// Whether this address is one of `candidates`. Both sides are normalised, so a
    /// caller never has to pre-lowercase anything.
    public func matches(anyOf candidates: [String]) -> Bool {
        let mine = address.lowercased()
        return candidates.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == mine }
    }

    /// Parses a header address list: `"Ada Lovelace" <ada@x.com>, grace@x.com`.
    ///
    /// Splitting is done by a scanner rather than `components(separatedBy: ",")`
    /// because a quoted display name may contain a comma (`"Lovelace, Ada"
    /// <ada@x.com>`). Group syntax (`undisclosed-recipients:;`) is not expanded --
    /// there is nothing to expand it into -- so its members simply do not appear.
    public static func parseList(_ raw: String) -> [EmailAddress] {
        split(raw, on: ",").compactMap(parse)
    }

    /// Parses one address. `Ada Lovelace <ada@x.com>` -> name + address; a bare
    /// `ada@x.com` -> address only. A token that is not `local@domain.tld` is
    /// dropped: it cannot be matched against the user's own address, and inventing
    /// one would put a junk name on a card.
    public static func parse(_ raw: String) -> EmailAddress? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        if let open = token.lastIndex(of: "<"), let close = token.lastIndex(of: ">"), open < close {
            let address = String(token[token.index(after: open)..<close])
            let name = String(token[token.startIndex..<open])
            guard isPlausibleAddress(address) else { return nil }
            // A quoted display name keeps its internal comma but loses the quotes that
            // were only there to protect it from the list split.
            return EmailAddress(name: unquote(MIMEText.decodeWordSequences(name)), address: address)
        }
        let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard isPlausibleAddress(bare) else { return nil }
        return EmailAddress(name: nil, address: bare)
    }

    /// Removes the surrounding quotes from a display name and unescapes `\"`/`\\`.
    /// `nil` when nothing is left, so a message from `"" <a@b.com>` prints as the
    /// address rather than an empty name.
    static func unquote(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") {
            name = String(name.dropFirst().dropLast())
            name = name.replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return name.isEmpty ? nil : name
    }

    /// `local@domain` with no whitespace and a dotted, non-empty domain.
    /// Deliberately loose: this decides who a message is from, it does not reject
    /// mail.
    static func isPlausibleAddress(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts[1].contains(".")
    }

    /// Splits on `separator` at quote/bracket depth zero.
    static func split(_ raw: String, on separator: Character) -> [String] {
        var pieces: [String] = []
        var current = ""
        var inQuotes = false
        var depth = 0
        for character in raw {
            if character == "\"" { inQuotes.toggle() }
            if !inQuotes {
                if character == "<" || character == "(" { depth += 1 }
                if character == ">" || character == ")" { depth -= 1 }
                if character == separator, depth <= 0 {
                    pieces.append(current)
                    current = ""
                    continue
                }
            }
            current.append(character)
        }
        pieces.append(current)
        return pieces
    }
}

// MARK: - Providing the account

/// Where the configured mailbox comes from.
///
/// The real conformance in the app is `UserDefaultsEmailAccountProvider`; tests and
/// previews use `StaticEmailAccountProvider`. The protocol exists so `EmailSource`
/// never reaches for a global store, and so "no account configured" is a value a
/// test can produce.
///
/// **Why this is not a Keychain read.** Only the *password* is a secret. Host, port
/// and username are shown on the settings screen and are safe in `UserDefaults`;
/// keeping them out of the Keychain means the settings UI can read them without
/// waiting on an unlock.
public protocol EmailAccountProviding: Sendable {
    /// The configured mailbox, or `nil` when the user has not set one up.
    ///
    /// Throws only for a store that exists but cannot be read; "not configured" is
    /// `nil`, not an error.
    func configuredAccount() throws -> EmailAccount?
}

/// An account provider that returns a literal value. Used by tests, previews and the
/// app's preview scenarios.
public struct StaticEmailAccountProvider: EmailAccountProviding {
    public let account: EmailAccount?

    public init(account: EmailAccount?) {
        self.account = account
    }

    public func configuredAccount() throws -> EmailAccount? { account }
}

/// The non-secret half of the connection, persisted in `UserDefaults`.
///
/// The password never comes near this type. The account is stored as JSON under one
/// key so a future settings screen can round-trip the whole struct, and a corrupt
/// value reads back as "not configured" rather than failing capture forever.
public struct UserDefaultsEmailAccountProvider: EmailAccountProviding, @unchecked Sendable {
    /// The defaults key the account JSON is written to.
    public static let storageKey = "com.steveafrost.thirdhand.imap.account"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsEmailAccountProvider.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    public func configuredAccount() throws -> EmailAccount? {
        guard let data = defaults.data(forKey: key) else { return nil }
        // A value we cannot read is not an account. Reporting it as an error would
        // make capture fail forever with no way to fix it from the board, so it reads
        // as "not configured" -- which the UI already presents as "connect a mailbox".
        return try? JSONDecoder().decode(EmailAccount.self, from: data)
    }

    /// Persists (or, with `nil`, clears) the account. No secret is involved.
    public func save(_ account: EmailAccount?) throws {
        guard let account else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try JSONEncoder().encode(account), forKey: key)
    }
}
