import Foundation

/// One unread message, as plain values.
///
/// This is the boundary between IMAP and the detector rules, exactly as
/// `CalendarEventSnapshot` is for EventKit: `IMAPClient` maps `FETCH` responses into
/// these, and every classification rule is a pure function over arrays of them. That
/// is what makes `EmailSource`'s rules testable against `FakeIMAPTransport` with no
/// server, no network and no credentials.
///
/// Only the headers capture is allowed to fetch are modelled. There is deliberately
/// no body: v1.2 judges a message by `Subject` and its address lists, which is enough
/// for the four classifications below and keeps a poll to a few kilobytes per
/// message. `docs/DEFERRED-SOURCES.md` records that body-based classification is the
/// next step.
public struct EmailMessageSnapshot: Sendable, Hashable, Identifiable {
    /// The IMAP `UID`, unique and stable within a mailbox. This is what the second
    /// half of an id is built from when a message carries no `Message-ID`.
    public var uid: UInt32
    /// The RFC 822 `Message-ID` header, verbatim, or `nil` when absent.
    ///
    /// Carried unparsed (angle brackets included) because it is an identity token,
    /// not something to display.
    public var messageID: String?
    public var subject: String
    /// `From`, in header order. RFC 5322 allows more than one.
    public var from: [EmailAddress]
    /// The full `To` header.
    public var to: [EmailAddress]
    /// The full `Cc` header. Counted as a recipient for the "you are the sole
    /// recipient" rule and as people on the card.
    public var cc: [EmailAddress]
    /// The `Date` header, or `nil` when it was absent or unparseable. Never
    /// substituted with "now" -- the caller's instant is what a pass is judged
    /// against, so an undated message simply carries no date.
    public var sentAt: Date?
    /// The server's `INTERNALDATE`, read from the same `FETCH`. Used as a fallback
    /// ordering key when `Date` is missing.
    public var receivedAt: Date?
    /// Whether the headers say this message is already part of a thread someone
    /// answered (`Re:` subject, or a non-empty `In-Reply-To`/`References`).
    ///
    /// A *header* answer, not a thread-membership answer: IMAP without `THREAD`
    /// cannot tell "the only message in a thread" from "one of nine", so the
    /// classifier treats this as a hint rather than proof. See
    /// `EmailClassifier.classifyMessage`.
    public var isReply: Bool

    public var id: UInt32 { uid }

    public init(
        uid: UInt32,
        messageID: String? = nil,
        subject: String = "",
        from: [EmailAddress] = [],
        to: [EmailAddress] = [],
        cc: [EmailAddress] = [],
        sentAt: Date? = nil,
        receivedAt: Date? = nil,
        isReply: Bool = false
    ) {
        self.uid = uid
        self.messageID = messageID
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.isReply = isReply
    }

    /// Everyone who was addressed directly, `To` then `Cc`, de-duplicated
    /// case-insensitively in that order.
    public var recipients: [EmailAddress] {
        var seen = Set<String>()
        return (to + cc).filter { seen.insert($0.address.lowercased()).inserted }
    }

    /// The first sender, which is the one a card shows and the one `people` leads
    /// with.
    public var primarySender: EmailAddress? { from.first }

    /// When the message claims to have been sent, falling back to the server's
    /// receipt instant. `nil` only when neither is known.
    public var effectiveDate: Date? { sentAt ?? receivedAt }

    /// Whether `address` appears as a recipient of this message.
    ///
    /// Used to answer "was this sent to me?", which is the difference between a
    /// newsletter and a message that wants something. Compared case-insensitively
    /// through `EmailAddress.matches`.
    public func isAddressed(to address: String) -> Bool {
        recipients.contains { $0.matches(anyOf: [address]) }
    }
}

