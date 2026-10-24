# Third Hand iOS — Architecture

## Product

Third Hand answers one question: *what needs me right now?* It reads your calendar,
reminders and (later) mail, classifies each thing into an action kind, and shows
one board sorted into **Now / Next / Later / Nice to Know**. Done and Snooze
stick. It exists standalone on iOS and also drives the existing bb plugin as a
mirror, so the same board is on the Mac nav rail.

## Targets

| Target | Kind | Purpose |
| --- | --- | --- |
| `Third Hand` | iOS app | The board, item detail, settings, capture scheduling. |
| `ThirdHandCore` | Swift package | Models, store, capture engine, sync. No UI. Unit-testable on macOS. |
| `ThirdHandWidgets` | Widget extension | Home Screen + Lock Screen widgets, Live Activity for the next meeting. |
| `ThirdHandIntents` | App Intents (in app) | Siri/Shortcuts: "What needs me", "Snooze the top item". |
| `ThirdHandTests` | Unit + UI tests | Store state machine, capture rules, sync protocol. |

`ThirdHandCore` is a local Swift package so it can be tested with `swift test`
without a simulator, which is what CI runs on every push.

## Layers

```
┌─────────────────────────────────────────────────┐
│ ThirdHandUI (SwiftUI)   BoardView, ItemDetail, ...  │
├─────────────────────────────────────────────────┤
│ ThirdHandCore                                       │
│  ├ Models      ThirdHandItem, enums, Ports          │
│  ├ Store       ItemStore (actor) - state machine│
│  ├ Capture     CaptureEngine, Detectors,        │
│  │             EventKitSource, RemindersSource  │
│  └ Sync        SnapshotWriter, CommandReader,   │
│                CloudContainer                   │
├─────────────────────────────────────────────────┤
│ Platform: SwiftData, EventKit, WidgetKit,       │
│           BackgroundTasks, CloudKit/iCloud      │
└─────────────────────────────────────────────────┘
```

### ItemStore

An `actor`. The only writer of item state. Pure Swift, no EventKit, no
filesystem — it takes `[DetectedItem]` in and returns changed ids. That makes the
whole sticky-state machine testable in milliseconds.

### CaptureEngine

Runs detectors against an injected `Date` and returns `[DetectedItem]`. Each
source is a protocol:

```swift
protocol CaptureSource {
    var sourceID: Source { get }
    func detect(now: Date, window: DateInterval) async throws -> [DetectedItem]
}
```

`EventKitSource` and `RemindersSource` are real; `FakeSource` is used in tests
and in SwiftUI previews. This is also the seam where Gmail/Slack plug in later
without touching the store or the UI.

### Sync

`SnapshotWriter` serialises the store to `snapshot.json` (atomic).
`CommandReader` tails `commands.jsonl`, returns `[MirrorCommand]`, and acks.
Both take a `CloudContainer` protocol so tests run against a temp directory and
the app uses the iCloud ubiquity container.

The Mac plugin uses the *same JSON shape* against a plain folder. See
`docs/DATA-CONTRACT.md`.

## Design language

Apple's current iOS design, built on **Liquid Glass** for floating chrome, with a
deliberately restrained content layer so the board stays readable:

- Content is opaque, calm, SF-styled cards — no glass on text.
- Glass is reserved for chrome that floats over content: the filter bar, the
  capture status capsule, the floating action button, sheets and the tab bar.
- `.glassEffect()` / `GlassEffectContainer` for grouping, `glassProminent`
  buttons for the single primary action per screen.
- Tinted glass for Now (urgent) vs neutral for Later.
- Motion: a matched-geometry row-to-detail transition, spring `.snappy`, and a
  soft `.symbolEffect(.bounce)` on state change. Nothing else animates.
- Full Dynamic Type, VoiceOver labels on every row action, Reduce Motion and
  Reduce Transparency respected (glass falls back to a solid material).

The visual spec, component inventory and screenshot checklist live in
`docs/DESIGN.md`.

## Scheduling

| Trigger | What runs |
| --- | --- |
| App foreground | Full capture pass, immediate |
| `BGAppRefreshTask` (~30 min cadence, OS-decided) | Incremental capture |
| Widget timeline (15 min) | Reads the last snapshot, no capture |
| Snooze expiry | Evaluated on every read (`effectiveStatus`) |

Capture is cheap (one EventKit fetch), so freshness comes from the foreground
pass plus widget reloads rather than aggressive background work.

## Privacy

Everything on device. No account, no server, no analytics. Calendar/Reminders
permission is requested at first launch with a pre-permission explainer screen.
The iCloud snapshot is the only thing that leaves the device and it goes to the
user's own private iCloud. This drives the App Privacy answers: **Data Not
Collected**.

## Milestones

| # | Milestone | Exit criteria |
| --- | --- | --- |
| M0 | Foundation | Repo, contract, architecture, CI, XcodeGen project builds empty app |
| M1 | Core domain | `ThirdHandCore` models + store state machine, green unit tests |
| M2 | Capture | EventKit + Reminders detectors, classification, green tests |
| M3 | UI | Board, detail, actions, Liquid Glass chrome, empty/error states |
| M4 | Sync + plugin mirror | Snapshot/command protocol both sides, plugin reads iOS data |
| M5 | Widgets + Intents | Home/Lock widgets, Live Activity, App Intents |
| M6 | Ship | TestFlight build uploaded, beta group invited |
