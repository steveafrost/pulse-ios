import Foundation

/// §10: every count that reaches a string goes through here.
///
/// One helper instead of `"\(count) item\(count == 1 ? "" : "s")"` at each surface,
/// because that pattern is how "1 items" ships: it was written correctly in three
/// places and wrongly in others, and the wrong ones are the ones a user sees while
/// capturing. `Plural` keeps the count and the noun adjacent, so the only way to
/// print a count is to name its noun.
public enum Plural {
    /// "0 items", "1 item", "2 items". `plural` is only needed for an irregular
    /// noun ("1 entry" / "2 entries"); the default is `singular + "s"`.
    public static func count(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(noun(count, singular, plural))"
    }

    /// The noun alone: "item" for 1, "items" otherwise.
    public static func noun(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        if count == 1 {
            return singular
        }
        return plural ?? singular + "s"
    }

    /// The board's unit of work: "1 item" / "12 items".
    public static func items(_ value: Int) -> String {
        count(value, "item")
    }

    /// The intent's unit of work: "1 thing needs you" / "3 things need you".
    public static func things(_ value: Int) -> String {
        count(value, "thing")
    }
}
