import Foundation

/// The calendar detector: one fetch, three sets of rules.
///
/// This type contains **no classification logic**. It fetches snapshots through
/// an `EventProviding`, then hands them to static pure functions
/// (`rsvpItems`, `conflictItems`, `imminentItems`, `passiveItems`) that are
/// unit-tested against plain arrays. `EventKitEventProvider` is the only file in
/// the module that mentions EventKit.
public struct EventKitSource: CaptureSource {
    public let sourceID: Source = .calendar

    private let provider: any EventProviding
    /// The current user's display name, so their own attendee row can be
    /// excluded from `people`. The user's *status* comes from
    /// `CalendarEventSnapshot.currentUserStatus`, not from name matching, so a
    /// missing name costs only a slightly longer `people` list.
    private let currentUserName: String?
    private let calendar: Calendar

    public init(
        provider: any EventProviding,
        currentUserName: String? = nil,
        calendar: Calendar = .current
    ) {
        self.provider = provider
        self.currentUserName = currentUserName
        self.calendar = calendar
    }

    public func detect(now: Date, window: DateInterval) async throws -> [DetectedItem] {
        let events = try await provider.events(in: window)
        let items = Self.detect(
            events: events,
            now: now,
            calendar: calendar,
            currentUserName: currentUserName
        )
        // A stable order -- the store sorts for display, but a deterministic
        // output makes the pass diffable in tests and logs.
        return items.sorted { $0.id < $1.id }
    }

    /// Every calendar-derived item for `events`, sorted by id and de-duplicated
    /// by id (first wins, so an event's own item beats a `passiveItems` one).
    public static func detect(
        events: [CalendarEventSnapshot],
        now: Date,
        calendar: Calendar = .current,
        currentUserName: String? = nil
    ) -> [DetectedItem] {
        var items: [DetectedItem] = []
        items += rsvpItems(events, now: now, currentUserName: currentUserName)
        items += conflictItems(events, now: now, calendar: calendar)
        items += imminentItems(events, now: now)
        // "no action needed" -- an event that already produced a row above is not
        // informational, it is on the board.
        let claimed = Set(items.map(\.id))
        items += passiveItems(events, excluding: claimed)

        var seen = Set<String>()
        return items
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
    }

    // MARK: - RSVP

    /// Row 1: the user has not answered and the event starts within 7 days.
    ///
    /// A `declined` invitation is skipped outright -- the user already answered,
    /// and "respond to this" would be a nag.
    public static func rsvpItems(
        _ events: [CalendarEventSnapshot],
        now: Date,
        currentUserName: String? = nil
    ) -> [DetectedItem] {
        events.compactMap { event in
            guard event.awaitsUserResponse else { return nil }
            guard let (kind, priority) = Classifier.classifyInvite(
                started: event.startDate,
                now: now,
                isAccepted: false
            ) else { return nil }

            return DetectedItem(
                id: ItemIdentity.event(event.identifier),
                source: .calendar,
                kind: kind,
                title: event.title,
                detail: event.notes,
                url: event.url,
                due: event.startDate,
                priority: priority,
                people: people(for: event, excluding: currentUserName),
                quickActions: acceptActions(for: event),
                reason: "invitation awaiting your response"
            )
        }
    }

