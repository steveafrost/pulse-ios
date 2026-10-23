import AppIntents
import Foundation

/// The snooze options `SnoozeTopItemIntent` offers, as an `AppEnum` so Shortcuts can
/// pick one from a menu (issue #32).
///
/// The dates are computed, never stored, exactly like `SnoozePresets` in the app: "this
/// evening" means 18:00 today and does not exist after it. The enum is the *shape* the
/// Shortcuts UI needs; `SnoozePresets` stays the app's single source of truth for what
/// each option resolves to.
enum SnoozeDuration: String, AppEnum, CaseIterable {
    case hour
    case evening
    case tomorrowMorning

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Snooze duration")
    }

    static var caseDisplayRepresentations: [SnoozeDuration: DisplayRepresentation] {
        [
            .hour: DisplayRepresentation(title: "In an hour"),
            .evening: DisplayRepresentation(title: "This evening"),
            .tomorrowMorning: DisplayRepresentation(title: "Tomorrow morning"),
        ]
    }

    /// The instant this option resolves to, from `now`. Mirrors `SnoozePresets`, and
    /// falls back to the next sensible future instant rather than returning nil: an
    /// intent has to answer with *a* time, and "in an hour" is always in the future.
    func date(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hour:
            return now.addingTimeInterval(3_600)
        case .evening:
            // 18:00 today when it is still ahead, otherwise 18:00 tomorrow.
            let today = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
            if let today, today > now { return today }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
            return tomorrow.flatMap { calendar.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }
                ?? now.addingTimeInterval(86_400)
        case .tomorrowMorning:
            // 9:00 the next day, exactly as the app's preset does.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
                ?? tomorrow
        }
    }
}
