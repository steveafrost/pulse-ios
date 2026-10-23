@testable import Pulse
import Foundation
import PulseCore
import Testing

/// #21: the widget projection and the app-group paths.
@Suite("Widget board")
@MainActor
struct WidgetBoardTests {
    @Test("nowCount excludes fyi items")
    func nowCountExcludesFYI() {
        let now = Fixtures.fixtureNow
        let board: [Horizon: [PulseItem]] = [
            .now: [Fixtures.highPriorityRSVP, Fixtures.imminentMeeting, Fixtures.fyiLink],
            .next: [Fixtures.conflict],
            .niceToKnow: [Fixtures.fyiLink],
        ]
        let widget = WidgetBoard(board: board, generatedAt: now, calendar: Fixtures.calendar())
        #expect(widget.nowCount == 2)
        #expect(widget.items.count == 5)
    }

    @Test("Projection carries only the widget fields")
    func projectionShape() throws {
        let board: [Horizon: [PulseItem]] = [.now: [Fixtures.highPriorityRSVP]]
        let widget = WidgetBoard(board: board, generatedAt: Fixtures.fixtureNow, calendar: Fixtures.calendar())
        let data = try PulseJSON.makeEncoder(prettyPrinted: true).encode(widget)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["generatedAt"] != nil)
        #expect(json["nowCount"] as? Int == 1)
        let items = try #require(json["items"] as? [[String: Any]])
        // `people` joined the projection for the Live Activity's attendee line (#31).
        // It is optional, so an item without attendee names omits the key entirely
        // rather than writing null -- which is what keeps the cache small.
        let fields = Set(items[0].keys)
        #expect(fields == ["id", "title", "kind", "priority", "due", "horizon", "people"])
    }

    @Test("Order follows horizon order")
    func horizonOrder() {
        let board: [Horizon: [PulseItem]] = [
            .niceToKnow: [Fixtures.fyiLink],
            .now: [Fixtures.highPriorityRSVP],
            .later: [Fixtures.waitingItem],
        ]
        let widget = WidgetBoard(board: board, generatedAt: Fixtures.fixtureNow, calendar: Fixtures.calendar())
        #expect(widget.items.map(\.horizon) == ["now", "later", "niceToKnow"])
    }

    @Test("Paths live under Documents/Pulse")
    func paths() {
        let paths = PulsePaths(root: URL(fileURLWithPath: "/tmp/pulse-test"))
        #expect(paths.appGroupRoot.lastPathComponent == "Pulse")
        #expect(paths.boardURL.lastPathComponent == "board.json")
        #expect(paths.snapshotURL.lastPathComponent == "snapshot.json")
    }

    @Test("WidgetBoard round-trips through the store")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WidgetBoardStore(paths: PulsePaths(root: root))
        let widget = WidgetBoard(
            board: [.now: [Fixtures.highPriorityRSVP]],
            generatedAt: Fixtures.fixtureNow,
            calendar: Fixtures.calendar()
        )
        try store.write(widget)
        #expect(store.read() == widget)
    }
}
