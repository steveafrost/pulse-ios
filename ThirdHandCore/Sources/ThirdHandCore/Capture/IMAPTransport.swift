import Foundation

/// The byte-level seam IMAP talks through.
///
/// A session is one already-connected, already-TLS'd mailbox: `IMAPTransport.open`
/// is responsible for the socket and the handshake, so everything above it is pure
/// protocol text and can be exercised by `FakeIMAPTransport` with no network. The
/// greeting (`* OK <server> ready`) has been consumed by the time a session is
/// handed back, which keeps the client's first command predictable.
///
/// **Why three methods and not a stream.** IMAP is line-oriented except for
/// literals: a server answers a command with one or more lines, and a `FETCH` of a
/// message section carries its payload as `{<n>}\r\n<n raw bytes>`. Modelling that
/// as `readLine` + `readLiteral(count:)` is the whole protocol surface a client
/// needs, and it is the smallest thing a fake can implement faithfully.
public protocol IMAPSession: Sendable {
    /// The next CRLF-terminated line, without the CRLF. `nil` at end of stream.
    func readLine() async throws -> String?

    /// Exactly `count` bytes, decoded as UTF-8 with replacement for anything
    /// invalid. Header text is either UTF-8 or RFC 2047-encoded inside ASCII, so a
    /// lossy decode only ever mangles a non-conforming sender's bytes.
    func readLiteral(count: Int) async throws -> String

    /// Writes one command line. The value may contain a credential; nothing in this
    /// module logs it.
    func send(_ line: String) async throws

    /// Tears the connection down. Idempotent, and safe to call after a failure.
    func close() async
}

/// Opens an IMAPS session for an account.
///
/// The real conformance is `TLSIMAPTransport`; tests use `FakeIMAPTransport`. Note
/// what is *not* here: a password. The password travels in the command text, one
/// `LOGIN` line, because that is what IMAP is; keeping it out of this signature
/// means a transport cannot stash it.
public protocol IMAPTransport: Sendable {
    func open(account: EmailAccount) async throws -> any IMAPSession
}

/// Everything that can go wrong below the classification layer, with enough detail
/// for a log line and nothing secret in it.
public enum IMAPError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The socket, TLS handshake or DNS failed.
    case connectionFailed(String)
    /// The server answered `LOGIN` with `NO`/`BAD`. A credential problem, which is
    /// the distinct "connect your mailbox" state, not a failed pass.
    case authenticationFailed(String)
    /// A command was refused. `command` is the command name only, never its
    /// arguments, so a `LOGIN` can never be reproduced from an error message.
    case commandFailed(command: String, status: String)
    /// The server said something the client cannot interpret.
    case unexpectedResponse(String)
    /// The stream ended mid-response.
    case connectionClosed
    /// A credential contained a CR or LF, which would forge a command.
    case invalidCredential

    public var description: String {
        switch self {
        case .connectionFailed(let reason): "could not reach the mail server: \(reason)"
        case .authenticationFailed(let reason): "the mail server rejected the credentials: \(reason)"
        case .commandFailed(let command, let status): "\(command) was refused: \(status)"
        case .unexpectedResponse(let detail): "unexpected mail server response: \(detail)"
        case .connectionClosed: "the mail server closed the connection"
        case .invalidCredential: "the mailbox credential contains an illegal line break"
        }
    }
}

// MARK: - Quoting

/// The two places a value goes into an IMAP command, both of which must be
/// injection-proof.
///
/// A username, password or mailbox name is appended to a command line the server
/// parses. A `"` or a CRLF in any of them would let a stored credential append a
/// command of its own choosing, so quoting is a security boundary, not formatting.
public enum IMAPQuote {
    /// A quoted string: `"` and `\` escaped, and any CR/LF refused outright rather
    /// than escaped (a literal would be legal IMAP but is not worth the surface).
    public static func string(_ raw: String) throws -> String {
        // Checked over `unicodeScalars`, not `Characters`: CRLF is a single grapheme
        // cluster in Swift, so `character == "\r"` is false for a CRLF and a
        // `Character`-level check would let the one sequence that matters through.
        guard !raw.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) else {
            throw IMAPError.invalidCredential
        }
        var escaped = ""
        for character in raw {
            if character == "\"" || character == "\\" { escaped.append("\\") }
            escaped.append(character)
        }
        return "\"\(escaped)\""
    }
}

