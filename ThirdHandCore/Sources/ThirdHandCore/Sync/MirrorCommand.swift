import Foundation

/// One line of `commands.jsonl`: a transition the Mac mirror is asking iOS to
/// apply.
///
/// Wire shape, exactly as the contract specifies:
/// ```json
/// {"id":"<uuid>","at":"<ISO>","op":"done|dismiss|snooze|reopen",
///  "itemId":"...","until":"<ISO|null>","reason":"<string|null>"}
/// ```
///
/// The mirror may never author item *content* -- only assert a transition. That is
/// why `op` is a closed set (`ItemActionVerb`) and decoding throws on anything
/// else: an unrecognised instruction must be dropped, not guessed at.
public struct MirrorCommand: Sendable, Hashable, Identifiable {
    public var id: String
    public var at: Date
    public var op: MirrorOp
    public var itemId: String
    public var until: Date?
    public var reason: String?

    public init(
        id: String = UUID().uuidString,
        at: Date,
        op: MirrorOp,
        itemId: String,
        until: Date? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.at = at
        self.op = op
        self.itemId = itemId
        self.until = until
        self.reason = reason
    }
}

// MARK: - Wire decoding

public extension MirrorCommand {
    /// The on-wire form. Separate from `MirrorCommand` so the domain type can
    /// hold real `Date`s while the JSON stays the contract's ISO strings, and so a
    /// malformed line is a decoding failure on this struct rather than a
    /// half-populated command.
    private struct Wire: Decodable {
        var id: String
        var at: Date
        var op: MirrorOp
        var itemId: String
        var until: Date?
        var reason: String?

        private enum CodingKeys: String, CodingKey {
            case id, at, op, itemId, until, reason
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            at = try c.decode(Date.self, forKey: .at)
            op = try c.decode(MirrorOp.self, forKey: .op)
            itemId = try c.decode(String.self, forKey: .itemId)
            until = try c.decodeIfPresent(Date.self, forKey: .until)
            reason = try c.decodeIfPresent(String.self, forKey: .reason)
        }
    }

    /// Parses one JSONL line. Throws when the line is not a valid command -- the
    /// caller records it as a corrupt line and moves on.
    static func decode(line: String) throws -> MirrorCommand {
        let data = Data(line.utf8)
        let wire = try ThirdHandJSON.decoder.decode(Wire.self, from: data)
        return MirrorCommand(
            id: wire.id,
            at: wire.at,
            op: wire.op,
            itemId: wire.itemId,
            until: wire.until,
            reason: wire.reason
        )
    }

    /// The ack record: `{"id":"..."}` and nothing else, so the plugin can diff ids
    /// without parsing the rest.
    var ackData: Data {
        Data(#"{"id":"\#(Self.escape(id))"}"#.utf8)
    }

    /// Minimal JSON string escaping for the id we just decoded, so a hostile id
    /// cannot produce an invalid ack line.
    internal static func escape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out
    }
}
