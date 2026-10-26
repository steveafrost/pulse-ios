import Foundation
import ThirdHandCore

/// The whole state of the Email account screen, as a value.
///
/// Kept out of the view for the same reason `BoardViewModel` is: every sentence,
/// every enabled/disabled decision and every "is this a valid address" answer is
/// then assertable in `ThirdHandTests` without instantiating SwiftUI. The view is
/// left with layout and nothing else.
///
/// **The password is never held here.** This type carries the *non-secret* half of
/// the connection (`EmailAccount`) plus a `hasSecret` flag that asks the Keychain
/// one yes/no question. It cannot leak a password because it never has one; the
/// draft password lives only in the view's `@State` and is handed straight to the
/// Keychain on save.
@MainActor
@Observable
public final class EmailAccountModel {
    /// What the screen is showing for the account, in the account's own terms.
    public enum Phase: Equatable {
        /// No mailbox configured — the screen offers a form.
        case notConnected
        /// A mailbox is configured and a password is stored.
        case connected(EmailAccount)
        /// A mailbox is configured but the Keychain has no password for it. This is
        /// the state a user lands in after restoring a backup: the address survived,
        /// the secret did not. It is *not* "not connected" — the honest report is
        /// that a mailbox is set up but cannot sign in.
        case needsPassword(EmailAccount)
    }

    /// What the email source is doing right now, as the board's chip reports it.
    ///
    /// Deliberately fewer states than the capture engine has: the settings screen
    /// answers "can this work?", not "what happened at 09:14:03".
    public enum Status: Equatable {
        case notConnected
        case checking
        case unread(Int)
        case failed(String)
    }

    public private(set) var phase: Phase
    public private(set) var status: Status
    /// The field values the form edits. Only meaningful in the form.
    public var draftAddress: String = ""
    public var draftHost: String = EmailAccount.Provider.gmail.imapHost ?? ""
    /// Which provider the user picked. Drives the host field and the password
    /// guidance; `.other` leaves the host to the user.
    public var draftProvider: EmailAccount.Provider = .gmail {
        didSet {
            // Switching provider replaces the host with that provider's endpoint, so
            // the common path needs no typing and cannot drift out of sync with the
            // guidance underneath. `.other` deliberately keeps whatever was typed.
            if draftProvider != .other, let host = draftProvider.imapHost {
                draftHost = host
            }
        }
    }

    /// Set when a save attempt failed, for an inline message under the form.
    public private(set) var saveError: String?

    private let accounts: any EmailAccountProviding
    private let accountsWriter: EmailAccountSaving?
    private let secrets: any SecretStoring

    public init(
        accounts: any EmailAccountProviding,
        accountsWriter: EmailAccountSaving?,
        secrets: any SecretStoring
    ) {
        self.accounts = accounts
        self.accountsWriter = accountsWriter
        self.secrets = secrets

        let configured = try? accounts.configuredAccount()
        let maybeAccount = configured
        if let account = maybeAccount {
            let hasSecret = (try? secrets.secret(for: account.keychainAccount))
            phase = hasSecret == nil ? .needsPassword(account) : .connected(account)
            status = .notConnected
            draftAddress = account.username
            draftHost = account.host
            // Show the picker on the provider that owns the stored host, so an
            // existing Gmail account does not open showing iCloud guidance.
            draftProvider = EmailAccount.Provider.matching(host: account.host) ?? .other
        } else {
            phase = .notConnected
            status = .notConnected
        }
    }

    // MARK: Form validity

    /// Whether the address looks like an address. Deliberately permissive — one `@`
    /// with something either side — because a stricter regex rejects valid addresses
    /// and this is a mail login, not a signup form.
    public var isAddressValid: Bool {
        let trimmed = draftAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@"), !trimmed.hasPrefix("@") else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !trimmed.contains(" ")
    }

    /// Whether the host looks like a hostname. Deliberately permissive.
    public var isHostValid: Bool {
        let trimmed = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains(" ") && trimmed.contains(".")
    }

    /// Save is enabled only when both non-secret fields are plausible *and* a
    /// password was typed. A save with an empty password would put the account in
    /// `.needsPassword`, which is a state the user did not ask for.
    public func canSave(password: String) -> Bool {
        isAddressValid && isHostValid && !password.isEmpty
    }

    // MARK: Actions

    /// Persists the account and its password.
    ///
    /// Returns `true` on success. The password goes straight to the Keychain and is
    /// never stored on this type, never included in `saveError`, and never written
    /// to the account's `description` (which `EmailAccount` already guarantees).
    @discardableResult
    public func save(password: String) -> Bool {
        saveError = nil
        let address = draftAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = EmailAccount(host: host, username: address)

        do {
            if let accountsWriter {
                try accountsWriter.save(account)
            }
            try secrets.setSecret(password, for: account.keychainAccount)
            phase = .connected(account)
            status = .notConnected
            return true
        } catch {
            // The message names the *operation*, never the value. `String(describing:)`
            // on a Keychain error carries no secret, and the password is not in scope.
            saveError = "Couldn't save the mailbox. \(error.localizedDescription)"
            return false
        }
    }

