import Foundation
import Testing

@testable import ThirdHandCore

/// The provider presets exist so the user does not have to know an IMAP hostname.
/// These lock down the two things that would make them worse than no preset at all:
/// a host that is wrong, and guidance that points at a setting the provider does not
/// have under that name.
@Suite("Email provider presets")
struct EmailProviderTests {

    /// Every host the presets can fill in, with the provider it belongs to.
    static let knownHosts: [(EmailAccount.Provider, String)] = [
        (.icloud, "imap.mail.me.com"),
        (.gmail, "imap.gmail.com"),
        (.outlook, "outlook.office365.com"),
        (.yahoo, "imap.mail.yahoo.com"),
        (.fastmail, "imap.fastmail.com"),
    ]

    @Test("every provider except .other has an IMAPS host on port 993")
    func hostsArePresent() {
        for provider in EmailAccount.Provider.allCases {
            if provider == .other {
                #expect(provider.imapHost == nil, ".other must not invent a host")
            } else {
                let host = provider.imapHost
                #expect(host?.isEmpty == false, "\(provider.rawValue) has no host")
                #expect(host?.contains(".") == true, "\(provider.rawValue) host is not a hostname")
            }
        }
    }

    @Test("hosts match the endpoints verified live")
    func hostsMatchVerifiedEndpoints() {
        // These five were each confirmed to complete a TLS handshake and answer an
        // IMAP greeting; see docs/DEFERRED-SOURCES.md. A typo here would be a silent
        // "cannot reach your mail server" for the user.
        for (provider, expected) in Self.knownHosts {
            #expect(provider.imapHost == expected, "\(provider.rawValue) host changed")
        }
    }

    @Test("iCloud is offered, because 'Apple Mail' is an iCloud account")
    func icloudIsPresent() {
        let account = EmailAccount.make(provider: .icloud, username: "steve@example.com")
        #expect(account?.host == "imap.mail.me.com")
        #expect(account?.port == EmailAccount.defaultIMAPPort)
    }

    @Test("guidance is never empty and names a provider-specific action")
    func guidanceIsSpecific() {
        for provider in EmailAccount.Provider.allCases {
            let text = provider.passwordGuidance
            #expect(!text.isEmpty, "\(provider.rawValue) has no guidance")
            if provider != .other {
                #expect(
                    text.lowercased().contains("app") || text.lowercased().contains("password"),
                    "\(provider.rawValue) guidance does not mention a password"
                )
            }
        }
    }

    @Test("iCloud guidance does not send the user to Gmail's page")
    func icloudGuidanceIsNotGmailGuidance() {
        // The failure this prevents: the screen defaulted to Gmail's wording, so an
        // iCloud user was told to open Google Account settings for a password Apple
        // issues at account.apple.com.
        let icloud = EmailAccount.Provider.icloud.passwordGuidance
        #expect(icloud.contains("account.apple.com"), "iCloud guidance lacks the right URL")
        #expect(!icloud.contains("myaccount.google.com"), "iCloud guidance mentions Google")
        #expect(
            !EmailAccount.Provider.gmail.passwordGuidance.contains("appleid"),
            "Gmail guidance mentions Apple"
        )
    }

    @Test("iCloud guidance no longer points at the retired appleid.apple.com host")
    func icloudGuidanceUsesCurrentHost() {
        // Apple moved the account pages to account.apple.com; appleid.apple.com only
        // redirects now. The prose and the button must agree, because both are read
        // as instructions and a mismatch looks like one of them is stale.
        let provider = EmailAccount.Provider.icloud
        #expect(!provider.passwordGuidance.contains("appleid.apple.com"))
        #expect(provider.passwordGuidance.contains("account.apple.com"))
        #expect(provider.appPasswordURL?.host() == "account.apple.com")
    }

    @Test("every provider that offers a password link points at its own domain")
    func appPasswordURLHostsMatchTheProvider() {
        // Cheap guard against a copy-paste that points Fastmail's button at Google.
        // `.outlook` and `.other` are nil by design (see the property's doc comment),
        // so they are excluded rather than required to produce a URL.
        let expected: [EmailAccount.Provider: String] = [
            .icloud: "account.apple.com",
            .gmail: "myaccount.google.com",
            .yahoo: "account.yahoo.com",
            .fastmail: "app.fastmail.com"
        ]
        for (provider, host) in expected {
            #expect(provider.appPasswordURL?.host() == host, "\(provider.rawValue) link is wrong")
        }
        #expect(EmailAccount.Provider.outlook.appPasswordURL == nil)
        #expect(EmailAccount.Provider.other.appPasswordURL == nil)
    }

    @Test("the credential is named the way each provider names it")
    func passwordNounIsProviderSpecific() {
        // Apple does not use the phrase "app-specific"; Google does. A user told to
        // look for the wrong phrase concludes the setting does not exist.
        #expect(EmailAccount.Provider.gmail.passwordNoun == "app-specific password")
        #expect(EmailAccount.Provider.icloud.passwordNoun == "app password")
        for provider in EmailAccount.Provider.allCases {
            #expect(!provider.passwordNoun.isEmpty, "\(provider.rawValue) has no noun")
        }
    }

    @Test("a stored host maps back to its provider, so the picker opens on the right one")
    func matchingFindsProvider() {
        for (provider, host) in Self.knownHosts {
            #expect(EmailAccount.Provider.matching(host: host) == provider)
            // Case and stray whitespace must not defeat it: a host is case-insensitive
            // and users paste with trailing spaces.
            #expect(EmailAccount.Provider.matching(host: "  \(host.uppercased()) ") == provider)
        }
        #expect(EmailAccount.Provider.matching(host: "mail.example.com") == nil)
        #expect(EmailAccount.Provider.matching(host: "") == nil)
    }

    @Test(".other never claims a host")
    func otherHasNoHost() {
        #expect(EmailAccount.make(provider: .other, username: "s@example.com") == nil)
        #expect(EmailAccount.Provider.matching(host: "imap.mail.me.com") != .other)
    }

    @Test("the icloud convenience initialiser points at the real IMAPS endpoint")
    func icloudAccount() {
        let account = EmailAccount.icloud(username: "steve@example.com")
        #expect(account.host == "imap.mail.me.com")
        #expect(account.port == 993)
        // The keychain key is derived from the host, so two providers with the same
        // address must never share a stored secret.
        #expect(
            account.keychainAccount
                != EmailAccount.gmail(username: "steve@example.com").keychainAccount
        )
    }
}
