import Foundation
import Testing
@testable import ThirdHandCore

@Suite("ItemIdentity.sharedLink")
struct SharedLinkIdentityTests {
    // MARK: - Stability

    @Test("the same URL twice yields the same id")
    func stable() {
        let first = ItemIdentity.sharedLink(source: .slack, url: "https://acme.slack.com/archives/C1/p1700000000")
        let second = ItemIdentity.sharedLink(source: .slack, url: "https://acme.slack.com/archives/C1/p1700000000")
        #expect(first == second)
        #expect(first.hasPrefix("slack:link:"))
        // 8 hex characters after the third colon.
        #expect(first.split(separator: ":").count == 3)
        #expect(first.split(separator: ":").last?.count == ItemIdentity.sharedLinkHashLength)
    }

    @Test("the id is valid per the contract's identifier rule and parses back to its source")
    func validAndParseable() {
        let id = ItemIdentity.sharedLink(source: .github, url: "https://github.com/acme/api/pull/7")
        #expect(ItemIdentity.isValid(id))
        #expect(ItemIdentity.source(for: id) == .github)
        #expect(DetectedItem.source(fromIdentifier: id) == .github)
    }

    @Test("a different path is a different item")
    func pathDiffers() {
        let one = ItemIdentity.sharedLink(source: .github, url: "https://github.com/acme/api/pull/1")
        let two = ItemIdentity.sharedLink(source: .github, url: "https://github.com/acme/api/pull/2")
        #expect(one != two)
    }

    @Test("a different source over the same URL is a different item")
    func sourceDiffers() {
        let slack = ItemIdentity.sharedLink(source: .slack, url: "https://example.com/x")
        let other = ItemIdentity.sharedLink(source: .other, url: "https://example.com/x")
        #expect(slack != other)
    }

    // MARK: - Normalisation

    @Test("tracking query parameters are normalised away")
    func trackingParameters() throws {
        let clean = ItemIdentity.sharedLink(source: .github, url: "https://github.com/acme/api/pull/9")
        let tracked = ItemIdentity.sharedLink(
            source: .github,
            url: "https://github.com/acme/api/pull/9?utm_source=slack&utm_medium=share&fbclid=abc&gclid=def&si=123"
        )
        #expect(clean == tracked)
    }

    @Test("a real query parameter is kept, and order does not matter")
    func realParametersSorted() {
        let a = ItemIdentity.normalizedSharedURL("https://x.com/s?b=2&a=1&utm_source=t")
        let b = ItemIdentity.normalizedSharedURL("https://x.com/s?a=1&b=2")
        #expect(a == b)
        #expect(a?.contains("utm_source") == false)
        // And it is a *different* id from the same path with no query at all.
        let bare = ItemIdentity.normalizedSharedURL("https://x.com/s")
        #expect(a != bare)
    }

    @Test("scheme and host case, a leading www. and a default port do not change identity")
    func hostNormalisation() {
        let canonical = ItemIdentity.normalizedSharedURL("https://github.com/acme/api/pull/3")
        #expect(ItemIdentity.normalizedSharedURL("HTTPS://GitHub.com/acme/api/pull/3") == canonical)
        #expect(ItemIdentity.normalizedSharedURL("https://www.github.com/acme/api/pull/3") == canonical)
        #expect(ItemIdentity.normalizedSharedURL("https://github.com:443/acme/api/pull/3") == canonical)
        #expect(ItemIdentity.normalizedSharedURL("https://github.com/acme/api/pull/3/") == canonical)
    }

    @Test("a fragment is dropped except where it is the message id")
    func fragments() {
        #expect(
            ItemIdentity.normalizedSharedURL("https://github.com/acme/api/pull/3#discussion_r1")
                == ItemIdentity.normalizedSharedURL("https://github.com/acme/api/pull/3")
        )
        let mail = ItemIdentity.normalizedSharedURL("https://mail.google.com/mail/u/0/#inbox/abc123")
        #expect(mail?.contains("#inbox/abc123") == true)
        // Two Gmail messages must not collapse into one item.
        let other = ItemIdentity.normalizedSharedURL("https://mail.google.com/mail/u/0/#inbox/zzz999")
        #expect(mail != other)
    }

    @Test("a non-http URL, an empty string and junk normalise to nil")
    func rejectsNonLinks() {
        #expect(ItemIdentity.normalizedSharedURL("") == nil)
        #expect(ItemIdentity.normalizedSharedURL("   ") == nil)
        #expect(ItemIdentity.normalizedSharedURL("not a url") == nil)
        #expect(ItemIdentity.normalizedSharedURL("mailto:ada@example.com") == nil)
        #expect(ItemIdentity.normalizedSharedURL("ftp://example.com/x") == nil)
        #expect(ItemIdentity.normalizedSharedURL("https://") == nil)
    }
}
