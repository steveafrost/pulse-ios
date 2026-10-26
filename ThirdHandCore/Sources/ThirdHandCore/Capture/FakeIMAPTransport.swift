import Foundation

/// An `IMAPTransport` backed by a scripted server. **Test and preview only.**
///
/// It is a real (if tiny) IMAP server: it parses the tag and command name out of what
/// the client sends, answers in wire format -- untagged lines, `{n}` literals, a
/// tagged verdict -- and records the commands it saw. That is deliberate. A fake that
/// returned canned responses without reading the request would let a broken client
/// (wrong tag, wrong mailbox, `BODY[]` instead of `BODY.PEEK[]`) pass every test.
///
/// Lives in `ThirdHandCore` rather than the test target for the same reason
/// `FakeSource` does: the test target needs it, and a preview of the mail settings
/// screen needs something to point at without a mailbox.
///
/// **The recorded commands contain a `LOGIN` line, which contains a password.** That
/// is why `commands` is not `CustomStringConvertible` and why the request log is
/// assembled by the fake's own code, never by printing a value. Tests that assert on
/// the log assert on which command *names* appeared (`commandNames`), not on the log
/// as text.
public final class FakeIMAPTransport: IMAPTransport, @unchecked Sendable {
    /// One scripted message, as the server would serve it.
    public struct ScriptedMessage: Sendable, Hashable {
        public var uid: UInt32
        public var messageID: String?
        public var subject: String
        public var from: [EmailAddress]
        public var to: [EmailAddress]
        public var cc: [EmailAddress]
        public var date: String?
        public var inReplyTo: String?
        public var references: String?

        public init(
            uid: UInt32,
            messageID: String? = nil,
            subject: String = "",
            from: [EmailAddress] = [],
            to: [EmailAddress] = [],
            cc: [EmailAddress] = [],
            date: String? = "Fri, 23 Oct 2026 18:04:11 +0000",
            inReplyTo: String? = nil,
            references: String? = nil
        ) {
            self.uid = uid
            self.messageID = messageID
            self.subject = subject
            self.from = from
            self.to = to
            self.cc = cc
            self.date = date
            self.inReplyTo = inReplyTo
            self.references = references
        }

        /// The `HEADER.FIELDS` block the server would put in a literal.
        var headerBlock: String {
            var lines = ["From: " + from.map(Self.format).joined(separator: ", ")]
            lines.append("To: " + to.map(Self.format).joined(separator: ", "))
            if !cc.isEmpty {
                lines.append("Cc: " + cc.map(Self.format).joined(separator: ", "))
            }
            lines.append("Subject: " + subject)
            if let date {
                lines.append("Date: " + date)
            }
            if let messageID {
                lines.append("Message-ID: <\(messageID)>")
            }
            if let inReplyTo {
                lines.append("In-Reply-To: <\(inReplyTo)>")
            }
            if let references {
                lines.append("References: <\(references)>")
            }
            // Blank line terminates the header block, exactly as on the wire.
            return lines.joined(separator: "\r\n") + "\r\n\r\n"
        }

        static func format(_ address: EmailAddress) -> String {
            if let name = address.name {
                return "\"\(name)\" <\(address.address)>"
            }
            return "<\(address.address)>"
        }
    }

    /// What the fake does with the conversation.
    public enum Behaviour: Sendable, Hashable {
        /// Everything works and the mailbox has `messages`.
        case serving
        /// `open` throws, as a refused socket would.
        case connectionFails(String)
        /// The greeting never arrives.
        case noGreeting
        /// `CAPABILITY` omits `IMAP4REV1`.
        case notIMAP4Rev1
        /// `LOGIN` answers `NO`, as a wrong app password does.
        case loginRejected
        /// `SELECT` answers `NO` (a mailbox that does not exist).
        case selectRejected
        /// `UID SEARCH` answers `BAD`.
        case searchRejected
        /// `UID FETCH` answers `BAD`.
        case fetchRejected
    }

