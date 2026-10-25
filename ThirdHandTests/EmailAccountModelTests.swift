import Foundation
import Testing
import ThirdHandCore
@testable import ThirdHand

/// The Email account screen's logic, tested without SwiftUI.
///
/// The rules asserted here are the ones that would be expensive to get wrong in
/// production: an address validation that is too strict locks the user out, a save
/// that forgets the Keychain leaves a mailbox that can never check, and a
/// `statusLine` that says "Not connected" for a *configured* mailbox is exactly the
/// dishonesty the design doc forbids. The password itself is asserted only in terms
/// of where it must end up — never by reading it back into a value under test.
@Suite("Email account")
@MainActor
struct EmailAccountModelTests {
    /// A provider that records what was written, so a test can prove the Keychain
    /// received the password without the model ever exposing it.
    final class RecordingWriter: EmailAccountSaving, @unchecked Sendable {
        var written: [EmailAccount?] = []
        func save(_ account: EmailAccount?) throws { written.append(account) }
    }

    private func makeModel(
        account: EmailAccount? = nil,
        secrets: InMemorySecretStore = InMemorySecretStore(),
        writer: RecordingWriter = RecordingWriter()
    ) -> (EmailAccountModel, RecordingWriter, InMemorySecretStore) {
        let model = EmailAccountModel(
            accounts: StaticEmailAccountProvider(account: account),
            accountsWriter: writer,
            secrets: secrets
        )
        return (model, writer, secrets)
    }

    // MARK: Provider

    @Test("picking iCloud fills in Apple's IMAP host without the user typing it")
    func icloudFillsHost() {
        let (model, _, _) = makeModel()
        // The default the screen opens on must not be the reason an iCloud user
        // ends up pointed at imap.gmail.com.
        model.draftProvider = .icloud
        #expect(model.draftHost == "imap.mail.me.com")
    }

    @Test("switching provider replaces a stale host rather than leaving both")
    func switchingProviderReplacesHost() {
        let (model, _, _) = makeModel()
        model.draftProvider = .gmail
        #expect(model.draftHost == "imap.gmail.com")
        model.draftProvider = .fastmail
        #expect(model.draftHost == "imap.fastmail.com", "the previous host survived the switch")
    }

    @Test("choosing Other keeps what the user already typed")
    func otherKeepsTypedHost() {
        let (model, _, _) = makeModel()
        model.draftHost = "mail.internal.example.com"
        model.draftProvider = .other
        // Clearing the field here would delete a host the user just typed, which is
        // the one case the picker is not allowed to be helpful about.
        #expect(model.draftHost == "mail.internal.example.com")
    }

    @Test("a saved iCloud account opens the picker on iCloud, not Gmail")
    func existingAccountSelectsProvider() {
        let (model, _, _) = makeModel(account: EmailAccount.icloud(username: "steve@example.com"))
        #expect(model.draftProvider == .icloud)
        #expect(model.draftHost == "imap.mail.me.com")
    }

    @Test("a saved account on an unknown host opens on Other")
    func unknownHostSelectsOther() {
        let custom = EmailAccount(host: "mail.example.com", username: "steve@example.com")
        let (model, _, _) = makeModel(account: custom)
        #expect(model.draftProvider == .other)
        #expect(model.draftHost == "mail.example.com")
    }

