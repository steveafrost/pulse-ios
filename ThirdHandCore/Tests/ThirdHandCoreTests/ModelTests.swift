import Foundation
import Testing
@testable import ThirdHandCore

@Suite("Wire models")
struct ModelTests {

    // MARK: - Round trips

    @Test("a fully-populated item survives encode -> decode unchanged")
    func fullItemRoundTrip() throws {
        let item = Fixture.fullItem()
        let data = try ThirdHandJSON.encode(item)
        let decoded = try ThirdHandJSON.decode(ThirdHandItem.self, from: data)
        #expect(decoded == item)
    }

    @Test("fractional seconds round-trip exactly")
    func fractionalSecondsRoundTrip() throws {
        let item = Fixture.fullItem()
        let data = try ThirdHandJSON.encode(item)
        let decoded = try ThirdHandJSON.decode(ThirdHandItem.self, from: data)

        // Every instant kept its millisecond component, not just its second.
        #expect(decoded.firstSeenAt == item.firstSeenAt)
        #expect(decoded.history[1].at == item.history[1].at)
        #expect(decoded.action?.finishedAt == item.action?.finishedAt)
        let finishedAt = try #require(decoded.action?.finishedAt)
        #expect(finishedAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) == 0.5)
    }

    @Test("dates are written the way JavaScript's toISOString does")
    func dateWireFormat() throws {
        let stamp = Fixture.date("2026-10-23T18:04:11.123Z")
        #expect(ThirdHandJSON.dates.string(from: stamp) == "2026-10-23T18:04:11.123Z")

        let item = Fixture.fullItem()
        let json = try #require(String(data: try ThirdHandJSON.encode(item), encoding: .utf8))
        #expect(json.contains("\"due\":\"2026-10-23T18:04:11.123Z\""))
        // No offset form and no missing fraction: the plugin parses this directly.
        #expect(!json.contains("+00:00"))
    }

    @Test("a whole-second instant still writes three fraction digits")
    func wholeSecondFormat() {
        let stamp = Fixture.date("2026-10-23T18:04:11Z")
        #expect(ThirdHandJSON.dates.string(from: stamp) == "2026-10-23T18:04:11.000Z")
    }

    @Test("timestamps without fractional seconds are accepted")
    func parsesNonFractionalInput() {
        #expect(ThirdHandJSON.dates.date(from: "2026-10-23T18:04:11Z") == Fixture.date("2026-10-23T18:04:11.000Z"))
        #expect(ThirdHandJSON.dates.date(from: "2026-10-23T18:04:11.123456Z") != nil)
        // An offset normalises to UTC rather than failing.
        #expect(ThirdHandJSON.dates.date(from: "2026-10-23T20:04:11+02:00") == Fixture.date("2026-10-23T18:04:11.000Z"))
    }

    @Test("the snapshot envelope round-trips, fractional seconds and null draft included")
    func snapshotRoundTrip() throws {
        let snapshot = ThirdHandSnapshot(
            generatedAt: Fixture.date("2026-10-23T18:04:11.000Z"),
            deviceName: "Steve's iPhone",
            lastViewedAt: Fixture.date("2026-10-23T17:40:00.500Z"),
            items: [Fixture.fullItem(), Fixture.fullItem(id: "reminders:reminder:X")],
            runs: [
                CaptureRun(
                    run: "morning",
                    startedAt: Fixture.date("2026-10-23T07:00:00.001Z"),
                    finishedAt: Fixture.date("2026-10-23T07:00:03.999Z"),
                    summary: "2 items, 0 errors",
                    thread: "thr_abc",
                    sources: ["calendar", "reminders"]
                )
            ],
            draft: ThirdHandDraft(
                kind: "weekly",
                date: "2026-10-23",
                file: "/tmp/weekly-2026-10-23.md",
                body: "# Week\n\nShipped M1.\n",
                modifiedAt: Fixture.date("2026-10-23T08:00:00.123Z")
            )
        )

        let data = try ThirdHandJSON.encode(snapshot, prettyPrinted: true)
        let decoded = try ThirdHandJSON.decode(ThirdHandSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.schemaVersion == 1)

        // A nil draft must survive as an explicit `"draft": null`, since the
        // contract's example shows the key present.
        var empty = snapshot
        empty.draft = nil
        let emptyJSON = try #require(String(data: try ThirdHandJSON.encode(empty), encoding: .utf8))
        #expect(emptyJSON.contains("\"draft\":null"))
        #expect(try ThirdHandJSON.decode(ThirdHandSnapshot.self, from: Data(emptyJSON.utf8)).draft == nil)
    }

