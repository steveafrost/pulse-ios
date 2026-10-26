import Foundation
import Testing
@testable import ThirdHandCore

@Suite("SharedLinkSource")
struct SharedLinkSourceTests {
    private func link(_ url: String, text: String? = nil, title: String? = nil) -> SharedLinkSnapshot {
        SharedLinkSnapshot(url: url, text: text, title: title, sharedAt: Fixture.now)
    }

    // MARK: - Host rules

    @Test("a Slack permalink is a Slack target, for the workspace tenant too")
    func slackHosts() {
        #expect(SharedLinkSource.target(for: "https://acme.slack.com/archives/C1/p1700000000") == .slack)
        #expect(SharedLinkSource.target(for: "https://app.slack.com/client/T1/C1") == .slack)
        #expect(SharedLinkSource.target(for: "https://slack.com/x") == .slack)
    }

    @Test("a GitHub pull request is a review; any other GitHub page is not")
    func githubPaths() {
        #expect(SharedLinkSource.target(for: "https://github.com/acme/api/pull/7") == .githubPullRequest)
        #expect(SharedLinkSource.target(for: "https://github.com/acme/api/pulls/7") == .githubPullRequest)
        #expect(SharedLinkSource.target(for: "https://github.com/acme/api/issues/7") == .githubOther)
        #expect(SharedLinkSource.target(for: "https://github.com/acme/api") == .githubOther)
        // A host that merely contains "github" is not GitHub.
        #expect(SharedLinkSource.target(for: "https://github.example.com/acme/api/pull/7") == .other)
    }

    @Test("a Gmail permalink is mail; a Google doc is not")
    func mailHosts() {
        #expect(SharedLinkSource.target(for: "https://mail.google.com/mail/u/0/#inbox/abc") == .mail)
        #expect(SharedLinkSource.target(for: "https://docs.google.com/document/d/1") == .other)
    }

    @Test("a bare URL with no host match is the catch-all target")
    func unknownHost() {
        #expect(SharedLinkSource.target(for: "https://example.com/whatever") == .other)
    }

    // MARK: - Kind heuristics

    @Test("a Slack link with a question is a reply")
    func slackQuestionIsReply() {
        let item = SharedLinkSource.item(for: link(
            "https://acme.slack.com/archives/C1/p1700000000",
            text: "Can you take a look at the auth PR before Friday?"
        ))
        #expect(item?.kind == .reply)
        #expect(item?.priority == .normal)
        #expect(item?.source == .slack)
    }

    @Test("a Slack link asking for a decision is a decision, question mark or not")
    func slackDecision() {
        let item = SharedLinkSource.item(for: link(
            "https://acme.slack.com/archives/C1/p1700000001",
            text: "Should we ship the migration on Friday?"
        ))
        #expect(item?.kind == .decision)

        let phrase = SharedLinkSource.item(for: link(
            "https://acme.slack.com/archives/C1/p1700000002",
            text: "need your approval on the pricing page"
        ))
        #expect(phrase?.kind == .decision)
    }

    @Test("a Slack link that neither asks nor decides is a followup")
    func slackFollowup() {
        let item = SharedLinkSource.item(for: link(
            "https://acme.slack.com/archives/C1/p1700000003",
            text: "shipping this now"
        ))
        #expect(item?.kind == .followup)

        // No text at all is still an item -- the user shared it on purpose.
        let bare = SharedLinkSource.item(for: link("https://acme.slack.com/archives/C1/p1700000004"))
        #expect(bare?.kind == .followup)
    }

    @Test("a GitHub pull request link is a review")
    func githubReview() {
        let item = SharedLinkSource.item(for: link("https://github.com/acme/api/pull/42"))
        #expect(item?.kind == .review)
        #expect(item?.source == .github)
        #expect(item?.priority == .normal)
    }

    @Test("a mail link is a reply")
    func mailReply() {
        let item = SharedLinkSource.item(for: link("https://mail.google.com/mail/u/0/#inbox/abc123"))
        #expect(item?.kind == .reply)
        #expect(item?.source == .gmail)
    }

    @Test("a bare link with no host match is fyi / low")
    func bareIsFyi() {
        let item = SharedLinkSource.item(for: link("https://example.com/some/page"))
        #expect(item?.kind == .fyi)
        #expect(item?.priority == .low)
        #expect(item?.source == .other)
    }

    // MARK: - Item shape

    @Test("a share becomes an item with a valid id, an https url and an Open action")
    func itemShape() {
        let item = SharedLinkSource.item(for: link(
            "https://github.com/acme/api/pull/42",
            text: "Review please",
            title: "Add retry to the queue"
        ))
        let unwrapped = try? #require(item)
        guard let unwrapped else { return }
        #expect(ItemIdentity.isValid(unwrapped.id))
        #expect(unwrapped.url == "https://github.com/acme/api/pull/42")
        #expect(unwrapped.title == "Add retry to the queue")
        #expect(unwrapped.detail == "Review please")
        #expect(unwrapped.due == nil)
        #expect(unwrapped.quickActions == [QuickAction(label: "Open", url: "https://github.com/acme/api/pull/42")])
        #expect(unwrapped.reason == "shared from github")
    }

