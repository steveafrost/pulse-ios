import Foundation
import ThirdHandCore

/// The board's filter (§8.1). A value type with a `matches` predicate, so the
/// view model owns the state and the view only renders it. Persisted by
/// `SharedStore.Key.boardFilter` as the identity's raw value; `nil` means "All".
public struct BoardFilter: Sendable, Hashable {
    public var source: SourceIdentity?
    public var query: String

    public init(source: SourceIdentity? = nil, query: String = "") {
        self.source = source
        self.query = query
    }

    public static let all = BoardFilter()

    public var isActive: Bool {
        source != nil || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func matches(_ item: ThirdHandItem) -> Bool {
        if let source, item.sourceIdentity != source { return false }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [item.title, item.detail, item.people.joined(separator: " ")].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(trimmed)
    }

    public func apply(to items: [ThirdHandItem]) -> [ThirdHandItem] {
        isActive ? items.filter(matches) : items
    }
}
