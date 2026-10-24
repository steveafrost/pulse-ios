import Foundation
import Testing
@testable import ThirdHandCore

/// The wire-parsing rules, exercised without a connection: header unfolding, RFC
/// 2047 decoding, date parsing, address lists, and the response framing the client
/// relies on.
@Suite("IMAP parsing")
struct IMAPParserTests {
    // MARK: - Header blocks

    @Test("headers unfold continuation lines and are lowercased by name")
    func unfolding() {
        let block = """
        From: Ada Lovelace <ada@example.org>
        Subject: a very long subject
         that was folded
        Date: Fri, 23 Oct 2026 18:04:11 +0000

        """
        let headers = IMAPParser.headers(from: block)
        #expect(headers["subject"] == "a very long subject that was folded")
        #expect(headers["from"] == "Ada Lovelace <ada@example.org>")
    }

    @Test("the blank line ends the header block, so a body is never parsed as headers")
    func bodyIsNotHeaders() {
        let block = "Subject: hi\r\n\r\nTo: not-a-header@x.com\r\n"
        let headers = IMAPParser.headers(from: block)
        #expect(headers["subject"] == "hi")
        #expect(headers["to"] == nil)
    }

    @Test("a header line with no colon is skipped without losing the others")
    func malformedLine() {
        let headers = IMAPParser.headers(from: "garbage line\r\nSubject: fine\r\n")
        #expect(headers["subject"] == "fine")
    }

    // MARK: - RFC 2047

    @Test("base64 and quoted-printable encoded words are decoded")
    func encodedWords() {
        #expect(MIMEText.decodeWordSequences("=?UTF-8?B?SGVsbG8=?=") == "Hello")
        #expect(MIMEText.decodeWordSequences("=?utf-8?q?Hello_World?=") == "Hello World")
        #expect(MIMEText.decodeWordSequences("=?UTF-8?Q?caf=C3=A9?=") == "café")
    }

    @Test("adjacent encoded words are joined without the fold whitespace")
    func adjacentWords() {
        // "Hello" then "World" split across two words, as a long subject arrives.
        let decoded = MIMEText.decodeWordSequences("=?UTF-8?B?SGVsbG8=?= =?UTF-8?B?V29ybGQ=?=")
        #expect(decoded == "HelloWorld")
    }

    @Test("latin-1 encoded words decode to the right characters")
    func latin1() {
        #expect(MIMEText.decodeWordSequences("=?ISO-8859-1?Q?caf=E9?=") == "café")
    }

    @Test("a broken encoded word is left visible rather than deleted")
    func brokenWord() {
        let raw = "=?UTF-8?B?not-base64-at-all!!?= tail"
        #expect(!MIMEText.decodeWordSequences(raw).isEmpty)
        #expect(MIMEText.decodeWordSequences("plain =? nonsense") == "plain =? nonsense")
    }

    @Test("whitespace including folds collapses to single spaces")
    func whitespace() {
        #expect(MIMEText.normalizeWhitespace("a\n  b\tc  ") == "a b c")
    }

    @Test("quoted-printable bodies decode, and soft breaks vanish")
    func quotedPrintable() {
        #expect(MIMEText.decodeQuotedPrintable("cost =C2=A33") == "cost £3")
        #expect(MIMEText.decodeQuotedPrintable("one=\r\ntwo") == "onetwo")
    }

    // MARK: - Dates

    @Test("an RFC 5322 date parses")
    func rfc5322Date() throws {
        let date = try #require(MailDateParser.parse("Fri, 23 Oct 2026 18:04:11 +0000"))
        #expect(date == Fixture.now)
    }

    @Test("a date with a numeric offset is honoured")
    func offsetDate() throws {
        let utc = try #require(MailDateParser.parse("Fri, 23 Oct 2026 18:04:11 +0000"))
        let plusTwo = try #require(MailDateParser.parse("Fri, 23 Oct 2026 20:04:11 +0200"))
        #expect(utc == plusTwo)
    }

    @Test("an unparseable date is nil, not a guess")
    func badDate() {
        #expect(MailDateParser.parse("not a date") == nil)
        #expect(MailDateParser.parse("") == nil)
    }

    // MARK: - Addresses

    @Test("a display name and address are separated")
    func namedAddress() throws {
        let parsed = try #require(EmailAddress.parse("Ada Lovelace <ada@example.org>"))
        #expect(parsed.name == "Ada Lovelace")
        #expect(parsed.address == "ada@example.org")
        #expect(parsed.description == "Ada Lovelace")
    }

    @Test("a quoted name containing a comma does not split the list")
    func quotedComma() {
        let list = EmailAddress.parseList("\"Lovelace, Ada\" <ada@example.org>, grace@example.org")
        #expect(list.count == 2)
        #expect(list.first?.name == "Lovelace, Ada")
        #expect(list.last?.address == "grace@example.org")
    }

