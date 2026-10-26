import Foundation
import ThirdHandCore

/// The board's filter (§8.1): a search query, and nothing else.
///
/// This used to carry a `source` too, driven by a row of chips ("All 7",
/// "Calendar", "Reminders", …) pinned above the board. Those chips are gone. Which
/// sources are connected is a Settings fact, and filtering the board down to one
/// of them was a way of slicing a list the user can already see the whole of —
/// the horizon sections are the only grouping that changes what needs doing.
///
/// `source` is kept as a value so a board persisted by an older build cannot fail
/// to restore, but the board never sets it and `matches` ignores it.
public struct BoardFilter: Sendable, Hashable {
    /// Retained for decoding only; never applied. See the type comment.
    public var source: SourceIdentity?
    public var query: String

    public init(source: SourceIdentity? = nil, query: String = "") {
        self.source = source
        self.query = query
    }

    public static let all = BoardFilter()

    /// True when a search is narrowing the board. Drives the "nothing matches"
    /// empty state and the reset affordance.
    public var isActive: Bool {
        !trimmedQuery.isEmpty
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func matches(_ item: ThirdHandItem) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        let haystack = [item.title, item.detail, item.people.joined(separator: " ")]
            .joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(trimmedQuery)
    }

    public func apply(to items: [ThirdHandItem]) -> [ThirdHandItem] {
        isActive ? items.filter(matches) : items
    }
}