// MARK: - Responses

/// One server response line, with its literals kept structurally separate from the
/// text around them.
///
/// A `FETCH` arrives as text, then `{n}` + raw bytes, then the remainder of the
/// line. Concatenating the two would corrupt both, so they stay apart and each
/// parser takes the half it understands.
public struct IMAPResponse: Sendable, Equatable {
    public enum Part: Sendable, Equatable {
        case text(String)
        case literal(String)
    }

    public var parts: [Part]

    public init(parts: [Part]) {
        self.parts = parts
    }

    /// Every text part, in order, joined by a space -- enough for token matching on
    /// a response that carries no literals.
    public var text: String {
        parts.compactMap { part in
            if case .text(let text) = part { return text }
            return nil
        }.joined(separator: " ")
    }

    /// The literal payloads, in order. A `FETCH` for a single header section has
    /// exactly one.
    public var literals: [String] {
        parts.compactMap { part in
            if case .literal(let literal) = part { return literal }
            return nil
        }
    }
}

// MARK: - Client

/// A minimal IMAP4rev1 client: enough to log in, select a mailbox and read the
/// headers of every unseen message.
///
/// **The deliberate subset.** `CAPABILITY`, `LOGIN`, `SELECT`, `UID SEARCH UNSEEN`,
/// `UID FETCH BODY.PEEK[HEADER.FIELDS …]`, `LOGOUT`. Nothing else -- no `IDLE`, no
/// `APPEND`, no `STORE`, no `SEARCH` beyond `UNSEEN`. In particular every fetch is
/// `BODY.PEEK`, never `BODY[...]`, so capture never flips a message to `\Seen`:
/// reading the board must not silently clear the user's inbox. That is a product
/// decision as much as a protocol one.
///
/// `AUTHENTICATE PLAIN` was considered and rejected for v1.2: `LOGIN` is in the
/// IMAP4rev1 base set and every server that offers `AUTH=PLAIN` also accepts it over
/// TLS, while SASL's multi-step continuation is more surface to fake and test.
public struct IMAPClient: Sendable {
    /// The headers requested. Kept to the ones classification reads, so a poll is a
    /// few kilobytes per message rather than a message body.
    public static let headerFields = [
        "FROM", "TO", "CC", "SUBJECT", "DATE", "MESSAGE-ID", "REFERENCES", "IN-REPLY-TO",
    ]

    /// How many unseen messages one pass considers. A thousand-message backlog would
    /// otherwise produce a thousand `FETCH` round trips; the cap is applied to the
    /// search result *before* fetching, and deliberately reported rather than hidden
    /// (`EmailSource` notes it in the item reason).
    public static let defaultLimit = 200

    private let transport: any IMAPTransport
    private let account: EmailAccount
    private let credentials: EmailCredentials
    private let limit: Int

    public init(
        transport: any IMAPTransport,
        account: EmailAccount,
        credentials: EmailCredentials,
        limit: Int = IMAPClient.defaultLimit
    ) {
        self.transport = transport
        self.account = account
        self.credentials = credentials
        self.limit = limit
    }

    /// Open, log in, select, search, fetch, log out.
    ///
    /// Throws `IMAPError.authenticationFailed` for a rejected `LOGIN` and
    /// `IMAPError.commandFailed`/`.connectionClosed`/`.connectionFailed` for
    /// everything else; `EmailSource` is what maps those onto `CaptureError`.
    public func unreadMessages() async throws -> [EmailMessageSnapshot] {
        let session: any IMAPSession
        do {
            session = try await transport.open(account: account)
        } catch let error as IMAPError {
            throw error
        } catch let error as CaptureError {
            throw error
        } catch {
            throw IMAPError.connectionFailed(error.localizedDescription)
        }

        let conversation = IMAPConversation(session: session)
        do {
            let messages = try await run(conversation)
            await conversation.logout()
            return messages
        } catch {
            await session.close()
            throw error
        }
    }