    @Test("a bare address has no name and prints as itself")
    func bareAddress() throws {
        let parsed = try #require(EmailAddress.parse("<grace@example.org>"))
        #expect(parsed.name == nil)
        #expect(parsed.description == "grace@example.org")
    }

    @Test("a token that is not an address is dropped")
    func junkAddress() {
        #expect(EmailAddress.parse("not-an-address") == nil)
        #expect(EmailAddress.parse("") == nil)
        #expect(EmailAddress.parseList("undisclosed-recipients:;") == [])
    }

    @Test("addresses compare case-insensitively")
    func matching() {
        let address = EmailAddress(address: "Steve@Example.COM")
        #expect(address.matches(anyOf: ["steve@example.com"]))
        #expect(address.matches(anyOf: [" steve@example.com "]))
        #expect(!address.matches(anyOf: ["someone@example.com"]))
    }

    // MARK: - Message ids and reply detection

    @Test("message ids lose their angle brackets and keep their case")
    func messageID() {
        #expect(IMAPParser.normalizeMessageID("<abc@x>") == "abc@x")
        #expect(IMAPParser.normalizeMessageID("  <AbC@X>  ") == "AbC@X")
        #expect(IMAPParser.normalizeMessageID("<>") == nil)
        #expect(IMAPParser.normalizeMessageID("  ") == nil)
    }

    @Test("reply markers are recognised in the subject and the threading headers")
    func replyDetection() {
        #expect(IMAPParser.isReplyHeader(subject: "Re: hi", inReplyTo: nil, references: nil))
        #expect(IMAPParser.isReplyHeader(subject: "RE: hi", inReplyTo: nil, references: nil))
        #expect(IMAPParser.isReplyHeader(subject: "AW: hi", inReplyTo: nil, references: nil))
        #expect(IMAPParser.isReplyHeader(subject: "hi", inReplyTo: "x@y", references: nil))
        #expect(IMAPParser.isReplyHeader(subject: "hi", inReplyTo: nil, references: "<a> <b>"))
        #expect(!IMAPParser.isReplyHeader(subject: "hi", inReplyTo: nil, references: nil))
        // "Re:" must be a prefix, not a substring.
        #expect(!IMAPParser.isReplyHeader(subject: "Regarding the plan", inReplyTo: nil, references: nil))
    }

    @Test("a full header block becomes a snapshot")
    func fullSnapshot() {
        let block = """
        From: "Ada Lovelace" <ada@example.org>
        To: steve@example.com
        Cc: grace@example.org
        Subject: =?UTF-8?B?TG9uZ8OpIHN1YmplY3Q=?=
        Date: Fri, 23 Oct 2026 18:04:11 +0000
        Message-ID: <mid-1@example.org>

        """
        let message = IMAPParser.message(uid: 77, headerBlock: block)
        #expect(message.uid == 77)
        #expect(message.messageID == "mid-1@example.org")
        #expect(message.subject == "Longé subject")
        #expect(message.primarySender?.name == "Ada Lovelace")
        #expect(message.recipients.count == 2)
        #expect(message.effectiveDate == Fixture.now)
        #expect(!message.isReply)
    }

    // MARK: - Response framing

    @Test("a trailing literal marker is recognised and its length read")
    func literalMarker() {
        #expect(IMAPConversation.trailingLiteralCount("* 1 FETCH (BODY[HEADER] {173}") == 173)
        #expect(IMAPConversation.trailingLiteralCount("a1 OK done") == nil)
        #expect(IMAPConversation.trailingLiteralCount("text {notanumber}") == nil)
        // A brace that is not a trailing marker must not be mistaken for one.
        #expect(IMAPConversation.trailingLiteralCount("{12} more text") == nil)
    }

    @Test("a uid is read out of a FETCH response")
    func uidInResponse() {
        #expect(IMAPConversation.uid(in: "* 1 FETCH (UID 101 BODY[HEADER] {12}") == 101)
        #expect(IMAPConversation.uid(in: "* 1 FETCH (UID 101)") == 101)
        #expect(IMAPConversation.uid(in: "* 1 FETCH (BODY[])") == nil)
    }

    // MARK: - Quoting

    @Test("quoted strings escape quotes and backslashes")
    func quoting() throws {
        #expect(try IMAPQuote.string("plain") == "\"plain\"")
        #expect(try IMAPQuote.string("a\"b") == "\"a\\\"b\"")
        #expect(try IMAPQuote.string("a\\b") == "\"a\\\\b\"")
    }

    @Test("a credential with a line break is refused, not escaped")
    func injection() {
        #expect(throws: IMAPError.invalidCredential) {
            try IMAPQuote.string("pass\r\nA2 DELETE INBOX")
        }
        #expect(throws: IMAPError.invalidCredential) {
            try IMAPQuote.string("pass\nA2 DELETE INBOX")
        }
    }
}