    @Test("a missing title falls back to the text's first line, then the path, never empty")
    func titleFallbacks() {
        let fromText = SharedLinkSource.item(for: link(
            "https://github.com/acme/api/pull/42",
            text: "Fix the flaky test\n\nMore detail"
        ))
        #expect(fromText?.title == "Fix the flaky test")

        let fromPath = SharedLinkSource.item(for: link("https://github.com/acme/api/pull/42"))
        #expect(fromPath?.title == "Github: 42")

        let fromHost = SharedLinkSource.item(for: link("https://example.com"))
        #expect(fromHost?.title == "Other: example.com")
    }

    @Test("a malformed URL produces no item rather than a crash or a junk item")
    func malformedURL() {
        #expect(SharedLinkSource.item(for: link("mailto:ada@example.com")) == nil)
        #expect(SharedLinkSource.item(for: link("not a url")) == nil)
    }

    @Test("sharing the same link twice is one item; a re-share with a title wins")
    func dedupByID() {
        let url = "https://github.com/acme/api/pull/42"
        let items = SharedLinkSource.detect(
            links: [
                link(url),
                link(url, title: "Add retry to the queue"),
                link("https://github.com/acme/api/pull/43")
            ],
            now: Fixture.now
        )
        #expect(items.count == 2)
        let titled = items.first { $0.url == url }
        #expect(titled?.title == "Add retry to the queue")
    }

    @Test("tracking parameters on one share and not another still produce one item")
    func trackingParamsDedup() {
        let items = SharedLinkSource.detect(
            links: [
                link("https://github.com/acme/api/pull/42"),
                link("https://github.com/acme/api/pull/42?utm_source=slack&utm_campaign=x")
            ],
            now: Fixture.now
        )
        #expect(items.count == 1)
        #expect(items.first?.url == "https://github.com/acme/api/pull/42")
    }

    @Test("the output is sorted by id, so a pass is diffable")
    func sortedOutput() {
        let items = SharedLinkSource.detect(
            links: [
                link("https://acme.slack.com/archives/C1/p1"),
                link("https://github.com/acme/api/pull/1"),
                link("https://mail.google.com/mail/u/0/#inbox/abc")
            ],
            now: Fixture.now
        )
        #expect(items.map(\.id) == items.map(\.id).sorted())
    }

    // MARK: - Provider

    @Test("a missing file is an empty source, not an error")
    func missingFile() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = FileSharedLinkProvider(paths: ThirdHandPaths(root: root))
        #expect((try? provider.sharedLinks())?.isEmpty == true)
    }

    @Test("a JSONL file round-trips, skips blank lines and survives a malformed line")
    func jsonlRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = ThirdHandPaths(root: root)
        let writer = SharedLinkWriter(paths: paths)
        try writer.append(
            url: "https://github.com/acme/api/pull/42",
            text: "Review please",
            title: nil,
            now: Fixture.now
        )
        try writer.append(
            url: "https://acme.slack.com/archives/C1/p1?utm_source=x",
            text: "Ship it?",
            title: nil,
            now: Fixture.now
        )

        // The last line is half-written, as a killed extension would leave it.
        let handle = try FileHandle(forWritingTo: paths.sharedLinksURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"url\":\"https://exa\n".utf8))
        try handle.close()

        let provider = FileSharedLinkProvider(paths: paths)
        let links = try provider.sharedLinks()
        #expect(links.count == 2)
        #expect(links.first?.url == "https://github.com/acme/api/pull/42")
        #expect(links.first?.text == "Review please")
        // Normalised on write, so `utm_source` never reaches the file.
        #expect(links.last?.url == "https://acme.slack.com/archives/C1/p1")

        let items = SharedLinkSource.detect(links: links, now: Fixture.now)
        #expect(items.count == 2)
    }

    @Test("the writer refuses a URL that is not a link")
    func writerRefusesJunk() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = SharedLinkWriter(paths: ThirdHandPaths(root: root))
        #expect(throws: SharedLinkError.self) {
            try writer.append(url: "mailto:ada@example.com", text: nil, title: nil, now: Fixture.now)
        }
    }

    @Test("a line with no instant is dated by the reader's clock")
    func undatedRecord() {
        let data = Data(#"{"url":"https://example.com/x"}"#.utf8)
        let links = FileSharedLinkProvider.decode(data, at: Fixture.now)
        #expect(links.count == 1)
        #expect(links.first?.sharedAt == Fixture.now)
    }
}

// MARK: - Classifier rows

@Suite("Classifier.classifySharedLink")
struct SharedLinkClassifierTests {
    @Test("github pull request -> review / normal")
    func github() throws {
        let (kind, priority) = try #require(Classifier.classifySharedLink(target: .githubPullRequest, text: nil))
        #expect(kind == .review)
        #expect(priority == .normal)
    }

    @Test("mail -> reply / normal")
    func mail() throws {
        let (kind, priority) = try #require(Classifier.classifySharedLink(target: .mail, text: nil))
        #expect(kind == .reply)
        #expect(priority == .normal)
    }

    @Test("slack: decision outranks a question mark")
    func decisionFirst() throws {
        let (kind, _) = try #require(Classifier.classifySharedLink(
            target: .slack,
            text: "Should we roll back? It is worse than before."
        ))
        #expect(kind == .decision)
    }

    @Test("slack with no text is a followup, never nothing")
    func alwaysAnItem() throws {
        let (kind, _) = try #require(Classifier.classifySharedLink(target: .slack, text: nil))
        #expect(kind == .followup)
        #expect(Classifier.classifySharedLink(target: .other, text: nil)?.0 == .fyi)
    }
}
