import AppIntents
import Foundation
import PulseCore

/// "What needs me" (issue #32): the Now bucket, spoken and displayed.
///
/// Reads only the app-group projection, so it answers in milliseconds and works from
/// Siri, Shortcuts, Spotlight and the Lock Screen with no permission prompt and no
/// capture pass. `openAppWhenRun` is false: the answer is the whole point, and opening
/// the app would hide it.
struct WhatNeedsMeIntent: AppIntent {
    static var title: LocalizedStringResource { "What needs me" }

    static var description: IntentDescription {
        IntentDescription(
            "Reads what is in your Now bucket: how many things need you, and the first couple by name.",
            categoryName: "Board"
        )
    }

    /// No parameters: the question is the whole intent, which is what makes it a
    /// one-tap Action Button shortcut.
    static var parameterSummary: some ParameterSummary {
        Summary("What needs me")
    }

    /// The board is already on disk; there is nothing worth showing the app for.
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let source = IntentBoardSource.live
        let snapshot = source.snapshot
        let summary = IntentSummary.whatNeedsMe(snapshot, now: source.now, calendar: source.calendar)
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}
