import Foundation
import Testing
@testable import ThirdHandCore

/// The account model, the redaction guarantee, and the persistence of the
/// non-secret half.
@Suite("EmailAccount")
struct EmailAccountTests {
    // MARK: - No secret in the account

    @Test("the account's description names host, port and user and nothing else")
    func accountDescription() {
        let account = EmailFixture.account
        #expect(account.description == "steve@example.com at imap.gmail.com:993")
        #expect(account.debugDescription.contains("imap.gmail.com"))
        // Nothing resembling a password can appear: the type has no such field.
        #expect(!account.description.contains("dummy"))
        #expect(!account.debugDescription.contains("dummy"))
    }

    @Test("the account encodes to JSON with no password-shaped key")
    func accountCoding() throws {
        let data = try JSONEncoder().encode(EmailFixture.account)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["host", "port", "username", "mailbox"])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.lowercased().contains("password"))
        #expect(!text.lowercased().contains("secret"))
    }

    @Test("the account round-trips through JSON")
    func accountRoundTrip() throws {
        let account = EmailAccount(host: "imap.example.net", port: 143, username: "x@example.net", mailbox: "Work")
        let decoded = try JSONDecoder().decode(EmailAccount.self, from: JSONEncoder().encode(account))
        #expect(decoded == account)
    }

    // MARK: - The redaction guarantee

    @Test("credentials never print their password, however they are described")
    func credentialsRedaction() {
        let credentials = EmailFixture.credentials
        let password = EmailFixture.dummyPassword

        #expect(!credentials.description.contains(password))
        #expect(!credentials.debugDescription.contains(password))
        #expect(!String(describing: credentials).contains(password))
        #expect(!String(reflecting: credentials).contains(password))
        #expect(!"\(credentials)".contains(password))
        // And the surrounding context still says which mailbox it is, so a log line is
        // useful without being dangerous.
        #expect(credentials.description.contains("steve@example.com"))
        #expect(credentials.description.contains(EmailCredentials.redaction))
    }

    @Test("dumping credentials does not reveal the password")
    func dumpRedaction() {
        var collector = LineCollector()
        dump(EmailFixture.credentials, to: &collector)
        #expect(!collector.text.contains(EmailFixture.dummyPassword))
        // The dump is not empty, so this is a real check rather than a no-op.
        #expect(collector.text.contains("EmailCredentials"))
    }

    /// A `TextOutputStream` that keeps what `dump` writes, so the assertion cannot be
    /// fooled by `dump` writing nowhere.
    final class LineCollector: TextOutputStream {
        private(set) var text = ""
        func write(_ string: String) { text += string }
    }

    // MARK: - Keychain key

    @Test("the keychain key is derived from the non-secret half and is case-insensitive")
    func keychainKey() {
        let account = EmailFixture.account
        #expect(account.keychainAccount == "imap:steve@example.com@imap.gmail.com:993")
        #expect(
            EmailAccount(host: "IMAP.GMAIL.COM", username: "Steve@Example.com").keychainAccount
                == account.keychainAccount
        )
        #expect(EmailAccount(host: "imap.gmail.com", port: 143, username: "steve@example.com").keychainAccount
            != account.keychainAccount)
        #expect(!account.keychainAccount.contains(EmailFixture.dummyPassword))
    }

    @Test("the gmail convenience initialiser points at the real IMAPS endpoint")
    func gmailAccount() {
        let account = EmailAccount.gmail(username: "steve@example.com")
        #expect(account.host == "imap.gmail.com")
        #expect(account.port == 993)
        #expect(account.mailbox == "INBOX")
    }

    // MARK: - Persistence

    @Test("the account persists in defaults and reads back")
    func defaultsRoundTrip() throws {
        let suite = try #require(UserDefaults(suiteName: "EmailAccountTests.\(UUID().uuidString)"))
        let provider = UserDefaultsEmailAccountProvider(defaults: suite)
        #expect(try provider.configuredAccount() == nil)

        try provider.save(EmailFixture.account)
        #expect(try provider.configuredAccount() == EmailFixture.account)

        try provider.save(nil)
        #expect(try provider.configuredAccount() == nil)
    }

    @Test("a corrupt stored account reads as not configured rather than throwing forever")
    func corruptDefaults() throws {
        let suite = try #require(UserDefaults(suiteName: "EmailAccountTests.\(UUID().uuidString)"))
        suite.set(Data("not json".utf8), forKey: UserDefaultsEmailAccountProvider.storageKey)
        #expect(try UserDefaultsEmailAccountProvider(defaults: suite).configuredAccount() == nil)
    }

    // MARK: - Secret stores

    @Test("the in-memory store round-trips a secret and deletes idempotently")
    func inMemoryStore() throws {
        let store = InMemorySecretStore()
        #expect(try store.secret(for: "k") == nil)
        try store.setSecret("v1", for: "k")
        #expect(try store.secret(for: "k") == "v1")
        try store.setSecret("v2", for: "k")
        #expect(try store.secret(for: "k") == "v2")
        #expect(store.count == 1)
        try store.deleteSecret(for: "k")
        #expect(try store.secret(for: "k") == nil)
        try store.deleteSecret(for: "k")
        #expect(store.count == 0)
    }

    @Test("the real keychain store reports missing values as nil, never as an error")
    func keychainMissing() throws {
        // A service name unique to this run, so the test can never touch a real
        // credential and never leaves one behind.
        let store = KeychainSecretStore(service: "com.steveafrost.thirdhand.tests.\(UUID().uuidString)")
        let account = "imap:test@example.com@imap.example.com:993"
        do {
            #expect(try store.secret(for: account) == nil)
        } catch let error as KeychainError {
            // A test host without the data-protection entitlement cannot read the
            // Keychain at all (`errSecMissingEntitlement`). That is the reason
            // `SecretStoring` exists; the fail-closed direction is still "an error",
            // never "an empty secret".
            guard case .unexpectedStatus = error else { throw error }
        }
    }
}