    private func run(_ conversation: IMAPConversation) async throws -> [EmailMessageSnapshot] {
        // `CAPABILITY` first: IMAP4rev1 requires it in the non-authenticated state, and
        // checking that the server speaks the protocol at all before handing it a
        // password means a misconfigured host (an SMTP port, a proxy) never sees the
        // credential.
        let capabilities = try await conversation.capability()
        guard capabilities.contains(where: { $0.caseInsensitiveCompare("IMAP4REV1") == .orderedSame }) else {
            throw IMAPError.unexpectedResponse("server does not offer IMAP4rev1 (said: \(capabilities.joined(separator: " ")))")
        }

        try await conversation.authenticate(username: credentials.account.username, password: credentials.password)

        try await conversation.select(mailbox: account.mailbox)

        let uids = try await conversation.searchUnseen()
        guard !uids.isEmpty else { return [] }

        // Newest-first is the server's own order for UID SEARCH (ascending), so the
        // overflow is the *oldest* mail. Taking the highest uids means a large backlog
        // costs the user nothing they were going to act on today.
        let selected = Array(uids.sorted().suffix(limit))
        var messages: [EmailMessageSnapshot] = []
        for uid in selected {
            if let message = try await conversation.fetchHeaders(uid: uid) {
                messages.append(message)
            }
        }
        return messages.sorted { $0.uid < $1.uid }
    }
}

/// One command/response dialogue over a session.
///
/// A `final class` with mutable tag state and no concurrency: it is created and
/// driven inside a single `unreadMessages()` call and never escapes it. `@unchecked
/// Sendable` because Swift 6 requires a nominal type to cross the `await` boundaries
/// in that function, and the instance is confined to one task by construction.
final class IMAPConversation: @unchecked Sendable {
    private let session: any IMAPSession
    private var tagCounter = 0

    init(session: any IMAPSession) {
        self.session = session
    }

    /// `a1`, `a2`, … A per-session prefix is fine: tags only have to be unique within
    /// one connection.
    private func nextTag() -> String {
        tagCounter += 1
        return "a\(tagCounter)"
    }

    /// One complete response, with literals assembled.
    ///
    /// The loop exists because a literal interrupts the line: after `{n}` the server
    /// writes n bytes and then *continues the same response* on a new line. Reading
    /// until a line arrives that carries no trailing literal is what makes a `FETCH`
    /// look like one response.
    func readResponse() async throws -> IMAPResponse {
        var parts: [IMAPResponse.Part] = []
        while true {
            guard let line = try await session.readLine() else { throw IMAPError.connectionClosed }
            guard let literalCount = Self.trailingLiteralCount(line) else {
                parts.append(.text(line))
                return IMAPResponse(parts: parts)
            }
            // Keep the marker out of the text half: `{173}` is framing, not content.
            parts.append(.text(String(line.dropLast(String(literalCount).count + 2))))
            let literal = try await session.readLiteral(count: literalCount)
            parts.append(.literal(literal))
        }
    }