    /// Organizer first, then attendee names, de-duplicated case-insensitively and
    /// with the current user removed. Names are what the card shows, so an
    /// attendee with no display name is skipped rather than shown as an address.
    public static func people(
        for event: CalendarEventSnapshot,
        excluding currentUser: String? = nil
    ) -> [String] {
        var raw: [String] = []
        if let organizer = event.organizerName { raw.append(organizer) }
        raw += event.attendees.map(\.name)

        let excluded = currentUser?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        return raw.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            if let excluded, !excluded.isEmpty, key == excluded { return nil }
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    /// One `Accept` action, only when the event carries an https link to act on.
    private static func acceptActions(for event: CalendarEventSnapshot) -> [QuickAction]? {
        guard let url = event.url else { return nil }
        return [QuickAction(label: "Accept", url: url)]
    }

    // MARK: - Conflict

    /// Row 2: two accepted events that overlap by more than 5 minutes and both
    /// start today or tomorrow. One item per pair, keyed on the pair's
    /// participant set and the day, so the same clash seen twice is one card.
    public static func conflictItems(
        _ events: [CalendarEventSnapshot],
        now: Date,
        calendar: Calendar = .current
    ) -> [DetectedItem] {
        let candidates = events.filter { $0.occupiesTime && startsTodayOrTomorrow($0.startDate, now: now, calendar: calendar) }
        guard candidates.count > 1 else { return [] }

        var items: [String: DetectedItem] = [:]
        for i in candidates.indices {
            for j in candidates.indices where j > i {
                let first = candidates[i]
                let second = candidates[j]
                let overlap = overlapInterval(first, second)
                guard overlap > Classifier.minimumConflictOverlap else { continue }
                guard let (kind, priority) = Classifier.classifyConflict() else { continue }

                // The card belongs to the day the clash happens on: the earlier
                // event's start day, in the caller's calendar.
                let day = calendar.startOfDay(for: min(first.startDate, second.startDate))
                let participants = conflictParticipants(first, second)
                let id = ItemIdentity.calendarConflict(day: day, participants: participants, calendar: calendar)
                guard items[id] == nil else { continue }

                items[id] = DetectedItem(
                    id: id,
                    source: .calendar,
                    kind: kind,
                    title: "\(first.title) overlaps \(second.title)",
                    detail: "Two accepted events overlap by \(Int(overlap / 60)) minutes.",
                    due: min(first.startDate, second.startDate),
                    priority: priority,
                    people: mergedPeople(first, second),
                    reason: "double-booked"
                )
            }
        }
        return items.values.sorted { $0.id < $1.id }
    }

    /// How many seconds two events share. Zero when they merely touch, which is
    /// why a 4-minute overlap does not conflict.
    public static func overlapInterval(_ a: CalendarEventSnapshot, _ b: CalendarEventSnapshot) -> TimeInterval {
        let start = max(a.startDate, b.startDate)
        let end = min(a.endDate, b.endDate)
        return max(0, end.timeIntervalSince(start))
    }

    private static func startsTodayOrTomorrow(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let day = calendar.startOfDay(for: date)
        return day == today || day == tomorrow
    }

    /// Both events' people, de-duplicated case-insensitively and sorted, so the
    /// card's list order does not depend on which event was seen first.
    private static func mergedPeople(_ a: CalendarEventSnapshot, _ b: CalendarEventSnapshot) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for name in people(for: a) + people(for: b) where seen.insert(name.lowercased()).inserted {
            names.append(name)
        }
        return names.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// The hash input for a pair: every attendee identifier across both events.
    /// When neither event lists anyone (a private block), the event identifiers
    /// stand in, so two different pairs can never mint the same id.
    private static func conflictParticipants(
        _ a: CalendarEventSnapshot,
        _ b: CalendarEventSnapshot
    ) -> [String] {
        let attendees = (a.attendees + b.attendees).map(\.hashKey)
        let cleanup = attendees.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return cleanup.isEmpty ? [a.identifier, b.identifier] : cleanup
    }

    // MARK: - Imminent

    /// Row 3: starts within 60 minutes and is not all-day.
    public static func imminentItems(_ events: [CalendarEventSnapshot], now: Date) -> [DetectedItem] {
        events.compactMap { event in
            guard !event.isCancelled else { return nil }
            guard let (kind, priority) = Classifier.classifyImminentEvent(
                started: event.startDate,
                now: now,
                isAllDay: event.isAllDay
            ) else { return nil }

            return DetectedItem(
                id: ItemIdentity.event(event.identifier),
                source: .calendar,
                kind: kind,
                title: event.title,
                detail: event.notes,
                url: event.url,
                due: event.startDate,
                priority: priority,
                people: people(for: event),
                reason: "starts within the hour"
            )
        }
    }

    // MARK: - Passive (fyi)

    /// Row 5 for events: a link in the notes and nothing to do. Only events that
    /// produced no other card are considered, so `fyi` never competes with an
    /// actionable row for the same event id.
    public static func passiveItems(
        _ events: [CalendarEventSnapshot],
        excluding claimed: Set<String>
    ) -> [DetectedItem] {
        events.compactMap { event in
            let id = ItemIdentity.event(event.identifier)
            guard !claimed.contains(id), !event.isCancelled else { return nil }
            guard let (kind, priority) = Classifier.classifyPassiveEvent(notes: event.notes) else { return nil }
            return DetectedItem(
                id: id,
                source: .calendar,
                kind: kind,
                title: event.title,
                detail: event.notes,
                url: event.url ?? Classifier.firstHTTPSLink(in: event.notes),
                due: event.startDate,
                priority: priority,
                people: people(for: event),
                reason: "reference material"
            )
        }
    }
}
