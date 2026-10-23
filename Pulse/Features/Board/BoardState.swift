import Foundation

/// The board's whole visible state (#20). One enum so an impossible combination
/// (loading *and* failed) cannot be represented, and so every preview is a case.
public enum BoardState: Sendable, Equatable {
    case loading
    case ready
    case empty(EmptyReason)
    case degraded([SourceFailure])
    case failed(String)

    /// §9: three genuinely different empty screens.
    public enum EmptyReason: Sendable, Equatable {
        /// 9.1 — captured before, nothing needs the user.
        case allClear
        /// 9.2 — no source has ever produced an item.
        case neverCaptured
        /// Filter/query excludes everything.
        case filtered
    }

    public var showsSections: Bool {
        switch self {
        case .ready, .degraded: true
        case .loading, .empty, .failed: false
        }
    }

    public var failures: [SourceFailure] {
        if case .degraded(let failures) = self { return failures }
        return []
    }
}