    /// `… {173}` -> 173. `nil` when the line does not end with a literal marker.
    /// Anchored at the end because `{n}` mid-line is a quoted-string character.
    static func trailingLiteralCount(_ line: String) -> Int? {
        guard line.hasSuffix("}") else { return nil }
        guard let open = line.lastIndex(of: "{") else { return nil }
        let digits = line[line.index(after: open)..<line.index(before: line.endIndex)]
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    /// Sends `command` under a fresh tag and reads until that tag's verdict.
    ///
    /// Returns the untagged responses plus the verdict's status (`OK`/`NO`/`BAD`) and
    /// its text. Untagged lines that arrive before the verdict belong to the command;
    /// there is no pipelining in this client, so that is unambiguous.
    private func command(_ name: String, _ arguments: String) async throws -> (untagged: [IMAPResponse], status: String, message: String) {
        let tag = nextTag()
        try await session.send(arguments.isEmpty ? "\(tag) \(name)" : "\(tag) \(name) \(arguments)")

        var untagged: [IMAPResponse] = []
        while true {
            let response = try await readResponse()
            let text = response.text
            if text.hasPrefix("\(tag) ") {
                let rest = text.dropFirst(tag.count + 1)
                let status = rest.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
                let message = rest.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                return (untagged, status.uppercased(), message)
            }
            if text.hasPrefix("* ") {
                untagged.append(response)
                continue
            }
            // A bare `+` continuation or an untagged line with no `*`: nothing in this
            // client's command set produces one, so treat it as noise and keep reading
            // rather than failing a pass over a server's unsolicited chatter.
            untagged.append(response)
        }
    }

    private func requireOK(
        _ name: String,
        _ arguments: String
    ) async throws -> [IMAPResponse] {
        let result = try await command(name, arguments)
        guard result.status == "OK" else {
            throw IMAPError.commandFailed(command: name, status: "\(result.status) \(result.message)")
        }
        return result.untagged
    }

    /// The greeting is the transport's problem; this asks the server what it speaks.
    func capability() async throws -> [String] {
        let untagged = try await requireOK("CAPABILITY", "")
        for response in untagged where response.text.hasPrefix("* CAPABILITY") {
            return response.text.split(separator: " ").dropFirst(2).map(String.init)
        }
        return []
    }

    /// `LOGIN` with quoted strings. On `NO`/`BAD` this throws
    /// `.authenticationFailed`, which is the signal `EmailSource` turns into
    /// `CaptureError.denied`.
    func authenticate(username: String, password: String) async throws {
        let quotedUser = try IMAPQuote.string(username)
        let quotedPassword = try IMAPQuote.string(password)
        let result = try await command("LOGIN", "\(quotedUser) \(quotedPassword)")
        guard result.status == "OK" else {
            throw IMAPError.authenticationFailed("\(result.status) \(result.message)".trimmingCharacters(in: .whitespaces))
        }
    }

    func select(mailbox: String) async throws {
        let quoted = try IMAPQuote.string(mailbox)
        _ = try await requireOK("SELECT", quoted)
    }

    /// `UID SEARCH UNSEEN`. The `SEARCH` response carries plain integers and nothing
    /// else; an empty result is a `* SEARCH` with no numbers, which is the healthy
    /// empty inbox, not an error.
    func searchUnseen() async throws -> [UInt32] {
        let untagged = try await requireOK("UID SEARCH", "UNSEEN")
        var uids: [UInt32] = []
        for response in untagged where response.text.hasPrefix("* SEARCH") {
            uids += response.text
                .split(separator: " ")
                .dropFirst(2)
                .compactMap { UInt32($0) }
        }
        return uids
    }

    /// Header-block fetch for one uid, or `nil` when the server returned no
    /// message-level `FETCH` for it (deleted between search and fetch).
    func fetchHeaders(uid: UInt32) async throws -> EmailMessageSnapshot? {
        let fields = IMAPClient.headerFields.joined(separator: " ")
        let untagged = try await requireOK(
            "UID FETCH",
            "\(uid) (UID BODY.PEEK[HEADER.FIELDS (\(fields))])"
        )

        for response in untagged where response.text.contains("FETCH") {
            guard let fetchedUID = Self.uid(in: response.text), fetchedUID == uid else { continue }
            guard let headerText = response.literals.first else { continue }
            return IMAPParser.message(uid: uid, headerBlock: headerText)
        }
        return nil
    }

    /// `* 4 FETCH (UID 101 BODY[...]…` -> 101.
    static func uid(in text: String) -> UInt32? {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ")" })
        for (index, token) in tokens.enumerated() where token.caseInsensitiveCompare("UID") == .orderedSame {
            guard index + 1 < tokens.count else { continue }
            if let value = UInt32(tokens[index + 1]) { return value }
        }
        return nil
    }

    /// `LOGOUT` is best effort: the pass has already succeeded or failed, and a
    /// server that ignores the courtesy line must not turn a good result into a bad
    /// one. The session is closed either way.
    func logout() async {
        _ = try? await command("LOGOUT", "")
        await session.close()
    }
}

