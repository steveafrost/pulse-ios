import Foundation
import Testing
@testable import ThirdHandCore

/// The rule table in `EmailClassifier`, one assertion per rule and per boundary.
@Suite("EmailClassifier")
struct EmailClassificationTests {
    private func classify(
        _ subject: String,
        detail: String? = nil,
        recipients: [EmailAddress]? = nil,
        isReply: Bool = false
    ) -> EmailClassifier.Classification {
        EmailClassifier.classify(
            subject: subject,
            detail: detail,
            recipients: recipients ?? [EmailFixture.me],
            userAddress: "steve@example.com",
            isReply: isReply
        )
    }

    // MARK: - Deadline

    @Test("a deadline phrase makes a high-priority deadline")
    func deadline() {
        let result = classify("Invoice due Friday")
        #expect(result.kind == .deadline)
        #expect(result.priority == .high)
        #expect(result.reason.contains("deadline"))
    }

    @Test("deadline outranks a question mark in the same subject")
    func deadlineOutranksQuestion() {
        #expect(classify("Can you confirm the deadline?").kind == .deadline)
    }

    @Test("every documented deadline phrase is recognised")
    func deadlinePhrases() {
        for phrase in EmailClassifier.deadlinePhrases {
            #expect(classify("Something \(phrase) something").kind == .deadline, "\(phrase) should be a deadline")
        }
    }

    // MARK: - Decision

    @Test("a decision phrase makes a decision, outranking the sole-recipient rule")
    func decision() {
        let result = classify("Should we ship this week")
        #expect(result.kind == .decision)
        #expect(result.priority == .normal)
    }

    @Test("every documented decision phrase is recognised")
    func decisionPhrases() {
        for phrase in EmailClassifier.decisionPhrases {
            #expect(classify("Note: \(phrase)").kind == .decision, "\(phrase) should be a decision")
        }
    }

    // MARK: - Solo recipient

    @Test("a message addressed only to the user is a reply")
    func soleRecipient() {
        let result = classify("Numbers for last quarter")
        #expect(result.kind == .reply)
        #expect(result.priority == .normal)
        #expect(result.reason == "only you were addressed")
    }

    @Test("the user's own address in a different case still counts as the sole recipient")
    func caseInsensitiveSelf() {
        let result = classify("Anything", recipients: [EmailAddress(address: "STEVE@Example.com")])
        #expect(result.kind == .reply)
    }

    @Test("a message with another recipient is a followup, not a direct reply")
    func multipleRecipients() {
        let result = classify("Numbers", recipients: [EmailFixture.me, EmailFixture.colleague])
        #expect(result.kind == .followup)
    }

    @Test("a cc counts as a recipient for the sole-recipient rule")
    func ccCounts() {
        let result = classify("Numbers", recipients: [EmailFixture.me, EmailFixture.colleague])
        #expect(result.kind != .reply)
    }

    // MARK: - Question and fallback

    @Test("a question mark in the detail is a reply when the message has other recipients")
    func question() {
        let result = classify(
            "Thoughts",
            detail: "Do you have time?",
            recipients: [EmailFixture.me, EmailFixture.colleague]
        )
        #expect(result.kind == .reply)
        #expect(result.reason.contains("question"))
    }

    @Test("a question mark in the subject is a reply")
    func questionInSubject() {
        let result = classify("Any thoughts?", recipients: [EmailFixture.me, EmailFixture.colleague])
        #expect(result.kind == .reply)
        #expect(result.reason.contains("question"))
    }

    @Test("a question mark in the detail is enough even with several recipients")
    func questionInDetail() {
        let result = classify(
            "Notes",
            detail: "Is this right?",
            recipients: [EmailFixture.me, EmailFixture.colleague]
        )
        #expect(result.kind == .reply)
    }

    @Test("an unclassified direct message is a followup at normal priority")
    func followup() {
        let result = classify(
            "Weekly summary",
            recipients: [EmailFixture.me, EmailFixture.colleague]
        )
        #expect(result.kind == .followup)
        #expect(result.priority == .normal)
    }

    @Test("a reply marker demotes the sole-recipient rule to followup")
    func replyDemotes() {
        let result = classify("Numbers", isReply: true)
        #expect(result.kind == .followup)
        #expect(result.reason == "part of an unread thread")
    }

    // MARK: - The never-fyi invariant

    @Test("no direct unread message is ever fyi or low priority")
    func neverFYI() {
        let subjects = [
            "", " ", "Re: x", "Fwd: x", "Weekly digest", "Meeting notes",
            "FYI", "fyi: something", "No action needed", "Newsletter vol 4",
        ]
        let recipientSets: [[EmailAddress]] = [
            [EmailFixture.me],
            [EmailFixture.me, EmailFixture.colleague],
            [],
        ]
        for subject in subjects {
            for recipients in recipientSets {
                for isReply in [false, true] {
                    let result = EmailClassifier.classify(
                        subject: subject,
                        detail: nil,
                        recipients: recipients,
                        userAddress: "steve@example.com",
                        isReply: isReply
                    )
                    #expect(result.kind != .fyi, "\(subject) / \(recipients.count) recipients")
                    #expect(result.priority != .low, "\(subject) / \(recipients.count) recipients")
                }
            }
        }
    }

    @Test("a subject that literally says FYI does not become fyi")
    func literalFYIText() {
        // Addressed only to the user, so it is a reply; the point is that the word
        // "FYI" in the subject cannot file it under "Nice to Know".
        #expect(classify("FYI: the build is green").kind == .reply)
        #expect(classify("FYI: the build is green").kind != .fyi)
        #expect(
            classify("FYI: the build is green", recipients: [EmailFixture.me, EmailFixture.colleague]).kind
                != .fyi
        )
    }

    // MARK: - Message snapshot helpers

    @Test("recipients merge To and Cc without duplicates")
    func recipientsMerge() {
        let message = EmailMessageSnapshot(
            uid: 1,
            to: [EmailFixture.me, EmailFixture.colleague],
            cc: [EmailAddress(address: "GRACE@example.org"), EmailAddress(address: "linus@example.org")]
        )
        #expect(message.recipients.map(\.address) == [
            "steve@example.com", "grace@example.org", "linus@example.org",
        ])
    }

    @Test("a message is addressed to the user only when they are a recipient")
    func addressedTo() {
        let message = EmailFixture.snapshot()
        #expect(message.isAddressed(to: "steve@example.com"))
        #expect(message.isAddressed(to: "STEVE@EXAMPLE.COM"))
        #expect(!message.isAddressed(to: "someone@example.com"))
    }

    @Test("the effective date falls back to receipt time, and is nil when neither is known")
    func effectiveDate() {
        let sent = Fixture.now
        let received = Fixture.now.addingTimeInterval(60)
        #expect(EmailMessageSnapshot(uid: 1, sentAt: sent, receivedAt: received).effectiveDate == sent)
        #expect(EmailMessageSnapshot(uid: 1, receivedAt: received).effectiveDate == received)
        #expect(EmailMessageSnapshot(uid: 1).effectiveDate == nil)
    }
}
