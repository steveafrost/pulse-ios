import Foundation
import Testing
@testable import ThirdHandCore

@Suite("ItemIdentity")
struct ItemIdentityTests {
    @Test("the four templates match the contract")
    func templates() {
        #expect(ItemIdentity.event("ABC-123") == "calendar:event:ABC-123")
        #expect(ItemIdentity.reminder("XYZ-9") == "reminders:reminder:XYZ-9")
        #expect(ItemIdentity.mail(messageID: "<a@b>") == "gmail:message:<a@b>")
        let conflict = ItemIdentity.calendarConflict(
            day: Fixture.date("2026-10-23T18:04:11.000Z"),
            participants: ["Ada", "Grace"],
            calendar: Fixture.calendar
        )
        #expect(conflict.hasPrefix("calendar:conflict:20261023:"))
        #expect(conflict.split(separator: ":").last?.count == 8)
    }

    @Test("the conflict hash is stable across runs")
    func hashIsStable() {
        let participants = ["ada@example.com", "grace@example.com"]
        let first = ItemIdentity.conflictHash(participants)
        let second = ItemIdentity.conflictHash(participants)
        #expect(first == second)
        #expect(first.count == 8)
        #expect(first.allSatisfy { $0.isHexDigit })
    }

    @Test("reordering participants does not change the hash")
    func hashIsOrderInsensitive() {
        let forward = ItemIdentity.conflictHash(["ada@example.com", "grace@example.com"])
        let reversed = ItemIdentity.conflictHash(["grace@example.com", "ada@example.com"])
        #expect(forward == reversed)
    }

    @Test("a different participant set changes the hash")
    func hashIsSetSensitive() {
        let two = ItemIdentity.conflictHash(["ada@example.com", "grace@example.com"])
        let oneRemoved = ItemIdentity.conflictHash(["ada@example.com"])
        let substituted = ItemIdentity.conflictHash(["ada@example.com", "linus@example.com"])
        #expect(two != oneRemoved)
        #expect(two != substituted)
    }

    @Test("the separator stops ['ab','c'] colliding with ['a','bc']")
    func separatorPreventsCollision() {
        #expect(ItemIdentity.conflictHash(["ab", "c"]) != ItemIdentity.conflictHash(["a", "bc"]))
    }

    @Test("the same pair on different days yields different ids")
    func dayIsPartOfTheId() {
        let participants = ["Ada", "Grace"]
        let today = ItemIdentity.calendarConflict(day: Fixture.date("2026-10-23T09:00:00.000Z"), participants: participants, calendar: Fixture.calendar)
        let tomorrow = ItemIdentity.calendarConflict(day: Fixture.date("2026-10-24T09:00:00.000Z"), participants: participants, calendar: Fixture.calendar)
        #expect(today != tomorrow)
    }

    @Test("canonical participants drop blanks, de-duplicate and sort")
    func canonicalisation() {
        let canonical = ItemIdentity.canonicalParticipants(["  Grace ", "ada", "ADA", "", "   "])
        #expect(canonical == ["ada", "grace"])
    }

    @Test("source parsing, including the reminders -> other mapping")
    func sourceParsing() {
        #expect(ItemIdentity.source(for: "calendar:event:x") == .calendar)
        #expect(ItemIdentity.source(for: "calendar:conflict:20261023:deadbeef") == .calendar)
        #expect(ItemIdentity.source(for: "gmail:message:<a@b>") == .gmail)
        #expect(ItemIdentity.source(for: "reminders:reminder:x") == .other)
        #expect(ItemIdentity.source(for: "nonsense:thing") == nil)
        #expect(ItemIdentity.source(for: "nocolon") == nil)
    }

    @Test("isValid enforces ^[a-z]+:.+")
    func validity() {
        #expect(ItemIdentity.isValid("calendar:event:x"))
        #expect(ItemIdentity.isValid("reminders:reminder:0123"))
        #expect(!ItemIdentity.isValid("nodots"))
        #expect(!ItemIdentity.isValid("Calendar:event:x"))
        #expect(!ItemIdentity.isValid("calendar:"))
        #expect(!ItemIdentity.isValid(":x"))
    }
}
