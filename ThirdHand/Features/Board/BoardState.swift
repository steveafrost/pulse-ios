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

        /// The source a paused-board state names, or `.calendar` for the reasons that
        /// name none. The board uses it to send "Open Settings" to the right place: a
        /// paused mailbox is fixed by the mailbox form, everything else by iOS Settings.
        public var pausedSource: SourceIdentity {
            if case let .denied(identity) = self {
                return identity
            }
            return .calendar
        }
    }

    public var showsSections: Bool {
        switch self {
        case .ready, .degraded: true
        case .loading, .empty, .failed: false
        }
    }

    public var failures: [SourceFailure] {
        if case let .degraded(failures) = self {
            return failures
        }
        return []
    }
}