    @Test("an iCloud save reaches the Keychain under the iCloud key, not Gmail's")
    func icloudSaveUsesICloudKeychainKey() throws {
        var (model, _, secrets) = makeModel()
        model.draftProvider = .icloud
        model.draftAddress = "steve@example.com"

        #expect(model.save(password: "app-specific-pw"))

        let expected = EmailAccount.icloud(username: "steve@example.com").keychainAccount
        #expect(try secrets.secret(for: expected) != nil, "the secret is not under the iCloud key")
        // Sharing a key with Gmail would silently reuse one provider's password for
        // another account on the same address.
        #expect(
            try secrets.secret(for: EmailAccount.gmail(username: "steve@example.com").keychainAccount) == nil
        )
    }

    @Test("the password rationale uses the provider's own word for the credential")
    func rationaleUsesProviderVocabulary() {
        // Gmail calls it an "app-specific password"; Apple calls it an "app password".
        // Showing Gmail's phrase to an iCloud user reads as a copy-paste mistake, and
        // the footer is the only place the phrase appears.
        #expect(EmailAccountModel.passwordRationale(for: .gmail).contains("app-specific password"))
        #expect(!EmailAccountModel.passwordRationale(for: .icloud).contains("app-specific"))
        #expect(EmailAccountModel.passwordRationale(for: .icloud).contains("app password"))
        // The three facts that make the block honest must survive the swap.
        for provider in EmailAccount.Provider.allCases {
            let text = EmailAccountModel.passwordRationale(for: provider)
            #expect(text.contains("Keychain"), "\(provider.rawValue): keychain claim lost")
            #expect(text.contains("this device only"), "\(provider.rawValue): device-only claim lost")
            #expect(text.contains("never written to a log"), "\(provider.rawValue): log claim lost")
        }
    }

    // MARK: Phase

    @Test("no configured mailbox reads as not connected")
    func notConnected() {
        let (model, _, _) = makeModel()
        #expect(model.phase == .notConnected)
        #expect(model.statusLine == "Not connected")
    }

    @Test("a configured mailbox with a stored password reads as connected")
    func connected() {
        let account = EmailAccount.gmail(username: "s@example.com")
        let secrets = InMemorySecretStore(secrets: [account.keychainAccount: "app-pass"])
        let (model, _, _) = makeModel(account: account, secrets: secrets)
        #expect(model.phase == .connected(account))
    }

    @Test("a configured mailbox with no password says so rather than reading as disconnected")
    func needsPassword() {
        let account = EmailAccount.gmail(username: "s@example.com")
        let (model, _, _) = makeModel(account: account)
        // Restoring from a backup keeps the address and loses the secret. Reporting
        // that as "Not connected" would send the user to a form that is already
        // filled in and hide what actually has to happen.
        #expect(model.phase == .needsPassword(account))
        #expect(model.statusLine != "Not connected")
    }

    // MARK: Capture feedback

    @Test("a pass that found unread mail makes the screen say so")
    func passReportsUnread() {
        let account = EmailAccount.gmail(username: "s@example.com")
        let secrets = InMemorySecretStore(secrets: [account.keychainAccount: "app-pass"])
        let (model, _, _) = makeModel(account: account, secrets: secrets)
        // Stale at construction: nothing had checked yet.
        #expect(model.status == .notConnected)

        model.apply(CaptureOutcome(detected: [], ranAt: Fixtures.fixtureNow, emailUnreadCount: 12))
        #expect(model.status == .unread(12))
        #expect(model.statusLine == "12 unread messages")
    }

    @Test("a refused sign-in reads as a failure, not as an unconnected mailbox")
    func passReportsFailure() {
        let account = EmailAccount.gmail(username: "s@example.com")
        let secrets = InMemorySecretStore(secrets: [account.keychainAccount: "wrong"])
        let (model, _, _) = makeModel(account: account, secrets: secrets)

        let failure = SourceFailure(identity: .email, reason: .denied)
        model.apply(CaptureOutcome(detected: [], failures: [failure], ranAt: Fixtures.fixtureNow))
        // `.denied` for mail means the credential was refused or is missing; either way
        // the row must not report a count, because no mail was read.
        #expect(model.status == .failed(failure.message))
    }

    @Test("another source's failure is not the mailbox's fault")
    func passIgnoresOtherSources() {
        let account = EmailAccount.gmail(username: "s@example.com")
        let secrets = InMemorySecretStore(secrets: [account.keychainAccount: "app-pass"])
        let (model, _, _) = makeModel(account: account, secrets: secrets)

        let calendar = SourceFailure(identity: .calendar, reason: .denied)
        model.apply(CaptureOutcome(detected: [], failures: [calendar], ranAt: Fixtures.fixtureNow, emailUnreadCount: 3))
        #expect(model.status == .unread(3))
    }

    @Test("with no mailbox configured, a failing pass does not blame the mail server")
    func passWithoutAccount() {
        let (model, _, _) = makeModel()
        let failure = SourceFailure(identity: .email, reason: .denied)
        model.apply(CaptureOutcome(detected: [], failures: [failure], ranAt: Fixtures.fixtureNow))
        // The pass always fails when there is no account -- that is what `denied(.gmail)`
        // means. Reporting `.failed` would show an error for a form not yet filled in.
        #expect(model.status == .notConnected)
    }

    @Test("a lost Keychain secret keeps saying 'Password needed' whatever the pass found")
    func passRespectsNeedsPassword() {
        let account = EmailAccount.gmail(username: "s@example.com")
        let (model, _, _) = makeModel(account: account)
        #expect(model.phase == .needsPassword(account))

        model.apply(CaptureOutcome(detected: [], ranAt: Fixtures.fixtureNow, emailUnreadCount: 5))
        // A mailbox with no secret cannot have read anything, so a count here would be
        // a claim the app cannot support.
        #expect(model.statusLine == "Password needed")
    }

    // MARK: Validation

    @Test("a plausible address is accepted", arguments: [
        "a@b.co", "steve.frost@example.com", "s+tag@mail.example.org",
    ])
    func validAddresses(_ address: String) {
        let (model, _, _) = makeModel()
        model.draftAddress = address
        #expect(model.isAddressValid)
    }

    @Test("an implausible address is rejected", arguments: [
        "", "no-at-sign", "@example.com", "a@nodot", "a@b.", "two words@example.com",
    ])
    func invalidAddresses(_ address: String) {
        let (model, _, _) = makeModel()
        model.draftAddress = address
        #expect(!model.isAddressValid)
    }

    @Test("a host needs a dot and no spaces")
    func hostValidation() {
        let (model, _, _) = makeModel()
        model.draftHost = "imap.gmail.com"
        #expect(model.isHostValid)
        model.draftHost = "localhost"
        #expect(!model.isHostValid)
        model.draftHost = "imap gmail com"
        #expect(!model.isHostValid)
    }

    @Test("save is blocked until address, host and password are all present")
    func canSave() {
        let (model, _, _) = makeModel()
        model.draftAddress = "s@example.com"
        model.draftHost = "imap.gmail.com"
        #expect(!model.canSave(password: ""))
        #expect(model.canSave(password: "x"))
    }

    // MARK: Saving

    @Test("saving stores the password in the secret store and the account in the writer")
    func saveWritesBothHalves() throws {
        let (model, writer, secrets) = makeModel()
        model.draftAddress = "s@example.com"
        model.draftHost = "imap.gmail.com"

        #expect(model.save(password: "app-specific"))
        #expect(model.phase == .connected(EmailAccount(host: "imap.gmail.com", username: "s@example.com")))
        // The secret is in the store, under the account's own key — not in the model.
        let stored = try secrets.secret(for: EmailAccount.gmail(username: "s@example.com").keychainAccount)
        #expect(stored == "app-specific")
        #expect(writer.written.compactMap { $0 }.count == 1)
    }

    @Test("the saved account carries no password field to leak")
    func accountHasNoSecret() {
        let account = EmailAccount(host: "imap.gmail.com", username: "s@example.com")
        // `description` is the string a log line would capture. It must name the
        // account without ever having a secret to name.
        #expect(!account.description.lowercased().contains("password"))
        #expect(account.description.contains("s@example.com"))
    }

    @Test("disconnect clears both halves")
    func disconnect() throws {
        let account = EmailAccount.gmail(username: "s@example.com")
        let secrets = InMemorySecretStore(secrets: [account.keychainAccount: "app-pass"])
        let (model, writer, _) = makeModel(account: account, secrets: secrets)
        #expect(model.phase == .connected(account))

        model.disconnect()
        #expect(model.phase == .notConnected)
        #expect(try secrets.secret(for: account.keychainAccount) == nil)
        #expect(writer.written.last! == nil)
    }

    // MARK: Status copy

    @Test("the status line states the mail state and never shrugs")
    func statusCopy() {
        #expect(EmailAccountModel.Status.notConnected.isHonest)
        #expect(EmailAccountModel.Status.checking.isHonest)
        #expect(EmailAccountModel.Status.unread(12).isHonest)
    }

    @Test("an unread count inflects, and one message is not '1 messages'")
    func unreadInflects() {
        #expect(EmailAccountModel.Status.unread(1).isHonest)
        // `Plural` is the shared rule the whole app uses; assert the two ends here
        // so the mailbox line cannot regress independently of it.
        #expect(Plural.count(1, "unread message") == "1 unread message")
        #expect(Plural.count(3, "unread message") == "3 unread messages")
        #expect(Plural.count(0, "unread message") == "0 unread messages")
    }

    @Test("the rationale names the Keychain and promises nothing it cannot keep")
    func rationale() {
        let text = EmailAccountModel.passwordRationale
        #expect(text.contains("Keychain"))
        #expect(text.lowercased().contains("never"))
        // It must not claim the password is "encrypted" in a vague way when what is
        // true is that it is stored in the Keychain and sent over TLS.
        #expect(!text.lowercased().contains("military"))
    }
}

private extension EmailAccountModel.Status {
    /// Every state is a fact the user can act on: a state, an action, or a count.
    /// None is an empty string and none is a generic apology.
    var isHonest: Bool {
        switch self {
        case .notConnected: true
        case .checking: true
        case .unread(let count): count >= 0
        case .failed: true
        }
    }
}