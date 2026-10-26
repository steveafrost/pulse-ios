import Foundation
import ThirdHandCore
import Testing

@testable import ThirdHand

/// §10 regression: these sentences are the ones that shipped wrong.
///
/// The bug they guard is not exotic — `"\(count) item\(count == 1 ? "" : "s")"`
/// was written correctly in some places and wrongly in others, and the wrong
/// ones were the ones a user reads while capturing. Each test below names the
/// surface, so a failure points at the screen a tester would have seen.
@Suite("Copy")
struct CopyTests {

    // MARK: - Plural

    @Test("0 items is plural, not singular")
    func pluralZero() {
        #expect(Plural.items(0) == "0 items")
    }

    @Test("1 item is singular")
    func pluralOne() {
        #expect(Plural.items(1) == "1 item")
    }

    @Test("2 items is plural")
    func pluralTwo() {
        #expect(Plural.items(2) == "2 items")
    }

    @Test("an irregular noun is supplied by the caller, not guessed")
    func pluralIrregular() {
        #expect(Plural.count(1, "entry", "entries") == "1 entry")
        #expect(Plural.count(3, "entry", "entries") == "3 entries")
    }

    @Test("the noun alone inflects the same way as the count")
    func pluralNounAlone() {
        #expect(Plural.noun(1, "thing") == "thing")
        #expect(Plural.noun(0, "thing") == "things")
    }

    // MARK: - Board sections

    @Test("a section header never reads 'Now, 1 items'")
    func sectionHeaderPlurality() {
        #expect(BoardCopy.sectionHeader(.now, count: 1) == "Now, 1 item")
        #expect(BoardCopy.sectionHeader(.now, count: 2) == "Now, 2 items")
        #expect(BoardCopy.sectionHeader(.later, count: 0) == "Later, 0 items")
    }

    @Test("the filter bar count inflects")
    func shownPlurality() {
        #expect(BoardCopy.shown(1) == "1 item shown")
        #expect(BoardCopy.shown(12) == "12 items shown")
    }

    @Test("show-more names the count and the horizon exactly once")
    func showMore() {
        #expect(BoardCopy.showMore(1, in: .now) == "Show 1 more in Now")
        #expect(BoardCopy.showMore(4, in: .next) == "Show 4 more in Next")
    }

    @Test("expanded state names its object for VoiceOver")
    func showFewer() {
        #expect(BoardCopy.showFewer(in: .now) == "Show fewer items in Now")
    }

    @Test("history uses the irregular plural")
    func historyPlurality() {
        #expect(BoardCopy.history(1) == "History, 1 entry")
        #expect(BoardCopy.history(3) == "History, 3 entries")
    }

    @Test("load-more never reads 'Load 1 more items'")
    func loadMorePlurality() {
        #expect(BoardCopy.loadMore(1) == "Load 1 more item")
        #expect(BoardCopy.loadMore(12) == "Load 12 more items")
    }

    // MARK: - Detail: the quick-action label bug

    /// The defect a design review caught on a screenshot: the fixture supplied
    /// `label: "Open thread"` and the view wrapped it as
    /// `Label("Open “\(action.label)”")`, producing `Open “Open thread”`.
    /// The invariant is that a quick action's title is rendered verbatim.
    @Test("a verb-phrase label renders once, never doubled")
    func quickActionLabelRendersOnce() {
        let action = QuickAction(label: "Open thread", url: "https://slack.example.com/archives/C1/p1")
        let rendered = QuickActionRow.title(for: action)

        #expect(rendered == "Open thread")
        #expect(!rendered.contains("Open “Open thread”"))
        #expect(rendered.components(separatedBy: "Open").count - 1 == 1)
    }

    @Test("a label that is not a verb is still rendered verbatim")
    func quickActionLabelIsNeverPrefixed() {
        let action = QuickAction(label: "Accept", url: "https://calendar.example.com/rsvp/1")
        #expect(QuickActionRow.title(for: action) == "Accept")
    }

