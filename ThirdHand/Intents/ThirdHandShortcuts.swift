import AppIntents

/// The Shortcuts/Spotlight registration (issue #32).
///
/// `AppShortcutsProvider` is what makes both actions appear in the Shortcuts app with no
/// user setup and makes Siri understand the phrases. The phrases must each contain the
/// app name -- the system uses it to route the utterance, so does `applicationName`.
struct ThirdHandShortcuts: AppShortcutsProvider {
    /// Both intents, each with the phrase, icon and short title Shortcuts shows.
    ///
    /// The Action Button accepts any of these: assigning "Shortcut" runs the intent
    /// directly, because `openAppWhenRun` is false for both.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatNeedsMeIntent(),
            phrases: [
                "What needs me in \(.applicationName)",
                "Ask \(.applicationName) what needs me",
            ],
            shortTitle: "What needs me",
            systemImageName: "exclamationmark.circle"
        )
        AppShortcut(
            intent: SnoozeTopItemIntent(),
            phrases: [
                "Snooze the top item in \(.applicationName)",
                "Snooze what needs me in \(.applicationName)",
            ],
            shortTitle: "Snooze top item",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
