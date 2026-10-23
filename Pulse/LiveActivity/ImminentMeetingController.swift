import Foundation
import PulseCore
#if canImport(ActivityKit) && os(iOS)
// `Activity` is not `Sendable`, and its `update`/`end` are `@concurrent`, so under
// Swift 6 strict concurrency every call to them from this `@MainActor` controller is
// diagnosed as sending an isolated value across. ActivityKit is correct here -- those
// methods are safe to call for one activity, and the activity is only ever touched from
// this controller -- so the SDK's declarations are imported as pre-concurrency rather
// than wrapping each call in an `unsafe` escape hatch.
@preconcurrency import ActivityKit

/// The app-side owner of the one Live Activity (issue #31).
///
/// Rules it enforces, all delegated to `ImminentItemRule` so the decision is testable
/// without ActivityKit:
///  * at most one activity at a time: a new imminent meeting ends the previous one
///    first, so `Activity<MeetingAttributes>.activities.count` never exceeds 1;
///  * start only when the item is within 60 minutes and has not already been
///    described by the running activity (a second capture pass is a no-op);
///  * end when the meeting starts (phase `.inProgress`) or its item leaves the board;
///  * never throw when the user has Live Activities disabled -- log and skip.
///
/// It is `@MainActor` because ActivityKit's request/update calls are, and because it
/// is kicked from `BoardViewModel`, which is.
@MainActor
final class ImminentMeetingController {
    /// The item id the running activity describes, so a rebuild after relaunch can
    /// adopt an activity the system already restored instead of duplicating it.
    private var runningItemID: String?
    private var ticker: Task<Void, Never>?
    private let reader: WidgetBoardReader
    private let clock: @Sendable () -> Date

    /// How often `minutesRemaining` is refreshed. The countdown is minute-granular,
    /// so a minute is the right cadence; ActivityKit budgets updates, and this is far
    /// inside the guidance.
    static let tickInterval: Duration = .seconds(60)

    init(reader: WidgetBoardReader = WidgetBoardReader(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.reader = reader
        self.clock = now
        // Adopt anything the system restored after a relaunch, so we do not start a
        // duplicate for the same meeting.
        runningItemID = Activity<MeetingAttributes>.activities.first?.attributes.itemID
    }

    /// The state the controller is in, for the debug log and tests.
    var runningActivityCount: Int { Activity<MeetingAttributes>.activities.count }

    /// Called after a capture pass, on foreground, and from the background refresh.
    ///
    /// Reads `board.json` rather than the store: the controller is kicked right after
    /// the board persists its projection, and reading the app group is what keeps this
    /// independent of the store's actor.
    func sync(hasConflict: Bool = false) async {
        let now = clock()
        let snapshot = reader.snapshot()

        // End an activity whose meeting has started or left the board.
        if let runningItemID, let running = activity(for: runningItemID) {
            let attributes = running.attributes
            if attributes.hasEnded(at: now) || ImminentItemRule.shouldEnd(runningItemID: runningItemID, snapshot: snapshot) {
                await end(running, reason: "meeting finished")
                return
            }
            if now >= attributes.startDate {
                // The meeting started: the countdown is over, the activity's job is done.
                await end(running, reason: "meeting started")
                return
            }
            await refresh(running, at: now, hasConflict: hasConflict)
            return
        }

        guard guardActivitiesEnabled() else { return }

        guard let item = ImminentItemRule.shouldStart(snapshot: snapshot, now: now, runningItemID: runningItemID),
              let start = item.due
        else { return }

        begin(item, start: start, now: now, hasConflict: hasConflict)
    }

    /// Ends whatever is running. Called when the user closes the app deliberately or
    /// the board goes empty for another reason.
    func endAll() async {
        for activity in Activity<MeetingAttributes>.activities {
            await end(activity, reason: "cleared")
        }
    }

    // MARK: Private

    private func guardActivitiesEnabled() -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Not an error: the user turned Live Activities off. Nothing to do, and
            // emphatically nothing to crash on.
            log("live activities disabled; skipping")
            return false
        }
        return true
    }

    private func activity(for itemID: String) -> Activity<MeetingAttributes>? {
        Activity<MeetingAttributes>.activities.first { $0.attributes.itemID == itemID }
    }

    private func begin(_ item: WidgetItem, start: Date, now: Date, hasConflict: Bool) {
        // A different meeting is imminent: end the old one first so there is only ever
        // one activity (#31 acceptance).
        for running in Activity<MeetingAttributes>.activities {
            if running.attributes.itemID == item.id { continue }
            Task { @MainActor in await self.end(running, reason: "replaced by \(item.id)") }
        }

        // `PulseItem` carries no end time and the projection does not invent one, so a
        // meeting is assumed to run an hour. That costs nothing to get wrong: the
        // activity ends when the meeting *starts* or its item leaves the board, so the
        // end date only bounds `staleDate`.
        let end = start.addingTimeInterval(60 * 60)
        let attributes = MeetingAttributes(
            itemID: item.id,
            title: item.title,
            startDate: start,
            endDate: end,
            people: item.people ?? []
        )
        let content = ActivityContent(state: attributes.state(at: now, hasConflict: hasConflict), staleDate: end)

        do {
            let activity = try Activity<MeetingAttributes>.request(attributes: attributes, content: content)
            runningItemID = item.id
            log("started activity for \(item.id)")
            startTicking(item.id)
        } catch {
            // `request` throws when activities are disabled or the budget is exhausted.
            // Both are "we could not show it", not failures the user must see.
            log("could not start activity: \(error)")
        }
    }

    /// `Activity` is not `Sendable`, so the call is awaited on this actor rather than
    /// hopped into a detached `Task`: the whole controller is `@MainActor`, which is
    /// where ActivityKit's own API lives.
    private func refresh(_ activity: Activity<MeetingAttributes>, at now: Date, hasConflict: Bool) async {
        let state = activity.attributes.state(at: now, hasConflict: hasConflict)
        guard state != activity.content.state else { return }
        await activity.update(ActivityContent(state: state, staleDate: activity.attributes.endDate))
    }

    private func end(_ activity: Activity<MeetingAttributes>, reason: String) async {
        if activity.attributes.itemID == runningItemID { runningItemID = nil }
        ticker?.cancel()
        ticker = nil
        log("ending activity: \(reason)")
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// Keeps `minutesRemaining` honest while the app is foregrounded. A suspended app
    /// cannot tick, and the system's own countdown does not exist here, so the state is
    /// also refreshed by `sync` on every capture pass and background refresh.
    private func startTicking(_ itemID: String) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ImminentMeetingController.tickInterval)
                guard let self, !Task.isCancelled else { return }
                await self.tick(itemID)
            }
        }
    }

    /// One tick: find the activity again (the system may have ended it) and either
    /// update the countdown or finish it.
    private func tick(_ itemID: String) async {
        guard let current = Activity<MeetingAttributes>.activities.first(where: {
            $0.attributes.itemID == itemID
        }) else { return }
        let now = clock()
        if current.attributes.hasEnded(at: now) || now >= current.attributes.startDate {
            await end(current, reason: "meeting started")
            return
        }
        await refresh(current, at: now, hasConflict: current.content.state.hasConflict)
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[Pulse] live activity: \(message)")
        #endif
    }
}
#endif
