import Foundation
@testable import ThirdHandCore

/// Fixtures for mail detection.
///
/// Every password here is an obvious dummy (`"app-specific-dummy"`), used only in
/// test code, and never a value anyone could mistake for a real credential. The
/// account fixture is a Gmail address at the real IMAP host so the Keychain key and
/// the classifier's self-address matching exercise the production shape.
enum EmailFixture {
    static let account = EmailAccount(
        host: "imap.gmail.com",
        username: "steve@example.com"
    )

    static let dummyPassword = "app-specific-dummy"

    static var credentials: EmailCredentials {
        EmailCredentials(account: account, password: dummyPassword)
    }

    static let sender = EmailAddress(name: "Ada Lovelace", address: "ada@example.org")
    static let colleague = EmailAddress(name: "Grace Hopper", address: "grace@example.org")
    static let me = EmailAddress(name: "Steve Frost", address: "steve@example.com")

    /// A message addressed only to the user, with no reply markers.
    static func direct(
        uid: UInt32 = 101,
        messageID: String? = "direct-101@mail.example.org",
        subject: String = "Quick question",
        from: [EmailAddress]? = nil,
        to: [EmailAddress]? = nil,
        cc: [EmailAddress] = [],
        date: String? = "Fri, 23 Oct 2026 18:04:11 +0000",
        inReplyTo: String? = nil,
        references: String? = nil
    ) -> FakeIMAPTransport.ScriptedMessage {
        FakeIMAPTransport.ScriptedMessage(
            uid: uid,
            messageID: messageID,
            subject: subject,
            from: from ?? [sender],
            to: to ?? [me],
            cc: cc,
            date: date,
            inReplyTo: inReplyTo,
            references: references
        )
    }

    /// The same message as a snapshot, for the pure rule tests.
    static func snapshot(
        uid: UInt32 = 101,
        messageID: String? = "direct-101@mail.example.org",
        subject: String = "Quick question",
        from: [EmailAddress]? = nil,
        to: [EmailAddress]? = nil,
        cc: [EmailAddress] = [],
        sentAt: Date? = nil,
        isReply: Bool = false
    ) -> EmailMessageSnapshot {
        EmailMessageSnapshot(
            uid: uid,
            messageID: messageID,
            subject: subject,
            from: from ?? [sender],
            to: to ?? [me],
            cc: cc,
            sentAt: sentAt,
            receivedAt: nil,
            isReply: isReply
        )
    }

    /// A source wired to a fake server, an in-memory secret store and a static
    /// account, which is the whole configuration a test needs.
    static func source(
        messages: [FakeIMAPTransport.ScriptedMessage] = [],
        behaviour: FakeIMAPTransport.Behaviour = .serving,
        account: EmailAccount? = EmailFixture.account,
        secret: String? = EmailFixture.dummyPassword,
        limit: Int = IMAPClient.defaultLimit
    ) -> (source: EmailSource, transport: FakeIMAPTransport, secrets: InMemorySecretStore) {
        let transport = FakeIMAPTransport(messages: messages, behaviour: behaviour)
        let secrets = InMemorySecretStore(
            secrets: {
                guard let account, let secret else { return [:] }
                return [account.keychainAccount: secret]
            }()
        )
        let source = EmailSource(
            transport: transport,
            accounts: StaticEmailAccountProvider(account: account),
            secrets: secrets,
            limit: limit
        )
        return (source, transport, secrets)
    }

    /// A provider that always throws, for the "settings unreadable" path.
    struct ThrowingAccountProvider: EmailAccountProviding {
        func configuredAccount() throws -> EmailAccount? {
            throw CaptureError.underlying("defaults are corrupt")
        }
    }

    /// A secret store that always throws, for the "Keychain unreadable" path.
    struct ThrowingSecretStore: SecretStoring {
        func secret(for account: String) throws -> String? {
            throw KeychainError.unexpectedStatus(-34018)
        }
        func setSecret(_ secret: String, for account: String) throws {}
        func deleteSecret(for account: String) throws {}
    }
}