/// RFC 2047 encoded-word decoding, plus the small amount of header cleanup a card
/// needs.
///
/// A mail header is not a `String` in any friendly sense: `Subject: =?UTF-8?B?SGVs
/// bG8=?=` is a subject of "Hello". Decoding is required for a title a person can read,
/// and it is the only place in capture where an encoding is interpreted.
public enum MIMEText {
    /// Decodes every `=?charset?encoding?text?=` word in `raw` and collapses the
    /// whitespace between adjacent encoded words (RFC 2047 §6.2 allows a long word to
    /// be split across several, and the folds are not content).
    ///
    /// Supported charsets: UTF-8 and US-ASCII, plus the ISO-8859-1/latin-1 family and
    /// Windows-1252, which is what a decade of mail servers actually emit. Anything
    /// else falls back to UTF-8, then to the raw bytes as latin-1 -- which always
    /// succeeds, so a subject is never dropped over a charset we do not know.
    ///
    /// Supported encodings: `B` (base64) and `Q` (quoted-printable with `_` for
    /// space). An encoded word that fails to decode is left as-is rather than
    /// deleted, so the user sees something rather than an empty title.
    public static func decodeWordSequences(_ raw: String) -> String {
        guard raw.contains("=?") else { return normalizeWhitespace(raw) }
        var output = ""
        var rest = Substring(raw)
        // True when the last thing appended was a decoded word, so the whitespace
        // separating it from the next encoded word can be dropped.
        var lastWasEncodedWord = false

        while let start = rest.range(of: "=?") {
            let prefix = rest[rest.startIndex..<start.lowerBound]
            appendLiteral(prefix, to: &output)
            let candidate = rest[start.lowerBound...]
            guard let word = decodeWord(candidate) else {
                // Not a well-formed encoded word: keep the two characters and keep
                // scanning from after them, so `=?` in prose does not swallow text.
                appendLiteral("=?", to: &output)
                rest = rest[rest.index(start.lowerBound, offsetBy: 2)...]
                lastWasEncodedWord = false
                continue
            }
            if lastWasEncodedWord {
                // Drop the separator between two encoded words.
                output = trimmingTrailingWhitespace(output)
            }
            output += word.decoded
            rest = rest[word.endIndex...]
            lastWasEncodedWord = true
        }
        appendLiteral(rest, to: &output)
        return normalizeWhitespace(output)
    }

    /// One decoded encoded word and where it ended.
    struct DecodedWord {
        var decoded: String
        var endIndex: String.Index
    }

    /// Parses `=?charset?enc?text?=` from the front of `text`, or `nil` when the
    /// shape does not hold.
    static func decodeWord(_ text: Substring) -> DecodedWord? {
        // `=?` charset `?` encoding `?` payload `?=`
        let parts = text.dropFirst(2)
        guard let charsetEnd = parts.firstIndex(of: "?") else { return nil }
        let charset = String(parts[parts.startIndex..<charsetEnd])
        let afterCharset = parts[parts.index(after: charsetEnd)...]
        guard let encodingEnd = afterCharset.firstIndex(of: "?") else { return nil }
        let encoding = String(afterCharset[afterCharset.startIndex..<encodingEnd]).uppercased()
        let afterEncoding = afterCharset[afterCharset.index(after: encodingEnd)...]
        guard let terminator = afterEncoding.range(of: "?=") else { return nil }
        let payload = String(afterEncoding[afterEncoding.startIndex..<terminator.lowerBound])
        guard encoding == "B" || encoding == "Q" else { return nil }

        let bytes: Data?
        switch encoding {
        case "B": bytes = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
        default: bytes = quotedPrintableBytes(payload, underscoreIsSpace: true)
        }
        guard let bytes, !bytes.isEmpty else { return nil }
        return DecodedWord(decoded: decode(bytes, charset: charset), endIndex: terminator.upperBound)
    }