    @Test("absent history and quickActions keys decode as empty arrays")
    func absentOptionalArraysDecodeEmpty() throws {
        let json = """
        {
          "id": "calendar:event:MIN",
          "source": "calendar",
          "kind": "deadline",
          "title": "Minimal",
          "firstSeenAt": "2026-10-23T18:04:11.000Z",
          "lastSeenAt": "2026-10-23T18:04:11.000Z",
          "updatedAt": "2026-10-23T18:04:11.000Z",
          "lastChangedBy": "capture"
        }
        """
        let item = try ThirdHandJSON.decode(ThirdHandItem.self, from: Data(json.utf8))
        #expect(item.history.isEmpty)
        #expect(item.quickActions.isEmpty)
        #expect(item.detail == "")
        #expect(item.people.isEmpty)
        #expect(item.status == .open)
        #expect(item.priority == .normal)
        #expect(item.agentSkills == nil)
        #expect(item.action == nil)
    }

    // MARK: - Lenient enum decoding

    @Test("an unknown enum value decodes to the documented fallback instead of throwing")
    func lenientEnumDecoding() throws {
        let diagnostics = DecodeDiagnostics()
        diagnostics.reset()
        DecodeDiagnostics.shared.reset()

        let json = """
        {
          "id": "slack:msg:1",
          "source": "signal",
          "kind": "escalation",
          "title": "Unknown peers",
          "priority": "urgent",
          "status": "escalated",
          "firstSeenAt": "2026-10-23T18:04:11.000Z",
          "lastSeenAt": "2026-10-23T18:04:11.000Z",
          "updatedAt": "2026-10-23T18:04:11.000Z",
          "lastChangedBy": "capture"
        }
        """
        let item = try ThirdHandJSON.decode(ThirdHandItem.self, from: Data(json.utf8))

        #expect(item.source == .other)
        #expect(item.kind == .followup)
        #expect(item.priority == .normal)
        #expect(item.status == .open)

        // The substitution is recorded, not silently dropped.
        let events = DecodeDiagnostics.shared.recent()
        #expect(events.contains(DecodeDiagnostics.Event(type: "Source", value: "signal")))
        #expect(events.contains(DecodeDiagnostics.Event(type: "Kind", value: "escalation")))
        #expect(events.contains(DecodeDiagnostics.Event(type: "Priority", value: "urgent")))
        #expect(events.contains(DecodeDiagnostics.Event(type: "Status", value: "escalated")))
    }

    @Test("unknown enums on their own decode to fallbacks")
    func lenientEnumFallbacks() throws {
        func decode<T: LenientWireEnum>(_ type: T.Type, _ raw: String) throws -> T {
            try ThirdHandJSON.decode(T.self, from: Data("\"\(raw)\"".utf8))
        }
        #expect(try decode(Source.self, "nope") == .other)
        #expect(try decode(Kind.self, "nope") == .followup)
        #expect(try decode(Status.self, "nope") == .open)
        #expect(try decode(Priority.self, "nope") == .normal)
        #expect(try decode(ActionStatus.self, "nope") == .failed)
    }

    @Test("a known enum value is untouched")
    func knownEnumValuePreserved() throws {
        let data = Data("\"gmail\"".utf8)
        #expect(try ThirdHandJSON.decode(Source.self, from: data) == .gmail)
    }

