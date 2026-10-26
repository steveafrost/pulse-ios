import ThirdHandCore
import WidgetKit

/// The timeline entry: everything the views need, snapshotted at one instant.
///
/// The projection itself is `WidgetSnapshot` (in `ThirdHandCore`), so the entry adds only
/// the render date. That keeps the count/top-N/empty logic testable in `ThirdHandTests`
/// with no widget host, which is the constraint the milestone called out.
struct ThirdHandEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// True for the placeholder and preview renders, so the view can `.redacted()` and
    /// use sample copy instead of the user's real titles.
    let isPlaceholder: Bool

    static func placeholder(at date: Date = .now) -> ThirdHandEntry {
        ThirdHandEntry(date: date, snapshot: .sample, isPlaceholder: true)
    }
}

/// Reads `board.json` from the app group and nothing else.
///
/// A `TimelineProvider` rather than an `AppIntentTimelineProvider`: there is no
/// configuration for this widget, so there is nothing for an intent to parameterise,
/// and `StaticConfiguration` keeps the widget addable with zero setup (issue #29).
struct ThirdHandProvider: TimelineProvider {
    /// Issue #29: the app also calls `WidgetCenter.reloadAllTimelines()` on every
    /// board change, so this interval is the *floor* for a widget that has not been
    /// told about a change -- e.g. while the app has not run since a midnight rollover.
    static let refreshInterval: TimeInterval = 15 * 60

    private let reader: WidgetBoardReader

    init(reader: WidgetBoardReader = WidgetBoardReader()) {
        self.reader = reader
    }

    func placeholder(in context: Context) -> ThirdHandEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (ThirdHandEntry) -> Void) {
        if context.isPreview {
            completion(ThirdHandEntry(date: .now, snapshot: .sample, isPlaceholder: true))
        } else {
            completion(ThirdHandEntry(date: .now, snapshot: reader.snapshot(), isPlaceholder: false))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThirdHandEntry>) -> Void) {
        let now = Date()
        let entry = ThirdHandEntry(date: now, snapshot: reader.snapshot(), isPlaceholder: false)
        // One entry, refreshed by the policy: the counts only change when the app
        // writes a new board, and the app pokes WidgetKit when it does.
        let next = now.addingTimeInterval(Self.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    /// The placeholder/preview board: three items at fixed, obviously-sample times.
    ///
    /// Fixed rather than "now + 40 minutes" so a preview and a screenshot are the same
    /// every render, and so the redacted state cannot leak a real title.
    static var sample: WidgetSnapshot {
        let base = Date(timeIntervalSince1970: 1_793_059_200) // 2026-10-23 09:00 UTC
        let items = [
            WidgetItem(
                sampleID: "calendar:event:sample-1",
                title: "Design review",
                kind: Kind.review.rawValue,
                priority: Priority.high.rawValue,
                due: base.addingTimeInterval(2400),
                horizon: Horizon.now.rawValue
            ),
            WidgetItem(
                sampleID: "gmail:thread:sample-2",
                title: "RSVP to Priya",
                kind: Kind.rsvp.rawValue,
                priority: Priority.high.rawValue,
                due: base.addingTimeInterval(3600),
                horizon: Horizon.now.rawValue
            ),
            WidgetItem(
                sampleID: "reminders:list:sample-3",
                title: "Send the invoice",
                kind: Kind.deadline.rawValue,
                priority: Priority.normal.rawValue,
                due: base.addingTimeInterval(7200),
                horizon: Horizon.now.rawValue
            ),
            WidgetItem(
                sampleID: "slack:message:sample-4",
                title: "Reply in #platform",
                kind: Kind.reply.rawValue,
                priority: Priority.normal.rawValue,
                due: nil,
                horizon: Horizon.now.rawValue
            )
        ]
        return WidgetSnapshot(nowCount: items.count, nowItems: items, generatedAt: base, hasBoard: true)
    }

    /// Twelve Now items, for the circular accessory's "10+" render.
    static var sampleOverflowing: WidgetSnapshot {
        let base = Date(timeIntervalSince1970: 1_793_059_200)
        let items = (1 ... 12).map { index in
            WidgetItem(
                sampleID: "reminders:list:sample-\(index)",
                title: "Reminder \(index)",
                kind: Kind.deadline.rawValue,
                priority: index <= 3 ? Priority.high.rawValue : Priority.normal.rawValue,
                due: base.addingTimeInterval(Double(index) * 900),
                horizon: Horizon.now.rawValue
            )
        }
        return WidgetSnapshot(nowCount: items.count, nowItems: items, generatedAt: base, hasBoard: true)
    }

    /// A 60-character title, for the inline widget's truncation render.
    static var sampleLongTitle: WidgetSnapshot {
        let base = Date(timeIntervalSince1970: 1_793_059_200)
        let item = WidgetItem(
            sampleID: "docs:doc:sample-long",
            title: "Review the quarterly platform architecture proposal before Friday",
            kind: Kind.review.rawValue,
            priority: Priority.high.rawValue,
            due: base.addingTimeInterval(2400),
            horizon: Horizon.now.rawValue
        )
        return WidgetSnapshot(nowCount: 1, nowItems: [item], generatedAt: base, hasBoard: true)
    }
}
