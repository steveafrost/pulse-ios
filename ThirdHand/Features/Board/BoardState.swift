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
        /// §9.3 — the board is empty because a source is paused, not because
        /// nothing needs the user. Without this the first run after a denial
        /// renders 9.2 ("Let's see what needs you", "Connect your calendar") at
        /// someone who just said no, which is both wrong and nagging.
        case denied(SourceIdentity)
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
