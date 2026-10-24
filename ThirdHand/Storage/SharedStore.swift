import Foundation
import ThirdHandCore

/// A tiny keyed store over `UserDefaults(suiteName:)`, so the last-viewed marker
/// and the board filter are visible to the widget extension (#21).
///
/// Deliberately minimal: the real sync layer is a later milestone. Nothing here
/// holds item content — that is `board.json` via `WidgetBoardStore`.
@MainActor
public struct SharedStore {
    public enum Key: String, Sendable, CaseIterable {
        case lastViewedAt = "pulse.lastViewedAt"
        case boardFilter = "pulse.boardFilter"
        case lastCaptureAt = "pulse.lastCaptureAt"
        case collapsedSections = "pulse.collapsedSections"
    }

    private let defaults: UserDefaults

    /// Uses the app-group suite, falling back to standard defaults when the suite
    /// is unavailable (simulator without entitlement, preview).
    public init(suiteName: String = AppGroup.identifier) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func date(_ key: Key) -> Date? {
        defaults.object(forKey: key.rawValue) as? Date
    }

    public func set(_ date: Date?, for key: Key) {
        if let date {
            defaults.set(date, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    public func string(_ key: Key) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    public func set(_ value: String?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
