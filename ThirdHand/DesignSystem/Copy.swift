import Foundation
import ThirdHandCore

/// §5.3 / §8.1: the sentences a count goes into, in one place so they can be
/// asserted without a view. Each one used to be an interpolated literal inside a
/// modifier, which is why "Now, 1 items" and "History, 1 entries" both shipped.
public enum BoardCopy {
    /// §10: the section header reads "Now, 2 items".
    public static func sectionHeader(_ horizon: Horizon, count: Int) -> String {
        "\(horizon.title), \(Plural.items(count))"
    }

    /// §8.1: the filter bar's "12 items shown" line.
    public static func shown(_ count: Int) -> String {
        "\(Plural.items(count)) shown"
    }

    /// The search field's placeholder. "the board" rather than "items": the user
    /// searches what they are looking at, not a data type.
    public static let searchPrompt = "Search the board"

    /// §4.1: "Show 4 more in Now". The horizon is named, so no row noun appears.
    public static func showMore(_ hidden: Int, in horizon: Horizon) -> String {
        "Show \(hidden) more in \(horizon.title)"
    }

    /// §4.1 after expansion. Says the noun, because "Show less" alone left
    /// VoiceOver with no object while the visible rows had collapsed to three.
    public static func showFewer(in horizon: Horizon) -> String {
        "Show fewer items in \(horizon.title)"
    }

    /// §18: "History, 3 entries".
    public static func history(_ count: Int) -> String {
        "History, \(Plural.count(count, "entry", "entries"))"
    }

    /// #19: "Load 12 more items" — the count the next tap reveals.
    public static func loadMore(_ remaining: Int) -> String {
        "Load \(Plural.count(remaining, "more item"))"
    }
}

/// §8.1: the capture capsule and its VoiceOver sentence. Both name the user's Mac,
/// never the transport ("snapshot", "publish", "mirror" are file words).
public enum CaptureCopy {
    public static func line(_ status: CaptureStatusModel, now: Date) -> String {
        switch status.phase {
        case .capturing:
            return "Looking for what needs you…"
        case .failed:
            return "Couldn't refresh · Try again"
        case .idle(let date):
            guard let date else { return "Not checked yet" }
            return "\(Plural.items(status.itemCount)) · \(ThirdHandDateFormat.relative(date, now: now))"
        }
    }

    /// The sync popover's headline line. Lives here rather than in the view so the
    /// sentences can be asserted: it is the only place the board now says how old
    /// its data is, and "2d ago" vs "Not checked yet" is the difference between a
    /// stale board and an empty one.
    ///
    /// Every branch names what happened, never what the code did (§8.1): no
    /// "snapshot", "mirror", "publish" or "sync".
    public static func syncDetail(_ status: CaptureStatusModel, now: Date) -> String {
        switch status.phase {
        case .capturing:
            return "Checking now…"
        case .failed(let date):
            guard let date else { return "Couldn't check the board" }
            return "Couldn't check · last worked \(ThirdHandDateFormat.relative(date, now: now))"
        case .idle(let date):
            guard let date else { return "Not checked yet" }
            return "Checked \(ThirdHandDateFormat.relative(date, now: now)) · \(Plural.items(status.itemCount))"
        }
    }

    public static func accessibility(_ status: CaptureStatusModel, now: Date) -> String {
        switch status.phase {
        case .failed:
            return "Couldn't refresh. Double-tap to try again."
        case .capturing:
            return "Looking for what needs you"
        case .idle(let date):
            guard let date else { return "Not checked yet" }
            let base = "\(Plural.items(status.itemCount)), updated \(ThirdHandDateFormat.relative(date, now: now))"
            guard let sync = status.syncText else { return base }
            return "\(base). Your Mac: \(sync)"
        }
    }
}
