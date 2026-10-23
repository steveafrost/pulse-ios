import Foundation

/// What one `upsert` pass did, item by item.
///
/// Mirrors the `{ created, updated, unchanged, resolved, keptUserState, reopened }`
/// summary that `upsert` returns in `lib/store.mjs`. These are *reports*, not
/// state: the store's items are the state.
public struct UpsertResult: Sendable, Hashable {
    /// An item whose mutable fields changed. `fields` names them the way the Node
    /// store does in its history (`["title", "due"]`), plus the synthetic
    /// `"reopened"` and `"snooze-expired"` markers.
    public struct Update: Sendable, Hashable, CustomStringConvertible {
        public var id: PulseItem.ID
        public var fields: [String]

        public init(id: PulseItem.ID, fields: [String]) {
            self.id = id
            self.fields = fields
        }

        /// `"calendar:event:x [title,due]"`, byte-identical to the Node summary.
        public var description: String { "\(id) [\(fields.joined(separator: ","))]" }
    }

    /// An item the pass saw but did not touch because the user's state is sticky.
    public struct KeptUserState: Sendable, Hashable, CustomStringConvertible {
        public var id: PulseItem.ID
        public var status: Status

        public init(id: PulseItem.ID, status: Status) {
            self.id = id
            self.status = status
        }

        /// `"calendar:event:x (done)"`, byte-identical to the Node summary.
        public var description: String { "\(id) (\(status.rawValue))" }
    }

    public var created: [PulseItem.ID] = []
    public var updated: [Update] = []
    public var unchanged: [PulseItem.ID] = []
    /// Items the pass moved to `resolved` because they are no longer detected.
    public var resolved: [PulseItem.ID] = []
    public var keptUserState: [KeptUserState] = []
    /// Items the pass reopened with an explicit `reopen: true` + reason.
    public var reopened: [PulseItem.ID] = []

    public init() {}

    /// Every id whose state actually changed, in the order the pass saw them.
    public var changedIDs: [PulseItem.ID] { created + resolved + reopened + updated.map(\.id) }

    /// Nothing changed at all -- the cheap "no republish needed" check.
    public var isEmpty: Bool {
        created.isEmpty && updated.isEmpty && unchanged.isEmpty
            && resolved.isEmpty && keptUserState.isEmpty && reopened.isEmpty
    }

    /// One line per item, matching the Node CLI's output.
    public var summaryLines: [String] {
        var lines: [String] = []
        lines += created.map { "created \($0)" }
        lines += updated.map(\.description)
        lines += resolved.map { "resolved \($0)" }
        lines += reopened.map { "reopened \($0)" }
        lines += keptUserState.map { "kept \($0)" }
        lines += unchanged.map { "unchanged \($0)" }
        return lines
    }
}
