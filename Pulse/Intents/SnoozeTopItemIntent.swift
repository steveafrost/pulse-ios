import AppIntents
import Foundation
import PulseCore

/// "Snooze the top item" (issue #32): resolves the top Now item and snoozes it,
/// without opening the app.
///
/// **Execution choice: it runs out-of-process (in-app intent) and writes a `snooze`
/// command to `commands.jsonl`, not to `board.json`.** The alternative was to open the
/// app and call `ItemStore.userAction` on the main actor, which would work but would
/// throw the user into a full-screen app for a one-line action from the Lock Screen --
/// and would break the "works from the Action Button without opening anything"
/// requirement.
///
/// Writing the projection directly was rejected because `board.json` is a cache the
/// next capture pass or `publish` overwrites: the snooze would appear to work and then
/// vanish. The command log is already the app's write path for a non-foreground actor
/// (it is exactly what the Mac mirror appends), `CommandReader` dedupes it by id,
/// applies it through `ItemStore.userAction` with `by: "mirror"`-style attribution, and
/// the app drains it on next activation or background refresh. So the state cannot be
/// corrupted, and the write is the same one the app makes.
struct SnoozeTopItemIntent: AppIntent {
    static var title: LocalizedStringResource { "Snooze the top item" }

    static var description: IntentDescription {
        IntentDescription(
            "Snoozes the most urgent thing in your Now bucket until the time you choose.",
            categoryName: "Board"
        )
    }

    @Parameter(
        title: "Until",
        description: "How long to hide it for.",
        default: SnoozeDuration.tomorrowMorning
    )
    var duration: SnoozeDuration

    static var parameterSummary: some ParameterSummary {
        Summary("Snooze the top item until \(\.$duration)")
    }

    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let source = IntentBoardSource.live
        let snapshot = source.snapshot
        let now = source.now

        // Empty board: say so plainly and mutate nothing (#32 acceptance).
        guard let top = snapshot.topItem else {
            return .result(dialog: IntentDialog(stringLiteral: IntentSummary.nothingToSnooze))
        }

        let until = duration.date(from: now, calendar: source.calendar)
        do {
            try source.writer.snooze(itemID: top.id, until: until, now: now)
        } catch {
            let message = "Couldn't snooze \(top.title). Open Pulse and try again."
            return .result(dialog: IntentDialog(stringLiteral: message))
        }

        let message = IntentSummary.snoozed(title: top.title, until: until, calendar: source.calendar)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
