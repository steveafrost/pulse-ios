import Foundation
import Testing
@testable import PulseCore

/// One test per row of the table in `docs/DATA-CONTRACT.md`
/// ("Classification rules (MVP, on-device only)").
@Suite("Classifier")
struct ClassifierTests {
    // MARK: Row 1 -- invitation

    @Test("row 1: invite inside 24h is rsvp/high")
    func inviteUrgent() {
        let result = Classifier.classifyInvite(
            started: Fixture.now.addingTimeInterval(3 * 3600),
            now: Fixture.now,
            isAccepted: false
        )
        #expect(result?.0 == .rsvp)
        #expect(result?.1 == .high)
    }

    @Test("row 1: invite in three days is rsvp/normal")
    func inviteLater() {
        let result = Classifier.classifyInvite(
            started: Fixture.now.addingTimeInterval(3 * 86_400),
            now: Fixture.now,
            isAccepted: false
        )
        #expect(result?.0 == .rsvp)
        #expect(result?.1 == .normal)
    }

    @Test("row 1: an accepted invite is not an RSVP")
    func inviteAccepted() {
        #expect(Classifier.classifyInvite(started: Fixture.now.addingTimeInterval(3600), now: Fixture.now, isAccepted: true) == nil)
    }

    @Test("row 1: boundaries -- exactly 24h is normal, exactly 7d still counts, 7d+1s does not")
    func inviteBoundaries() {
        let exactly24h = Classifier.classifyInvite(started: Fixture.now.addingTimeInterval(86_400), now: Fixture.now, isAccepted: false)
        #expect(exactly24h?.1 == .normal)

        let exactly7d = Classifier.classifyInvite(started: Fixture.now.addingTimeInterval(7 * 86_400), now: Fixture.now, isAccepted: false)
        #expect(exactly7d?.0 == .rsvp)

        let past7d = Classifier.classifyInvite(started: Fixture.now.addingTimeInterval(7 * 86_400 + 1), now: Fixture.now, isAccepted: false)
        #expect(past7d == nil)
    }

    @Test("row 1: an event already started is not an RSVP")
    func inviteStarted() {
        #expect(Classifier.classifyInvite(started: Fixture.now.addingTimeInterval(-60), now: Fixture.now, isAccepted: false) == nil)
    }

    // MARK: Row 2 -- conflict

    @Test("row 2: conflict is always conflict/high")
    func conflict() {
        let result = Classifier.classifyConflict()
        #expect(result?.0 == .conflict)
        #expect(result?.1 == .high)
    }

    // MARK: Row 3 -- imminent

    @Test("row 3: event in 45 minutes is deadline/high")
    func imminent() {
        let result = Classifier.classifyImminentEvent(started: Fixture.now.addingTimeInterval(45 * 60), now: Fixture.now, isAllDay: false)
        #expect(result?.0 == .deadline)
        #expect(result?.1 == .high)
    }

    @Test("row 3: all-day events never match")
    func imminentAllDay() {
        #expect(Classifier.classifyImminentEvent(started: Fixture.now.addingTimeInterval(600), now: Fixture.now, isAllDay: true) == nil)
    }

    @Test("row 3: boundaries -- exactly 60 minutes counts, 60 minutes plus a second does not")
    func imminentBoundaries() {
        #expect(Classifier.classifyImminentEvent(started: Fixture.now.addingTimeInterval(3_600), now: Fixture.now, isAllDay: false) != nil)
        #expect(Classifier.classifyImminentEvent(started: Fixture.now.addingTimeInterval(3_601), now: Fixture.now, isAllDay: false) == nil)
    }

    // MARK: Row 4 -- reminder

    @Test("row 4: overdue reminder is deadline/high, due-later-today is deadline/normal")
    func reminder() {
        let overdue = Classifier.classifyReminder(due: Fixture.now.addingTimeInterval(-60), now: Fixture.now, isCompleted: false)
        #expect(overdue?.0 == .deadline)
        #expect(overdue?.1 == .high)

        let laterToday = Classifier.classifyReminder(due: Fixture.now.addingTimeInterval(3600), now: Fixture.now, isCompleted: false)
        #expect(laterToday?.0 == .deadline)
        #expect(laterToday?.1 == .normal)
    }

    @Test("row 4: a completed reminder never matches")
    func reminderCompleted() {
        #expect(Classifier.classifyReminder(due: Fixture.now.addingTimeInterval(-60), now: Fixture.now, isCompleted: true) == nil)
    }

    // MARK: Row 5 -- link in notes

    @Test("row 5: an https link in notes is fyi/low, and the link is extracted")
    func linkInNotes() {
        let result = Classifier.classifyLinkInNotes("Agenda: https://example.com/agenda.pdf, see you there")
        #expect(result?.0 == .fyi)
        #expect(result?.1 == .low)
        #expect(Classifier.firstHTTPSLink(in: "Agenda: https://example.com/agenda.pdf, see you there") == "https://example.com/agenda.pdf")
    }

    @Test("row 5: plain notes, http links and nil are not fyi")
    func noLink() {
        #expect(Classifier.classifyLinkInNotes("Nothing to see") == nil)
        #expect(Classifier.classifyLinkInNotes("http://insecure.example.com/x") == nil)
        #expect(Classifier.classifyLinkInNotes(nil) == nil)
        #expect(Classifier.firstHTTPSLink(in: "https://") == nil)
    }

    // MARK: Row 6 -- imported mail

    @Test("row 6: mail awaiting a reply is reply/normal, otherwise nil")
    func importedMail() {
        let result = Classifier.classifyImportedMail(awaitsReply: true)
        #expect(result?.0 == .reply)
        #expect(result?.1 == .normal)
        #expect(Classifier.classifyImportedMail(awaitsReply: false) == nil)
    }
}