    /// Removes the account and its secret, returning to `.notConnected`.
    public func disconnect() {
        saveError = nil
        if case let .connected(account) = phase {
            try? secrets.deleteSecret(for: account.keychainAccount)
        } else if case let .needsPassword(account) = phase {
            try? secrets.deleteSecret(for: account.keychainAccount)
        }
        if let accountsWriter {
            try? accountsWriter.save(nil)
        }
        phase = .notConnected
        status = .notConnected
        draftAddress = ""
        draftHost = EmailAccount.gmail(username: "").host
    }

    // MARK: Capture feedback

    /// Folds one capture pass into the state this screen reports.
    ///
    /// Without this the screen tells the truth once, at construction, and then lies
    /// forever: `status` was only ever set in `init`, so a mailbox that had just
    /// signed in and found twelve unread messages still read "Not connected", and a
    /// refused app password still read like a mailbox nobody had set up. Nothing fed
    /// the pass back in, even though the pass is the only thing that knows whether
    /// the mailbox works.
    ///
    /// `phase` wins over the transport in one case: a mailbox whose Keychain secret
    /// is gone cannot have checked anything, and `statusLine` already renders
    /// "Password needed" for it — a transport status would only contradict that.
    public func apply(_ outcome: CaptureOutcome) {
        if case .needsPassword = phase {
            return
        }
        guard case .connected = phase else {
            // No mailbox configured. The pass failing is expected and not the user's
            // mail server's fault, so it must not read as a broken mailbox.
            status = .notConnected
            return
        }
        if let failure = outcome.failures.first(where: { $0.identity == .email }) {
            status = .failed(failure.message)
        } else {
            status = .unread(outcome.emailUnreadCount)
        }
    }

    // MARK: Copy

    /// The account-state line the source chip and this screen both show.
    ///
    /// The three cases are the brief's three, phrased as facts: "Not connected" is a
    /// state, "Checking…" is an action in progress, "12 unread" is a count. None of
    /// them is a shrug and none of them is optimistic.
    /// The phase can override the transport status, and it must: a mailbox that is
    /// configured but has lost its Keychain secret is *not* "Not connected", and
    /// saying so would send the user to a form that is already filled in.
    public var statusLine: String {
        if case .needsPassword = phase {
            return "Password needed"
        }
        return switch status {
        case .notConnected: "Not connected"
        case .checking: "Checking…"
        case let .unread(count): Plural.count(count, "unread message")
        case .failed: "Couldn't check"
        }
    }

    /// The VoiceOver sentence for the status, which spells out what the short line
    /// only implies.
    public var statusAccessibility: String {
        if case let .needsPassword(account) = phase {
            return "\(account.username) is set up, but its password is not on this device. Enter it again to check mail."
        }
        return switch status {
        case .notConnected:
            "Email is not connected. Add a mailbox in Settings to see mail on your board."
        case .checking:
            "Checking your mailbox now"
        case let .unread(count):
            "\(Plural.count(count, "unread message")) in your mailbox"
        case let .failed(reason):
            "Couldn't check your mailbox. \(reason)"
        }
    }

    /// The short, truthful rationale shown under the password field.
    ///
    /// It says what is stored, where, and what is *not* done — three facts a security
    /// copy block usually omits. It does not promise encryption-in-transit beyond
    /// what is true: the transport is IMAPS (TLS from the first byte), which is.
    /// The noun the provider itself uses for the credential: "app-specific password"
    /// is Gmail's phrase and reads as wrong under an iCloud account, which simply
    /// calls it an app password. The rationale below is the only place the phrase
    /// reaches the screen, so it takes the provider as a parameter rather than
    /// hardcoding one vendor's vocabulary for everybody.
    public static func passwordRationale(for provider: EmailAccount.Provider) -> String {
        let noun = provider.passwordNoun
        return """
        Your \(noun) is kept in the iOS Keychain on this device only. It is never \
        shown again, never written to a log, and never leaves the phone except to \
        sign in to your mail server over an encrypted connection.
        """
    }

    /// Kept as the Gmail-flavoured default for callers that have no provider in hand
    /// (the rationale is also used by a preview and by the Settings row summary).
    public static let passwordRationale = passwordRationale(for: .gmail)

    /// Provider-agnostic fallback, used only where a provider has no specific
    /// guidance. The per-provider text lives on `EmailAccount.Provider`, next to the
    /// host it belongs to, so the two cannot drift apart.
    public static let appPasswordHint = """
    Most mail providers need an app-specific password rather than your normal one, \
    especially when two-step verification is on.
    """
}

/// Writing the non-secret half of an account.
///
/// Declared here rather than in `ThirdHandCore` because the core agent owns that
/// module right now; `UserDefaultsEmailAccountProvider` already has a `save(_:)`
/// method with exactly this signature, so this conformance is a one-line adapter
/// and the settings screen can be built and tested against it today.
@MainActor
public protocol EmailAccountSaving {
    func save(_ account: EmailAccount?) throws
}

extension UserDefaultsEmailAccountProvider: EmailAccountSaving {}
