import Foundation

// MARK: - Lenient wire enums

//
// The snapshot is produced by this app but *read* by other implementations
// (the `bb-plugin-thirdhand` mirror, and later possibly a newer iOS build). A
// value this build has never heard of must not make a whole parse fail: that
// would turn "the Mac plugin added a source" into "the app shows nothing".
//
// Policy, per the contract's versioning section:
//   `Source`   -> `.other`     (the contract's own catch-all bucket)
//   `Kind`     -> `.followup`  (the generic, non-alarming classification)
//   `Status`   -> `.open`      (never hide an item from the board because of
//                               a value we cannot reason about; `.open` is
//                               also what the state machine treats as mutable)
//   `Priority` -> `.normal`    (neither jumps the Now queue nor disappears)
//
// Each substitution is recorded through `DecodeDiagnostics` so a caller can
// log it instead of losing the signal silently.

/// A wire enum that can decode an unknown string instead of throwing.
public protocol LenientWireEnum: RawRepresentable, Codable, Sendable, Hashable where RawValue == String {
    /// Value substituted when the payload carries a string this build does not know.
    static var fallback: Self { get }
}

public extension LenientWireEnum {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let value = Self(rawValue: raw) {
            self = value
        } else {
            DecodeDiagnostics.shared.record(type: String(describing: Self.self), value: raw)
            self = Self.fallback
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Thread-safe record of lenient-decoding substitutions.
///
/// Deliberately tiny and bounded: this is a diagnostic breadcrumb, not telemetry
/// (the app collects nothing off device). The most recent events are kept so a
/// sync layer can attach them to a log line.
public final class DecodeDiagnostics: @unchecked Sendable {
    public struct Event: Sendable, Equatable {
        public let type: String
        public let value: String
        public init(type: String, value: String) {
            self.type = type
            self.value = value
        }
    }

    public static let shared = DecodeDiagnostics()

    private let lock = NSLock()
    private var events: [Event] = []
    private let capacity: Int

    public init(capacity: Int = 32) {
        self.capacity = capacity
    }

    public func record(type: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        events.append(Event(type: type, value: value))
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    /// The recorded substitutions, oldest first.
    public func recent() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll()
    }
}
