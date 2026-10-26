import Foundation

#if canImport(EventKit) && os(iOS)
    import EventKit

    /// `EKEventStore` is not `Sendable`, but it is documented as safe to use from a
    /// background queue for the fetch calls we make, and one `EKEventStore` should be
    /// shared per app rather than rebuilt per pass. This box carries that promise
    /// explicitly instead of marking the providers `@unchecked Sendable`, which would
    /// also silence real mistakes in the mapping code.
    final class EventStoreBox: @unchecked Sendable {
        let store: EKEventStore

        init(_ store: EKEventStore = EKEventStore()) {
            self.store = store
        }
    }

    /// The real calendar provider.
    ///
    /// This file is the only place in `ThirdHandCore` that imports EventKit for events,
    /// and it is compiled only for iOS: the package also builds for macOS so the
    /// tests can run without a simulator, and EventKit's authorization API differs
    /// there. Everything downstream of the snapshot types is platform-neutral.
    public struct EventKitEventProvider: EventProviding {
        private let box: EventStoreBox
        private let currentUserName: String?

        public init(store: EKEventStore = EKEventStore(), currentUserName: String? = nil) {
            box = EventStoreBox(store)
            self.currentUserName = currentUserName
        }

        public func events(in window: DateInterval) async throws -> [CalendarEventSnapshot] {
            let store = box.store
            do {
                let granted = try await store.requestFullAccessToEvents()
                guard granted else { throw CaptureError.denied(.calendar) }
            } catch let error as CaptureError {
                throw error
            } catch {
                throw CaptureError.underlying(error.localizedDescription)
            }

            let predicate = store.predicateForEvents(
                withStart: window.start,
                end: window.end,
                calendars: nil
            )
            let me = currentUserName
            return store.events(matching: predicate).map { Self.snapshot($0, currentUserName: me) }
        }

        /// `EKEvent` -> `CalendarEventSnapshot`. Mapping only: every decision about
        /// what the values *mean* happens in `EventKitSource`'s pure functions.
        static func snapshot(_ event: EKEvent, currentUserName: String?) -> CalendarEventSnapshot {
            let attendees = (event.attendees ?? []).map { participant in
                Attendee(
                    name: participant.name ?? "",
                    identifier: Self.identifier(for: participant),
                    status: Self.status(participant.participantStatus)
                )
            }
            return CalendarEventSnapshot(
                identifier: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                notes: event.notes,
                url: event.url?.absoluteString.hasPrefix("https://") == true ? event.url?.absoluteString : nil,
                organizerName: event.organizer?.name,
                attendees: attendees,
                currentUserStatus: Self.currentUserStatus(event: event, me: currentUserName),
                isCancelled: event.status == .canceled
            )
        }

        /// The current user's row is the one whose URL matches the store's "me"
        /// participant, falling back to an exact name match. `nil` means this event
        /// has no participation row for the user (a personal event).
        static func currentUserStatus(event: EKEvent, me: String?) -> ParticipationStatus? {
            let attendees = event.attendees ?? []
            if let mine = attendees.first(where: { $0.isCurrentUser }) {
                return status(mine.participantStatus)
            }
            if let me {
                let key = me.lowercased()
                if let match = attendees.first(where: { ($0.name ?? "").lowercased() == key }) {
                    return status(match.participantStatus)
                }
            }
            return nil
        }

        static func status(_ status: EKParticipantStatus) -> ParticipationStatus {
            switch status {
            case .accepted: .accepted
            case .declined: .declined
            case .tentative: .tentative
            case .pending: .invited
            case .delegated, .completed, .inProcess, .unknown: .unknown
            @unknown default: .unknown
            }
        }

        static func identifier(for participant: EKParticipant) -> String? {
            participant.url.absoluteString.hasPrefix("mailto:")
                ? String(participant.url.absoluteString.dropFirst("mailto:".count))
                : participant.url.absoluteString
        }
    }

    /// The real reminders provider. Same iOS-only rule as the event provider.
    public struct EventKitReminderProvider: ReminderProviding {
        private let box: EventStoreBox

        public init(store: EKEventStore = EKEventStore()) {
            box = EventStoreBox(store)
        }

        public func incompleteReminders() async throws -> [ReminderSnapshot] {
            let store = box.store
            do {
                let granted = try await store.requestFullAccessToReminders()
                guard granted else { throw CaptureError.denied(.calendar) }
            } catch let error as CaptureError {
                throw error
            } catch {
                throw CaptureError.underlying(error.localizedDescription)
            }
            return await withCheckedContinuation { continuation in
                let predicate = store.predicateForIncompleteReminders(
                    withDueDateStarting: nil,
                    ending: nil,
                    calendars: nil
                )
                store.fetchReminders(matching: predicate) { reminders in
                    let snapshots = (reminders ?? []).map(Self.snapshot)
                    continuation.resume(returning: snapshots)
                }
            }
        }

        /// `EKReminder` -> `ReminderSnapshot`. Mapping only.
        static func snapshot(_ reminder: EKReminder) -> ReminderSnapshot {
            let components = reminder.dueDateComponents
            return ReminderSnapshot(
                identifier: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                notes: reminder.notes,
                dueDate: components.flatMap { Calendar.current.date(from: $0) },
                isCompleted: reminder.isCompleted
            )
        }
    }
#endif
