import Foundation
import ThirdHandCore

/// The dependency container the intents use (issue #32).
///
/// An intent must be instant and must work from the Lock Screen, so it may not build a
/// store, a capture engine or a `SyncCoordinator`: those mean an actor hop, a possible
/// permission prompt, and EventKit. Everything an intent needs is in the app-group
/// projection plus the command log, and this type is the one place that knows that.
///
/// `SnoozeTopItemIntent` writes through `SnoozeCommandWriter` -- the same append-only
/// `commands.jsonl` the Mac mirror appends to -- rather than mutating `board.json` or
/// spinning up an `ItemStore`. The reason is in `SnoozeWritePath.swift`: the projection
/// is a cache, the command log is the app's real write path for anything that is not
/// the foreground UI, and the app drains it on the next activation or background
/// refresh with ack-based dedupe. Writing the cache would be a lost update.
struct IntentBoardSource: Sendable {
    var reader: WidgetBoardReader
    var writer: SnoozeCommandWriter
    var clock: @Sendable () -> Date
    var calendar: Calendar

    static var live: IntentBoardSource {
        IntentBoardSource(
            reader: WidgetBoardReader(),
            writer: SnoozeCommandWriter(),
            clock: { Date() },
            calendar: .current
        )
    }

    init(
        reader: WidgetBoardReader = WidgetBoardReader(),
        writer: SnoozeCommandWriter = SnoozeCommandWriter(),
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.reader = reader
        self.writer = writer
        self.clock = clock
        self.calendar = calendar
    }

    var snapshot: WidgetSnapshot { reader.snapshot() }
    var now: Date { clock() }
}
