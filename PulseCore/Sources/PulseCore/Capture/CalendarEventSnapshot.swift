import Foundation

/// One calendar event, as plain values.
///
/// This is the boundary between EventKit and the detector rules: `EventKitSource`
/// maps `EKEvent` into this and nothing else, and every rule is a pure function
/// over arrays of these. That is what makes the detectors testable on macOS,
/// where `EKEvent` may not even exist, without a simulator calendar or a
/// permission prompt.
public struct CalendarEventSnapshot: Sendable, Hashable, Identifiable {
    /// `EKEvent.eventIdentifier` -- the calendar database's stable id, and the
    /// `<eventIdentifier>` half of `calendar:event:<id>`.
    public var identifier: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var notes: String?
    /// `https://` only, as the contract requires of `PulseItem.url`.
    public var url: String?
    public var organizerName: String?
    public var attendees: [Attendee]
    /// The *current user's* participation, when the event has one. `nil` means
    /// this event is not a meeting the user was invited to (a personal event),
    /// so there is nothing to RSVP to.
    public var currentUserStatus: ParticipationStatus?
    public var isCancelled: Bool

    public var id: String { identifier }

    public init(
        identifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        notes: String? = nil,
        url: String? = nil,
        organizerName: String? = nil,
        attendees: [Attendee] = [],
        currentUserStatus: ParticipationStatus? = nil,
        isCancelled: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.notes = notes
        self.url = url
        self.organizerName = organizerName
        self.attendees = attendees
        self.currentUserStatus = currentUserStatus
        self.isCancelled = isCancelled
    }

    /// How long the event runs. Never negative.
    public var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }

    /// Accepted and not cancelled -- the contract's "two accepted events".
    public var isAcceptedAndLive: Bool {
        guard !isCancelled else { return false }
        switch currentUserStatus {
        case .accepted, .none: return true
        case .declined, .tentative, .invited, .unknown: return false
        }
    }

    /// The user has not answered the invite yet. `declined` is emphatically not
    /// this: the user already gave an answer.
    public var awaitsUserResponse: Bool {
        !isCancelled && currentUserStatus == .invited
    }

    /// A meeting the user may have to attend: accepted and not all-day.
    public var occupiesTime: Bool { isAcceptedAndLive && !isAllDay }
}

/// Someone on an event, plus what they said.
public struct Attendee: Sendable, Hashable {
    public var name: String
    /// An email or other identifier if the platform has one; used for the
    /// conflict hash and for de-duplication. Falls back to `name`.
    public var identifier: String?
    public var status: ParticipationStatus

    public init(name: String, identifier: String? = nil, status: ParticipationStatus = .invited) {
        self.name = name
        self.identifier = identifier
        self.status = status
    }

    /// What the conflict hash sorts on: the address when there is one, else the
    /// display name.
    public var hashKey: String { identifier ?? name }
}

/// EventKit's `EKParticipantStatus`, without the EventKit import.
public enum ParticipationStatus: String, Sendable, CaseIterable, Hashable {
    case accepted, declined, tentative, invited, unknown
}

/// Anything that can hand back calendar events for a window.
///
/// The real conformance is `EventKitEventProvider`, which needs EventKit and iOS;
/// tests and previews use `FakeEventProvider`.
public protocol EventProviding: Sendable {
    func events(in window: DateInterval) async throws -> [CalendarEventSnapshot]
}