    @Test("an unknown mirror op throws rather than guessing")
    func unknownVerbThrows() throws {
        #expect(throws: (any Error).self) {
            try ThirdHandJSON.decode(ItemActionVerb.self, from: Data("\"archive\"".utf8))
        }
    }

    // MARK: - QuickAction validation

    @Test("four quick actions are rejected")
    func tooManyQuickActions() throws {
        let actions = (0..<4).map { QuickAction(label: "a\($0)", text: "t") }
        #expect(throws: ThirdHandStoreError.tooManyQuickActions) { try actions.validateQuickActions() }
    }

    @Test("a 33-character label is rejected, a 32-character one is kept")
    func labelLength() throws {
        let tooLong = [QuickAction(label: String(repeating: "x", count: 33), text: "t")]
        #expect(throws: ThirdHandStoreError.invalidQuickAction("label must be a short string (1-32 chars)")) {
            try tooLong.validateQuickActions()
        }
        try [QuickAction(label: String(repeating: "x", count: 32), text: "t")].validateQuickActions()
        #expect(throws: (any Error).self) { try [QuickAction(label: "   ", text: "t")].validateQuickActions() }
    }

    @Test("a quick action needs text, a url, or both")
    func actionNeedsContent() throws {
        #expect(throws: ThirdHandStoreError.invalidQuickAction("needs text to copy, a url to open, or both")) {
            try [QuickAction(label: "Empty")].validateQuickActions()
        }
        try [QuickAction(label: "Text only", text: "hi")].validateQuickActions()
        try [QuickAction(label: "URL only", url: "https://example.com")].validateQuickActions()
    }

    @Test("a non-https url is rejected")
    func urlMustBeHTTPS() throws {
        #expect(throws: ThirdHandStoreError.invalidQuickAction("url must be an https URL")) {
            try [QuickAction(label: "Insecure", url: "http://example.com")].validateQuickActions()
        }
        #expect(throws: (any Error).self) {
            try [QuickAction(label: "Mail", url: "mailto:someone@example.com")].validateQuickActions()
        }
    }

    @Test("text over 1500 characters is rejected")
    func textLength() throws {
        let long = [QuickAction(label: "Long", text: String(repeating: "y", count: 1501))]
        #expect(throws: (any Error).self) { try long.validateQuickActions() }
    }

    // MARK: - Identifier + source derivation

    @Test("source derives from the id prefix, unknown prefixes fall back to other")
    func sourceDerivation() {
        #expect(DetectedItem.source(fromIdentifier: "calendar:event:ABC") == .calendar)
        // `reminders` is not one of the contract's six sources: a reminder item
        // is a `calendar` capture with a `reminders:` id, which lands in `.other`
        // exactly as the Node store's `SOURCES.includes(...) ? ... : "other"` does.
        #expect(DetectedItem.source(fromIdentifier: "reminders:reminder:ABC") == .other)
        #expect(DetectedItem.source(fromIdentifier: "slack:msg:1") == .slack)
        // `retrieval` is not a known source, so it lands in `.other`.
        #expect(DetectedItem.source(fromIdentifier: "retrieval:1") == .other)
    }

    @Test("identifiers must look like <source>:<id>")
    func identifierValidation() {
        #expect(DetectedItem.isValidIdentifier("calendar:event:ABC"))
        #expect(!DetectedItem.isValidIdentifier("calendar:"))
        #expect(!DetectedItem.isValidIdentifier("nocolon"))
        #expect(!DetectedItem.isValidIdentifier("Calendar:event:1"))
    }

    // MARK: - Snapshot pruning + versioning

    @Test("closed items older than three days are pruned, open ones are not")
    func pruningClosedItems() throws {
        let old = Fixture.date("2026-10-19T00:00:00.000Z")
        var done = Fixture.fullItem(id: "calendar:event:OLD")
        done.status = .done
        done.resolvedAt = old
        done.updatedAt = old

        var fresh = Fixture.fullItem(id: "calendar:event:NEW")
        fresh.status = .dismissed
        fresh.resolvedAt = Fixture.now

        let snapshot = ThirdHandSnapshot(
            generatedAt: Fixture.now,
            deviceName: "test",
            items: [done, fresh, Fixture.fullItem(id: "calendar:event:OPEN")]
        )
        let pruned = snapshot.pruningClosedItems(olderThan: Fixture.now)
        #expect(pruned.items.count == 2)
        #expect(!pruned.items.contains { $0.id == "calendar:event:OLD" })
    }

    @Test("a newer schema version refuses to be written back")
    func schemaVersionGate() throws {
        let snapshot = ThirdHandSnapshot(
            schemaVersion: 99,
            generatedAt: Fixture.now,
            deviceName: "test"
        )
        #expect(!snapshot.isWritable())
        #expect(throws: (any Error).self) { try snapshot.validateVersion() }
        try ThirdHandSnapshot(generatedAt: Fixture.now, deviceName: "test").validateVersion()
    }
}
