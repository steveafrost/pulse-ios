import Foundation

/// The seam every detector plugs into.
///
/// A source knows how to look at one system (Calendar, Reminders, and later
/// Gmail/Slack) and turn what it finds into `[DetectedItem]`. It never touches
/// `ItemStore`, so the store never learns EventKit exists.
///
/// `now` and `window` are injected, never read from the clock: a capture pass
/// must be reproducible in tests, and a pass that takes a while must judge every
/// source against the same instant.
public protocol CaptureSource: Sendable {
    /// Which system this source speaks for. Used for reporting and for the
    /// "no permission" vs "no items" distinction on the board.
    var sourceID: Source { get }

    /// Everything this source detects in `window`, as of `now`.
    ///
    /// Throws `CaptureError` for the situations the UI must tell apart
    /// (no permission, source unavailable); any other error is reported as a
    /// failed source and does not abort the capture pass.
    func detect(now: Date, window: DateInterval) async throws -> [DetectedItem]
}

/// The ways a source can refuse to answer.
///
/// `denied` is deliberately *not* a generic failure: the UI shows "Calendar
/// access is off" with a Settings button, which is a different screen from
/// "something went wrong, try again".
public enum CaptureError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The platform cannot provide this source at all (e.g. EventKit on macOS).
    case unavailable(Source)
    /// The user has not granted access. A paused source, not a failed pass.
    case denied(Source)
    /// The fetch did not finish in the time the caller allowed.
    case timeout
    /// Anything else, already rendered for a log line.
    case underlying(String)

    /// The source this error belongs to, when the case names one.
    public var source: Source? {
        switch self {
        case .unavailable(let source), .denied(let source): source
        case .timeout, .underlying: nil
        }
    }

    public var description: String {
        switch self {
        case .unavailable(let source): "\(source.rawValue) is unavailable on this platform"
        case .denied(let source): "access to \(source.rawValue) was denied"
        case .timeout: "capture source timed out"
        case .underlying(let message): message
        }
    }
}

extension CaptureError: LocalizedError {
    public var errorDescription: String? { description }
}

/// Builds the `DateInterval` a capture pass scans, relative to an injected `now`.
///
/// All intervals are half-open-ish in the way EventKit wants (`start ..< end`),
/// and every one of them is computed from the caller's instant so a pass is
/// reproducible.
public enum CaptureWindow {
    public static let secondsPerDay: TimeInterval = 86_400
    public static let secondsPerHour: TimeInterval = 3_600

    /// The calendar day containing `now`, in `calendar`.
    public static func day(now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(secondsPerDay)
        return DateInterval(start: start, end: end)
    }

    /// `days` whole days starting at `now` -- exactly `days * 86400` seconds, so
    /// a test can assert the arithmetic without a calendar getting involved.
    public static func next(days: Int, now: Date) -> DateInterval {
        DateInterval(start: now, duration: Double(days) * secondsPerDay)
    }

    /// A rolling window centred on the task's background-refresh shape:
    /// everything from `hours` before `now` to `hours` after it.
    public static func rolling(hours: Int, now: Date) -> DateInterval {
        DateInterval(
            start: now.addingTimeInterval(-Double(hours) * secondsPerHour),
            end: now.addingTimeInterval(Double(hours) * secondsPerHour)
        )
    }

    /// From `back` seconds before `now` to `forward` seconds after it. Used by
    /// `CaptureMode.incremental`, whose window is not symmetric.
    public static func around(now: Date, back: TimeInterval, forward: TimeInterval) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-back), end: now.addingTimeInterval(forward))
    }
}
