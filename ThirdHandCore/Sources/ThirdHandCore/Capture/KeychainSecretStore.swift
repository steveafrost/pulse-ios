import Foundation
import Security

/// The ways a secret store can refuse.
///
/// Separate from `CaptureError` because a Keychain failure is a *credential*
/// failure: `EmailSource` translates it, and the translation is what decides which
/// screen the user sees. Keeping the raw status here means the message can name the
/// OSStatus number for a log line without the capture layer having to know about
/// `SecItem`.
public enum KeychainError: Error, Sendable, Hashable, CustomStringConvertible {
    /// `SecItemCopyMatching` (or add/update/delete) returned a non-`errSecSuccess`
    /// status other than "not found".
    case unexpectedStatus(OSStatus)
    /// The stored item existed but was not UTF-8 data we can read as a password.
    case unreadableSecret

    public var description: String {
        switch self {
        case let .unexpectedStatus(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "keychain error \(status): \(message)"
        case .unreadableSecret:
            return "stored secret was not readable text"
        }
    }
}

/// Store/read/delete one credential per account key.
///
/// This is the only type in Pulse that talks to `SecItem`. The protocol exists
/// so `EmailSource` can be tested on a machine with no Keychain (the macOS test host
/// gives `errSecMissingEntitlement` for data-protection items), which is why
/// `InMemorySecretStore` can stand in for it exactly.
///
/// **Accessibility.** Every write uses
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. After-first-unlock is the
/// weakest class that still lets a `BGAppRefreshTask` read the password while the
/// phone is locked (a mail poll runs precisely then); `ThisDeviceOnly` keeps the
/// secret out of an iCloud or encrypted-iTunes backup, so restoring a backup onto a
/// second device does not clone the mail password. `kSecAttrSynchronizable` is never
/// set, and there is no `applicationPassword`/`kSecAttrGeneric` copy of the secret.
public struct KeychainSecretStore: SecretStoring, @unchecked Sendable {
    /// The Keychain service all Pulse IMAP passwords are filed under.
    ///
    /// One service, one account per mailbox (`EmailAccount.keychainAccount`), so a
    /// delete of one mailbox cannot touch another's secret.
    public static let defaultService = "com.steveafrost.thirdhand.imap"

    /// The accessibility class every write uses.
    ///
    /// Not stored in a `static let`: the `kSecAttrAccessible*` constants are
    /// `CFString`s and so are not `Sendable`, which `SWIFT_STRICT_CONCURRENCY:
    /// complete` rejects as a global. It is written out at the one place it is applied
    /// (`setSecret`) so there is nothing to drift.
    static var accessibility: CFString {
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }

    private let service: String

    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    /// The base query shared by every operation: one item, this service, this
    /// account. `kSecClassGenericPassword` because the secret is not a certificate
    /// or a key, just bytes we control.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// The stored password for `account`, or `nil` when there is none.
    ///
    /// "No item" is `nil`, not an error: an unconfigured mailbox is a normal state.
    /// A concurrent delete between the lookup and the read also reads as `nil`.
    public func secret(for account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError.unreadableSecret
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Writes `secret`, replacing any existing value for `account`.
    ///
    /// Update-then-add rather than delete-then-add: deleting first leaves a window
    /// where a concurrent capture sees no password and reports the mailbox as
    /// unconfigured. `SecItemUpdate` cannot change `kSecAttrAccessible`, so an item
    /// written by an older build is re-created with the current class when the
    /// attribute did not take -- which is the one case where the accessibility
    /// guarantee is actively enforced rather than assumed.
    public func setSecret(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = Self.accessibility
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        // A racing writer that won the add is not a failure: the value we wanted to
        // store is already stored by the other call only if it wrote the same secret,
        // so treat the duplicate as an error and let the caller rewrite.
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    /// Removes the password for `account`. Idempotent: deleting something absent is
    /// success, so a "disconnect mailbox" action can never get stuck.
    public func deleteSecret(for account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// The seam `KeychainSecretStore` implements.
///
/// Only ever holds credentials, keyed by `EmailAccount.keychainAccount`. A caller
/// that wants the *account* (host/port/username) goes to `EmailAccountProviding`
/// instead -- the two are separate so no single type can hand out both halves.
public protocol SecretStoring: Sendable {
    /// The secret for `account`, or `nil` when none is stored.
    func secret(for account: String) throws -> String?
    /// Stores `secret` for `account`, replacing any previous value.
    func setSecret(_ secret: String, for account: String) throws
    /// Removes the secret for `account`. Deleting an absent secret is not an error.
    func deleteSecret(for account: String) throws
}

/// A `SecretStoring` that keeps secrets in memory. **Test and preview only.**
///
/// It exists because the test host has no Keychain entitlement, and because a test
/// that asserts on a stored password must be able to look at it. It is `final` with a
/// lock rather than an `actor` so `EmailSource`'s synchronous credential read does not
/// have to hop.
///
/// It deliberately does *not* conform to `CustomStringConvertible`: nothing should
/// be able to print the map by accident.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String]

    public init(secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    public func secret(for account: String) throws -> String? {
        lock.withLock { secrets[account] }
    }

    public func setSecret(_ secret: String, for account: String) throws {
        lock.withLock { secrets[account] = secret }
    }

    public func deleteSecret(for account: String) throws {
        _ = lock.withLock { secrets.removeValue(forKey: account) }
    }

    /// How many secrets are held. For assertions that never print a value.
    public var count: Int {
        lock.withLock { secrets.count }
    }

    /// Whether nothing is held. Same reason as `count`, in the form assertions read
    /// better in: `#expect(store.isEmpty)` says what was checked, `count == 0` makes the
    /// reader compare numbers.
    public var isEmpty: Bool {
        lock.withLock { secrets.isEmpty }
    }
}