    /// Bytes of a quoted-printable run. `=XX` is a byte, `=` at the very end is a soft
    /// line break and is dropped, `_` is a space when the run came from a header.
    static func quotedPrintableBytes(_ text: String, underscoreIsSpace: Bool) -> Data? {
        var bytes = Data()
        let iterator = Array(text.utf8)
        var index = 0
        while index < iterator.count {
            let byte = iterator[index]
            if byte == UInt8(ascii: "=") {
                if index + 2 < iterator.count,
                   let value = hexByte(iterator[index + 1], iterator[index + 2]) {
                    bytes.append(value)
                    index += 3
                    continue
                }
                // A soft break is `=` + CRLF (or bare LF in the wild): the `=` and the
                // line ending both vanish, which is what joins the two halves. A
                // malformed escape skips only the `=`.
                if index + 1 < iterator.count, iterator[index + 1] == UInt8(ascii: "\r") {
                    index += (index + 3 < iterator.count && iterator[index + 2] == UInt8(ascii: "\n")) ? 3 : 2
                } else if index + 1 < iterator.count, iterator[index + 1] == UInt8(ascii: "\n") {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if underscoreIsSpace, byte == UInt8(ascii: "_") {
                bytes.append(UInt8(ascii: " "))
            } else {
                bytes.append(byte)
            }
            index += 1
        }
        return bytes
    }

    /// Reverses `quotedPrintableBytes` for a mail *body* part. Not used by capture
    /// today (no bodies are fetched); provided so a future body-based classifier does
    /// not reimplement it wrongly.
    public static func decodeQuotedPrintable(_ text: String) -> String {
        guard let bytes = quotedPrintableBytes(text, underscoreIsSpace: false) else { return text }
        return decode(bytes, charset: "utf-8")
    }

    static func hexByte(_ high: UInt8, _ low: UInt8) -> UInt8? {
        guard let h = hexValue(high), let l = hexValue(low) else { return nil }
        return h << 4 | l
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }

    /// Bytes -> `String` for a charset name as it appears in a header.
    ///
    /// `String(data:encoding:)` has no ISO-8859-1 decode in Swift, so latin-1 is done
    /// by mapping each byte to the code point of the same value -- which is exactly
    /// what ISO-8859-1 is. Anything unknown falls back to UTF-8, then to latin-1, so
    /// this function is total.
    static func decode(_ data: Data, charset: String) -> String {
        let name = charset.lowercased().trimmingCharacters(in: .whitespaces)
        if name == "iso-8859-1" || name == "latin1" || name == "latin-1" || name == "windows-1252" {
            return decodeLatin1(data)
        }
        if let string = String(data: data, encoding: .utf8) { return string }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cfEncoding != kCFStringEncodingInvalidId,
           let string = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))) {
            return string
        }
        return decodeLatin1(data)
    }

    static func decodeLatin1(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in data {
            scalars.append(Unicode.Scalar(byte))
        }
        return String(scalars)
    }

    /// Collapses every run of whitespace (including the CRLF folds a header may
    /// contain) to one space and trims. A card title is one line, and a raw header
    /// that still carries a fold would otherwise render as a broken row.
    public static func normalizeWhitespace(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func appendLiteral(_ piece: Substring, to output: inout String) {
        output += piece
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        var copy = text
        while let last = copy.last, last.isWhitespace { copy.removeLast() }
        return copy
    }
}

/// Parses the `Date:` header, which is RFC 5322's format and not ISO 8601.
///
/// Two parsers because a single one is not enough: `DateFormatter` with
/// `en_US_POSIX` handles the canonical `Fri, 23 Oct 2026 18:04:11 +0000`, and
/// `ISO8601DateFormatter` catches the ISO-ish dates some senders emit instead. A date
/// that parses with neither is `nil` -- the message still becomes an item, it just
/// carries no `due`.
public enum MailDateParser {
    /// The formats tried, in order. `Z` for a `+0000` that was written as `UTC`,
    /// and the no-weekday form that some senders (and Exchange) emit.
    static let formats: [String] = [
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm Z",
        "d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
    ]

    /// A fresh formatter each call would be wasteful in a loop over hundreds of
    /// messages; a `static let` of a class-based `DateFormatter` is not `Sendable`, so
    /// the formatter is created per parse and the *lock* is avoided by making the whole
    /// parser a pure function of its input with a cached thread-local formatter array.
    private static let threadLocal: ThreadLocal = ThreadLocal()

    final class ThreadLocal: @unchecked Sendable {
        private let lock = NSLock()
        private var formatters: [DateFormatter] = []

        func resolved() -> [DateFormatter] {
            lock.lock()
            defer { lock.unlock() }
            if formatters.isEmpty {
                formatters = MailDateParser.formats.map { format in
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = format
                    return formatter
                }
            }
            return formatters
        }
    }

    /// The instant in `raw`, or `nil`.
    public static func parse(_ raw: String) -> Date? {
        let trimmed = MIMEText.normalizeWhitespace(raw)
        guard !trimmed.isEmpty else { return nil }
        for formatter in threadLocal.resolved() {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