    @Test("no fixture quick action renders a doubled verb")
    func fixturesHaveNoDoubledVerbs() {
        // Guards the whole fixture corpus, not just the row a review caught.
        let fixtures: [ThirdHandItem] = [
            Fixtures.withThreeQuickActions,
            Fixtures.highPriorityRSVP,
            Fixtures.imminentMeeting,
            Fixtures.conflict,
        ]
        for item in fixtures {
            for action in item.quickActions {
                let rendered = QuickActionRow.title(for: action)
                let firstWord = rendered.split(separator: " ").first.map(String.init) ?? ""
                guard !firstWord.isEmpty else { continue }
                let occurrences = rendered.components(separatedBy: firstWord).count - 1
                #expect(
                    occurrences == 1,
                    "label \"\(action.label)\" repeats \"\(firstWord)\" in \"\(rendered)\""
                )
                #expect(
                    !rendered.contains("\u{201C}"),
                    "label \"\(rendered)\" is quoted"
                )
            }
        }
    }

    // MARK: - Capture capsule

    @Test("the capsule line inflects and never says '1 items'")
    func captureLinePlurality() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let one = CaptureStatusModel(phase: .idle(now), itemCount: 1)
        let many = CaptureStatusModel(phase: .idle(now), itemCount: 12)

        #expect(one.text(now: now).hasPrefix("1 item "))
        #expect(!one.text(now: now).hasPrefix("1 items"))
        #expect(many.text(now: now).hasPrefix("12 items "))
    }

    @Test("the failed state offers an action rather than a shrug")
    func captureFailureIsActionable() {
        let model = CaptureStatusModel(phase: .failed(Date()), itemCount: 0)
        #expect(model.text(now: Date()).contains("Try again"))
    }

    @Test("the sync popover says how old the board is, and admits when it doesn't know")
    func syncDetailStates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let never = CaptureStatusModel(phase: .idle(nil), itemCount: 0)
        #expect(CaptureCopy.syncDetail(never, now: now) == "Not checked yet")

        let fresh = CaptureStatusModel(phase: .idle(now), itemCount: 12)
        let freshLine = CaptureCopy.syncDetail(fresh, now: now)
        #expect(freshLine.hasPrefix("Checked "))
        #expect(freshLine.contains("12 items"))

        let running = CaptureStatusModel(phase: .capturing, itemCount: 0)
        #expect(CaptureCopy.syncDetail(running, now: now) == "Checking now…")

        // A failure must not read as a shrug, and must not claim the board is current.
        let failed = CaptureStatusModel(phase: .failed(now), itemCount: 0)
        let failedLine = CaptureCopy.syncDetail(failed, now: now)
        #expect(failedLine.hasPrefix("Couldn't check"))
        #expect(!failedLine.hasPrefix("Checked"))
    }

    @Test("the sync popover never leaks transport vocabulary either")
    func syncDetailAvoidsImplementationWords() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = CaptureStatusModel(phase: .idle(now), itemCount: 3, syncText: "Mac · 2m ago")
        let line = CaptureCopy.syncDetail(model, now: now)
        for banned in ["snapshot", "mirror", "publish", "sync", "manifest"] {
            #expect(!line.lowercased().contains(banned), "leaked \(banned): \(line)")
        }
    }

    @Test("the capture VoiceOver sentence does not leak transport vocabulary")
    func captureAccessibilityAvoidsImplementationWords() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = CaptureStatusModel(phase: .idle(now), itemCount: 3, syncText: "Mac · 2m ago")
        let sentence = CaptureCopy.accessibility(model, now: now)

        for banned in ["snapshot", "mirror", "publish", "sync", "manifest", "nil"] {
            #expect(
                !sentence.lowercased().contains(banned),
                "accessibility sentence leaked \(banned): \(sentence)"
            )
        }
    }
}