    public let behaviour: Behaviour
    private let messages: [ScriptedMessage]
    private let lock = NSLock()
    private var openedAccounts: [EmailAccount] = []
    private var requestLog: [String] = []

    public init(messages: [ScriptedMessage] = [], behaviour: Behaviour = .serving) {
        self.messages = messages
        self.behaviour = behaviour
    }

    /// How many times `open` was called.
    public var openCount: Int {
        lock.withLock { openedAccounts.count }
    }

    /// The accounts `open` was called with. No secret: an account carries none.
    public var accounts: [EmailAccount] {
        lock.withLock { openedAccounts }
    }

    /// Every command line the client sent, in order, `LOGIN` included.
    ///
    /// Exposed only so a test can assert *which commands* were sent -- see
    /// `commandNames`. Never print this array.
    public var commands: [String] {
        lock.withLock { requestLog }
    }

    /// The command names sent, with arguments stripped: `["CAPABILITY", "LOGIN",
    /// "SELECT", "UID SEARCH", "UID FETCH", "LOGOUT"]`. This is the assertion surface
    /// for "the client speaks only the subset it claims to".
    public var commandNames: [String] {
        commands.map { line in
            let tokens = line.split(separator: " ")
            // Drop the tag. `withoutTag` is a slice of `tokens`, so every index below
            // is stepped from its own `startIndex`.
            let withoutTag = tokens.dropFirst()
            guard let name = withoutTag.first else { return "" }
            if name.caseInsensitiveCompare("UID") == .orderedSame {
                let second = withoutTag.index(withoutTag.startIndex, offsetBy: 1)
                if second < withoutTag.endIndex {
                    return "UID \(withoutTag[second])"
                }
            }
            return String(name).uppercased()
        }
    }

    private func record(_ line: String) {
        lock.withLock { requestLog.append(line) }
    }

    public func open(account: EmailAccount) async throws -> any IMAPSession {
        lock.withLock { openedAccounts.append(account) }
        if case let .connectionFails(reason) = behaviour {
            throw IMAPError.connectionFailed(reason)
        }
        return FakeIMAPSession(
            transport: self,
            greeting: { [behaviour] in
                switch behaviour {
                case .noGreeting: nil
                default: "* OK fake server ready"
                }
            }(),
            behaviour: behaviour,
            messages: messages
        )
    }

    /// One session's state: the outbound commands already produced, and the inbound
    /// lines still to hand back.
    final class FakeIMAPSession: IMAPSession, @unchecked Sendable {
        private weak var transport: FakeIMAPTransport?
        private let greeting: String?
        private let behaviour: Behaviour
        private let messages: [ScriptedMessage]

        private let lock = NSLock()
        private var pending: [IMAPResponse.Part] = []

        init(transport: FakeIMAPTransport, greeting: String?, behaviour: Behaviour, messages: [ScriptedMessage]) {
            self.transport = transport
            self.greeting = greeting
            self.behaviour = behaviour
            self.messages = messages
        }

        /// Hands back the next line. Every command is answered synchronously by
        /// `send`, which fills `pending`, so a read only dequeues.
        func readLine() async throws -> String? {
            try lock.withLock {
                while !pending.isEmpty {
                    let part = pending.removeFirst()
                    switch part {
                    case let .text(text):
                        return text
                    case let .literal(literal):
                        throw IMAPError.unexpectedResponse("literal served without a marker (\(literal.count) bytes)")
                    }
                }
                return nil
            }
        }

        func readLiteral(count: Int) async throws -> String {
            try lock.withLock {
                guard !pending.isEmpty, case let .literal(literal) = pending[0] else {
                    throw IMAPError.unexpectedResponse("no literal was queued for a \(count)-byte read")
                }
                pending.removeFirst()
                let bytes = Array(literal.utf8)
                guard bytes.count == count else {
                    throw IMAPError.unexpectedResponse("literal was \(bytes.count) bytes, marker said \(count)")
                }
                return literal
            }
        }