// MARK: - Parsing

/// Turns a `FETCH` header block into an `EmailMessageSnapshot`.
///
/// Pure and total: every field is optional in practice and a message with unusable
/// headers still becomes a snapshot, because a message the user cannot see is worse
/// than a badly-titled one.
public enum IMAPParser {
    /// A header block is lines of `Name: value` with continuation lines that begin
    /// with whitespace. Unfolding happens here, once, so no rule above has to think
    /// about it. Later occurrences of a name win, matching how most mail clients read
    /// a repeated header (the last `Received`, the last `To` block).
    public static func headers(from block: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentName: String?
        var currentValue = ""

        func flush() {
            guard let name = currentName else { return }
            headers[name] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // CRLF is what a server sends; a bare LF is accepted because a fixture, a
        // forwarded copy or a non-conforming server may produce one, and a header
        // block that fails to split turns every message into an untitled card.
        let normalized = block.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if rawLine.isEmpty {
                // The blank line ends the header block; anything after it is body.
                break
            }
            if rawLine.first == " " || rawLine.first == "\t" {
                currentValue += " " + rawLine.trimmingCharacters(in: .whitespaces)
                continue
            }
            flush()
            guard let colon = rawLine.firstIndex(of: ":") else {
                currentName = nil
                currentValue = ""
                continue
            }
            currentName = rawLine[rawLine.startIndex..<colon]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            currentValue = String(rawLine[rawLine.index(after: colon)...])
        }
        flush()
        return headers
    }

    /// One snapshot from a uid and its header block.
    public static func message(uid: UInt32, headerBlock: String) -> EmailMessageSnapshot {
        let headers = headers(from: headerBlock)
        let subject = headers["subject"].map(MIMEText.decodeWordSequences) ?? ""
        let messageID = headers["message-id"].flatMap(normalizeMessageID)
        let references = headers["references"]
        let inReplyTo = headers["in-reply-to"].flatMap(normalizeMessageID)
        return EmailMessageSnapshot(
            uid: uid,
            messageID: messageID,
            subject: subject,
            from: EmailAddress.parseList(headers["from"] ?? ""),
            to: EmailAddress.parseList(headers["to"] ?? ""),
            cc: EmailAddress.parseList(headers["cc"] ?? ""),
            sentAt: headers["date"].flatMap(MailDateParser.parse),
            receivedAt: nil,
            isReply: isReplyHeader(subject: subject, inReplyTo: inReplyTo, references: references)
        )
    }

    /// A message id without its angle brackets: `gmail:message:<id>` reads better and
    /// brackets are framing. Case is preserved -- the local part of a Message-ID is
    /// case-sensitive in practice and two ids differing only in case are two ids.
    public static func normalizeMessageID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether a message sits in a thread someone already answered.
    ///
    /// Headers only, so the evidence is a `Re:`-style subject prefix or a non-empty
    /// `In-Reply-To`/`References`. `aw:`/`sv:` are the German and Swedish reply
    /// prefixes, included because Gmail users with a non-English locale produce them
    /// and a `Re:`-only check would misread their threads.
    public static func isReplyHeader(subject: String, inReplyTo: String?, references: String?) -> Bool {
        let lowered = subject.trimmingCharacters(in: .whitespaces).lowercased()
        if lowered.hasPrefix("re:") || lowered.hasPrefix("re[") || lowered.hasPrefix("aw:") || lowered.hasPrefix("sv:") {
            return true
        }
        if let inReplyTo, !inReplyTo.isEmpty { return true }
        if let references, !references.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
}
