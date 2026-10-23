import Foundation

// MARK: - Wire date coding
//
// The contract stores dates as ISO 8601 strings, always UTC, e.g.
// `2026-10-23T18:04:11.000Z`. The plugin's `isoOrNull`/`now()` always emit
// `Date.prototype.toISOString()`, i.e. **millisecond** precision with a `Z`
// suffix, so that is what we write. We accept anything `Date.ISO8601FormatStyle`
// can parse on the way in, with or without fractional seconds, so a hand-edited
// file or a differently-formatted peer still decodes.

/// Formats and parses the contract's ISO 8601 instants.
///
/// Wrapping `ISO8601DateFormatter` rather than `Date.ISO8601FormatStyle` is
/// deliberate: the format style *truncates* the fractional part, so a
/// `Date(timeIntervalSince1970: ...1234)` writes `.123` and then fails to
/// round-trip. `ISO8601DateFormatter` rounds to the nearest millisecond, which
/// is what JavaScript's `toISOString()` does and what the contract needs.
///
/// The formatter is a class and not `Sendable`, so the pair lives behind a lock
/// and is exposed only through value-typed `string(from:)`/`date(from:)`.
public struct PulseDateCoding: Sendable, Hashable {
    public init() {}

    /// The contract's canonical string for an instant: always UTC, always three
    /// fractional digits, always a `Z` suffix.
    public func string(from date: Date) -> String {
        PulseFormatters.shared.write { $0.string(from: date) }
    }

    /// Parses a contract instant. Accepts fractional and non-fractional forms,
    /// and offsets other than `Z` (they normalise to UTC).
    public func date(from string: String) -> Date? {
        PulseFormatters.shared.read(string)
    }

    public static func == (lhs: PulseDateCoding, rhs: PulseDateCoding) -> Bool { true }
    public func hash(into hasher: inout Hasher) { hasher.combine(0) }
}

/// The two `ISO8601DateFormatter` instances, created once and guarded by a lock.
private final class PulseFormatters: @unchecked Sendable {
    static let shared = PulseFormatters()

    private let lock = NSLock()
    private let withFraction: ISO8601DateFormatter
    private let withoutFraction: ISO8601DateFormatter

    private init() {
        // A formatter configured for writing; `string(from:)` always emits UTC
        // with `Z` because `withTimeZone` is not set.
        let writer = ISO8601DateFormatter()
        writer.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        writer.timeZone = TimeZone(secondsFromGMT: 0)
        withFraction = writer

        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime]
        reader.timeZone = TimeZone(secondsFromGMT: 0)
        withoutFraction = reader
    }

    func write(_ body: (ISO8601DateFormatter) -> String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return body(withFraction)
    }

    func read(_ string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        // Fractional first, then plain, so `".123Z"` and `"Z"` both land.
        return withFraction.date(from: string) ?? withoutFraction.date(from: string)
    }
}

// MARK: - Shared coders

public enum PulseJSON {
    /// The one date strategy both coders use.
    public static let dates = PulseDateCoding()

    /// Encoder for everything Pulse writes: snapshot, command acks, tests.
    public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dates.string(from: date))
        }
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return encoder
    }

    /// Decoder for everything Pulse reads.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = dates.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "expected an ISO 8601 instant, got \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    public static let encoder = makeEncoder()
    public static let decoder = makeDecoder()

    /// Encodes with the shared configuration, optionally pretty-printed the way
    /// the snapshot file on disk is.
    public static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = false) throws -> Data {
        try makeEncoder(prettyPrinted: prettyPrinted).encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