        func send(_ line: String) async throws {
            transport?.record(line)
            let responses = FakeServer.respond(
                to: line,
                behaviour: behaviour,
                messages: messages
            )
            lock.withLock { pending.append(contentsOf: responses) }
        }

        func close() async {
            lock.withLock { pending.removeAll() }
        }
    }
}

/// The fake's protocol logic, kept separate from the session so it is a pure function
/// of `(request, behaviour, messages)` and can be reasoned about on its own.
enum FakeServer {
    /// Builds the queued response parts for one request line.
    static func respond(
        to line: String,
        behaviour: FakeIMAPTransport.Behaviour,
        messages: [FakeIMAPTransport.ScriptedMessage]
    ) -> [IMAPResponse.Part] {
        let tokens = line.split(separator: " ").map(String.init)
        guard let tag = tokens.first else { return [] }
        let rest = tokens.dropFirst()

        func token(_ offset: Int) -> String? {
            // `rest` is a slice, so its indices start at 1; this accessor keeps that
            // arithmetic in one place rather than spelling `rest[2]` at each use.
            let index = rest.startIndex + offset
            return index < rest.endIndex ? String(rest[index]) : nil
        }

        guard let command = token(0)?.uppercased() else {
            return [.text("\(tag) BAD empty command")]
        }

        switch command {
        case "CAPABILITY":
            let caps = behaviour == .notIMAP4Rev1
                ? "IMAP4rev1-Absent AUTH=PLAIN"
                : "IMAP4rev1 AUTH=PLAIN AUTH=LOGIN"
            return [
                .text("* CAPABILITY \(caps)"),
                .text("\(tag) OK CAPABILITY completed")
            ]

        case "LOGIN":
            if behaviour == .loginRejected {
                return [.text("\(tag) NO [AUTHENTICATIONFAILED] Invalid credentials")]
            }
            return [.text("\(tag) OK LOGIN completed")]

        case "SELECT":
            if behaviour == .selectRejected {
                return [.text("\(tag) NO [NONEXISTENT] Unknown mailbox")]
            }
            return [
                .text("* \(messages.count) EXISTS"),
                .text("* 0 RECENT"),
                .text("* OK [UIDVALIDITY 1] UIDs valid"),
                .text("\(tag) OK [READ-WRITE] SELECT completed")
            ]

        case "UID" where token(1)?.uppercased() == "SEARCH":
            if behaviour == .searchRejected {
                return [.text("\(tag) BAD SEARCH is not allowed")]
            }
            let uids = messages.map { String($0.uid) }.joined(separator: " ")
            return [
                .text("* SEARCH\(uids.isEmpty ? "" : " " + uids)"),
                .text("\(tag) OK SEARCH completed")
            ]

        case "UID" where token(1)?.uppercased() == "FETCH":
            if behaviour == .fetchRejected {
                return [.text("\(tag) BAD FETCH is not allowed")]
            }
            guard let rawUID = token(2), let uid = UInt32(rawUID),
                  let message = messages.first(where: { $0.uid == uid })
            else {
                // Nothing to fetch: the message was expunged between SEARCH and FETCH.
                return [.text("\(tag) OK FETCH completed")]
            }
            let block = message.headerBlock
            let count = block.utf8.count
            return [
                .text(
                    "* 1 FETCH (UID \(uid) BODY[HEADER.FIELDS (FROM TO CC SUBJECT DATE MESSAGE-ID REFERENCES IN-REPLY-TO)] {\(count)}"
                ),
                .literal(block),
                .text(")"),
                .text("\(tag) OK FETCH completed")
            ]

        case "LOGOUT":
            return [
                .text("* BYE logging out"),
                .text("\(tag) OK LOGOUT completed")
            ]

        case "NOOP":
            return [.text("\(tag) OK NOOP completed")]

        default:
            return [.text("\(tag) BAD unknown command \(command)")]
        }
    }
}
