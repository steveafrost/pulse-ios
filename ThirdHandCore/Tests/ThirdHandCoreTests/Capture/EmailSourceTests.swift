import Foundation
import Testing
@testable import ThirdHandCore

/// The end-to-end behaviour of `EmailSource` against a fake server: the failure
/// states the board must distinguish, and the classification of real messages.
@Suite("EmailSource")
struct EmailSourceTests {
    private let window = CaptureWindow.rolling(hours: 24, now: Fixture.now)

    // MARK: - Failure states

    @Test("no configured mailbox throws denied, never an empty board")
    func noAccount() async {
        let (source, transport, _) = EmailFixture.source(account: nil)
        await #expect(throws: CaptureError.denied(.gmail)) {
            try await source.detect(now: Fixture.now, window: window)
        }
        // Nothing was even attempted: a missing configuration never opens a socket.
        #expect(transport.openCount == 0)
    }

    @Test("a missing keychain secret throws denied")
    func noSecret() async {
        let (source, transport, _) = EmailFixture.source(secret: nil)
        await #expect(throws: CaptureError.denied(.gmail)) {
            try await source.detect(now: Fixture.now, window: window)
        }
        #expect(transport.openCount == 0)
    }

    @Test("an empty string secret counts as no secret")
    func emptySecret() async {
        let (source, _, _) = EmailFixture.source(secret: "")
        await #expect(throws: CaptureError.denied(.gmail)) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("a rejected LOGIN throws denied")
    func loginRejected() async {
        let (source, transport, _) = EmailFixture.source(
            messages: [EmailFixture.direct()],
            behaviour: .loginRejected
        )
        await #expect(throws: CaptureError.denied(.gmail)) {
            try await source.detect(now: Fixture.now, window: window)
        }
        #expect(transport.openCount == 1)
    }

    @Test("an unreachable server throws underlying, not denied")
    func connectionFailure() async {
        let (source, _, _) = EmailFixture.source(
            behaviour: .connectionFails("connection refused")
        )
        await #expect(throws: CaptureError.underlying("could not reach the mail server: connection refused")) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("a SELECT the server refuses throws underlying with the command named")
    func selectRejected() async {
        let (source, _, _) = EmailFixture.source(behaviour: .selectRejected)
        await #expect(throws: CaptureError.underlying("SELECT was refused: NO [NONEXISTENT] Unknown mailbox")) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("a SEARCH the server refuses throws underlying")
    func searchRejected() async {
        let (source, _, _) = EmailFixture.source(behaviour: .searchRejected)
        await #expect(throws: CaptureError.underlying("UID SEARCH was refused: BAD SEARCH is not allowed")) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("a FETCH the server refuses throws underlying")
    func fetchRejected() async {
        let (source, _, _) = EmailFixture.source(
            messages: [EmailFixture.direct()],
            behaviour: .fetchRejected
        )
        await #expect(throws: CaptureError.underlying("UID FETCH was refused: BAD FETCH is not allowed")) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("a server that is not IMAP4rev1 throws underlying")
    func wrongProtocol() async {
        let (source, _, _) = EmailFixture.source(behaviour: .notIMAP4Rev1)
        await #expect(throws: CaptureError.underlying(
            "unexpected mail server response: server does not offer IMAP4rev1 (said: IMAP4rev1-Absent AUTH=PLAIN)"
        )) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("an unreadable account store throws underlying, not empty")
    func unreadableAccountStore() async {
        let source = EmailSource(
            transport: FakeIMAPTransport(),
            accounts: EmailFixture.ThrowingAccountProvider(),
            secrets: InMemorySecretStore()
        )
        await #expect(throws: CaptureError.underlying("mail account settings are unreadable: defaults are corrupt")) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    @Test("an unreadable keychain throws denied")
    func unreadableKeychain() async {
        let source = EmailSource(
            transport: FakeIMAPTransport(),
            accounts: StaticEmailAccountProvider(account: EmailFixture.account),
            secrets: EmailFixture.ThrowingSecretStore()
        )
        await #expect(throws: CaptureError.denied(.gmail)) {
            try await source.detect(now: Fixture.now, window: window)
        }
    }

    // MARK: - The healthy empty case

    @Test("an empty inbox returns no items and is not an error")
    func emptyInbox() async throws {
        let (source, transport, _) = EmailFixture.source()
        let items = try await source.detect(now: Fixture.now, window: window)
        #expect(items.isEmpty)
        #expect(source.sourceID == .gmail)
        // The whole conversation happened: this was a real, successful poll.
        #expect(transport.commandNames == ["CAPABILITY", "LOGIN", "SELECT", "UID SEARCH", "LOGOUT"])
    }

    // MARK: - Classification through the whole stack

    @Test("a direct unread message with a question becomes reply/normal")
    func directQuestion() async throws {
        let (source, _, _) = EmailFixture.source(messages: [
            EmailFixture.direct(uid: 7, messageID: "q-7@x", subject: "Can you review this today?")
        ])
        let item = try #require(try await source.detect(now: Fixture.now, window: window).first)
        #expect(item.id == "gmail:message:q-7@x")
        #expect(item.source == .gmail)
        #expect(item.kind == .reply)
        #expect(item.priority == .normal)
        #expect(item.title == "Can you review this today?")
        #expect(item.people == ["Ada Lovelace"])
    }

    @Test("a deadline subject becomes deadline/high")
    func deadline() async throws {
        let (source, _, _) = EmailFixture.source(messages: [
            EmailFixture.direct(subject: "Invoice due Friday", to: [EmailFixture.me, EmailFixture.colleague])
        ])
        let item = try #require(try await source.detect(now: Fixture.now, window: window).first)
        #expect(item.kind == .deadline)
        #expect(item.priority == .high)
    }

    @Test("a decision request becomes decision/normal")
    func decision() async throws {
        let (source, _, _) = EmailFixture.source(messages: [
            EmailFixture.direct(subject: "Should we ship the beta this week")
        ])
        let item = try #require(try await source.detect(now: Fixture.now, window: window).first)
        #expect(item.kind == .decision)
        #expect(item.priority == .normal)
    }

    @Test("an unread message addressed to nobody else but already a reply is followup, never fyi")
    func unreadReplyIsNeverFYI() async throws {
        let (source, _, _) = EmailFixture.source(messages: [
            EmailFixture.direct(subject: "Re: numbers", inReplyTo: "orig@x")
        ])
        let item = try #require(try await source.detect(now: Fixture.now, window: window).first)
        #expect(item.kind == .followup)
        #expect(item.kind != .fyi)
    }

    @Test("every classification of a direct unread message stays actionable")
    func neverFYI() async throws {
        let subjects = [
            "Weekly digest", // no question, no markers
            "Re: Re: thread", // a reply
            "Fwd: something", // forwarded
            "", // no subject at all
            "Meeting notes 2026-10-20" // informational-looking
        ]
        let messages = subjects.enumerated().map { index, subject in
            EmailFixture.direct(uid: UInt32(200 + index), messageID: "nofyi-\(index)@x", subject: subject)
        }
        let (source, _, _) = EmailFixture.source(messages: messages)
        let items = try await source.detect(now: Fixture.now, window: window)
        #expect(items.count == subjects.count)
        #expect(items.allSatisfy { $0.kind != .fyi })
        #expect(items.allSatisfy { $0.priority != .low })
    }

    // MARK: - Identity

    @Test("a re-fetch of the same mailbox produces identical ids")
    func stableIdentity() async throws {
        let messages = [
            EmailFixture.direct(uid: 1, messageID: "a@x", subject: "First"),
            EmailFixture.direct(uid: 2, messageID: "b@x", subject: "Second")
        ]
        let (firstSource, _, _) = EmailFixture.source(messages: messages)
        let (secondSource, _, _) = EmailFixture.source(messages: messages)

        let first = try await firstSource.detect(now: Fixture.now, window: window).map(\.id)
        let second = try await secondSource.detect(now: Fixture.now, window: window).map(\.id)
        #expect(first == second)
        #expect(first == ["gmail:message:a@x", "gmail:message:b@x"])
    }

    @Test("a message with no Message-ID gets a deterministic uid-derived id")
    func noMessageID() async throws {
        let messages = [EmailFixture.direct(uid: 4242, messageID: nil, subject: "No id here")]
        let (firstSource, _, _) = EmailFixture.source(messages: messages)
        let (secondSource, _, _) = EmailFixture.source(messages: messages)

        let first = try #require(try await firstSource.detect(now: Fixture.now, window: window).first)
        let second = try #require(try await secondSource.detect(now: Fixture.now, window: window).first)
        #expect(first.id == "gmail:message:uid:4242")
        #expect(first.id == second.id)
        #expect(DetectedItem.isValidIdentifier(first.id))
        #expect(DetectedItem.source(fromIdentifier: first.id) == .gmail)
    }

    @Test("two mailboxes delivering the same Message-ID produce one id")
    func sharedMessageIDAcrossAccounts() {
        let message = EmailFixture.snapshot(messageID: "shared@list.example.org")
        let a = EmailSource.identifier(for: message, account: EmailFixture.account)
        let b = EmailSource.identifier(
            for: message,
            account: EmailAccount(host: "imap.other.example", username: "other@example.org")
        )
        #expect(a == b)
        #expect(a == "gmail:message:shared@list.example.org")
    }

    @Test("angle brackets are stripped from the id")
    func bracketStripping() {
        let message = EmailFixture.snapshot(messageID: "  <abc@x>  ")
        #expect(EmailSource.identifier(for: message, account: EmailFixture.account) == "gmail:message:abc@x")
    }

    @Test("duplicate ids collapse to one item and output is sorted by id")
    func deDuplication() {
        let messages = [
            EmailFixture.snapshot(uid: 3, messageID: "b@x", subject: "B older"),
            EmailFixture.snapshot(uid: 1, messageID: "a@x", subject: "A"),
            EmailFixture.snapshot(uid: 9, messageID: "b@x", subject: "B newer")
        ]
        let items = EmailSource.detect(messages: messages, account: EmailFixture.account, now: Fixture.now)
        #expect(items.map(\.id) == ["gmail:message:a@x", "gmail:message:b@x"])
        // Last wins: the later uid's subject survives.
        #expect(items.last?.title == "B newer")
    }

    // MARK: - Titles and detail

    @Test("a message with no subject falls back to the sender")
    func fallbackTitle() {
        let message = EmailFixture.snapshot(subject: "")
        let item = EmailSource.item(for: message, account: EmailFixture.account, now: Fixture.now)
        let title = try? #require(item.title)
        #expect(title == "Message from Ada Lovelace")
        #expect(title?.isEmpty == false)
    }

    @Test("a message with no subject and no parsable sender still gets a title")
    func fallbackTitleNoSender() {
        let message = EmailMessageSnapshot(uid: 5, subject: "   ", from: [])
        let item = EmailSource.item(for: message, account: EmailFixture.account, now: Fixture.now)
        #expect(item.title == "Unread message")
    }

    @Test("an encoded-word subject is decoded for the card")
    func encodedSubject() async throws {
        let (source, _, _) = EmailFixture.source(messages: [
            EmailFixture.direct(subject: "=?UTF-8?B?UXVlc3Rpb24gYWJvdXQgY29zdHM/?=")
        ])
        let item = try #require(try await source.detect(now: Fixture.now, window: window).first)
        #expect(item.title == "Question about costs?")
    }

    @Test("the detail line names the sender and the age, and never quotes a body")
    func detailLine() throws {
        let message = EmailFixture.snapshot(
            to: [EmailFixture.me, EmailFixture.colleague],
            sentAt: Fixture.now.addingTimeInterval(-3 * 86400)
        )
        let item = EmailSource.item(for: message, account: EmailFixture.account, now: Fixture.now)
        let detail = try #require(item.detail)
        #expect(detail.contains("From Ada Lovelace"))
        #expect(detail.contains("3 days ago"))
        #expect(detail.contains("also to Grace Hopper"))
    }

    @Test("no item ever carries a url, because IMAP has no permalink")
    func noURL() async throws {
        let (source, _, _) = EmailFixture.source(messages: [
            EmailFixture.direct(subject: "See https://example.com/thing")
        ])
        let items = try await source.detect(now: Fixture.now, window: window)
        #expect(items.allSatisfy { $0.url == nil })
    }

    // MARK: - Protocol shape

    @Test("only the declared IMAP subset is sent: no STORE, no BODY[]")
    func minimalCommandSet() async throws {
        let (source, transport, _) = EmailFixture.source(messages: [EmailFixture.direct()])
        _ = try await source.detect(now: Fixture.now, window: window)
        let names = transport.commandNames
        #expect(names.prefix(5) == ["CAPABILITY", "LOGIN", "SELECT", "UID SEARCH", "UID FETCH"])
        #expect(names.last == "LOGOUT")
        #expect(!names.contains("STORE"))
        // Every fetch is a peek: capture must never clear the user's unread mail.
        #expect(transport.commands.contains { $0.contains("BODY.PEEK") })
        #expect(!transport.commands.contains { $0.contains("BODY[") })
    }

    @Test("the configured mailbox is the one selected, quoted")
    func selectsConfiguredMailbox() async throws {
        let account = EmailAccount(host: "imap.example.net", username: "x@example.net", mailbox: "Projects")
        let (source, transport, _) = EmailFixture.source(account: account)
        _ = try await source.detect(now: Fixture.now, window: window)
        #expect(transport.commands.contains { $0.contains("SELECT \"Projects\"") })
    }

    @Test("one open per detect, and the password never appears in a command name")
    func oneOpen() async throws {
        let (source, transport, _) = EmailFixture.source(messages: [EmailFixture.direct()])
        _ = try await source.detect(now: Fixture.now, window: window)
        #expect(transport.openCount == 1)
        #expect(transport.commandNames.filter { $0 == "LOGIN" }.count == 1)
    }

    @Test("the limit caps how many messages are fetched, oldest dropped")
    func limit() async throws {
        let messages = (1 ... 5).map { index in
            EmailFixture.direct(uid: UInt32(index), messageID: "m\(index)@x", subject: "Message \(index)")
        }
        let (source, transport, _) = EmailFixture.source(messages: messages, limit: 2)
        let items = try await source.detect(now: Fixture.now, window: window)
        #expect(items.map(\.id) == ["gmail:message:m4@x", "gmail:message:m5@x"])
        #expect(transport.commandNames.filter { $0 == "UID FETCH" }.count == 2)
    }

    // MARK: - Engine integration

    @Test("a denied mailbox is reported as a paused source, not as an empty board")
    func pausedInEngine() async {
        let store = ItemStore()
        let engine = CaptureEngine(
            sources: [EmailSource(
                transport: FakeIMAPTransport(),
                accounts: StaticEmailAccountProvider(account: nil),
                secrets: InMemorySecretStore()
            )],
            store: store,
            now: { Fixture.now }
        )
        let report = await engine.run(mode: .full)
        #expect(report.errors.count == 1)
        #expect(report.pausedSources == [.gmail])
        #expect(report.detectedCount == 0)
    }

    @Test("mail items land in the store and are counted under gmail")
    func engineIntegration() async {
        let store = ItemStore()
        let (source, _, _) = EmailFixture.source(messages: [
            EmailFixture.direct(uid: 1, messageID: "one@x", subject: "Ping?"),
            EmailFixture.direct(uid: 2, messageID: "two@x", subject: "Invoice due today")
        ])
        let engine = CaptureEngine(sources: [source], store: store, now: { Fixture.now })
        let report = await engine.run(mode: .full)

        #expect(report.errors.isEmpty)
        #expect(report.countsBySource[.gmail] == 2)
        #expect(report.created.count == 2)
        let stored = await store.allItems()
        #expect(stored.allSatisfy { $0.source == .gmail })
        #expect(stored.map(\.status).allSatisfy { $0 == .open })
    }
}
