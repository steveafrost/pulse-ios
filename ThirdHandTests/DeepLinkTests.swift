import Foundation
import Testing
@testable import ThirdHand

/// The widget deep links.
///
/// These exist because the scheme check silently regressed during the Pulse → Third
/// Hand rename: `project.yml` registered `thirdhand`, the widgets emitted
/// `thirdhand://item/<id>`, and the handler compared against `"pulse"`, so every tap
/// was discarded. Nothing caught it, because `onOpenURL` is not reachable from a unit
/// test and neither side was wrong on its own.
@Suite("Deep links")
struct DeepLinkTests {

    private func url(_ string: String) -> URL {
        // Force-unwrap is deliberate: a malformed literal is a broken test, not a
        // condition the code under test should be asked to handle.
        URL(string: string)!
    }

    @Test("an item link yields the id")
    func itemLink() {
        #expect(DeepLink.itemID(from: url("thirdhand://item/abc123")) == "abc123")
    }

    @Test("an item id containing a percent-escape is decoded")
    func percentEncodedID() {
        // Item ids embed a source and a message id, so they legitimately contain
        // characters a URL would encode.
        #expect(
            DeepLink.itemID(from: url("thirdhand://item/gmail:message:a%40b.com"))
                == "gmail:message:a@b.com"
        )
    }

    @Test("the whole-widget tap opens the board and yields no item")
    func boardLink() {
        #expect(DeepLink.itemID(from: url("thirdhand://board")) == nil)
    }

    @Test("a foreign scheme is ignored")
    func foreignScheme() {
        // The exact regression: after the rename this URL carried an id but was
        // dropped. It must be *this* scheme that is accepted.
        #expect(DeepLink.itemID(from: url("pulse://item/abc123")) == nil)
        #expect(DeepLink.itemID(from: url("https://item/abc123")) == nil)
    }

    @Test("an empty item id is ignored")
    func emptyID() {
        #expect(DeepLink.itemID(from: url("thirdhand://item")) == nil)
        #expect(DeepLink.itemID(from: url("thirdhand://item/")) == nil)
    }

    @Test("the handler's scheme is the one the bundle actually registers")
    func schemeMatchesBundle() throws {
        // Read the scheme out of the built Info.plist rather than trusting a copy in
        // this file. A future rename that updates one side and not the other fails
        // here instead of shipping.
        // The app bundle, not the test bundle: the unit-test host is the app, so its
        // Info.plist is reachable through `bundleIdentifier` lookup. `Bundle(for:)`
        // with a test class would read the *test* bundle's plist and always fail.
        let bundle = try #require(
            Bundle(identifier: "com.steveafrost.thirdhand"),
            "could not find the app bundle"
        )
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = (types ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        try #require(!schemes.isEmpty, "the app registers no URL scheme at all")
        #expect(
            schemes.contains(DeepLink.scheme),
            "handler accepts \(DeepLink.scheme) but the bundle registers \(schemes)"
        )
        #expect(!schemes.contains("pulse"), "the old scheme is still registered")
    }
}
