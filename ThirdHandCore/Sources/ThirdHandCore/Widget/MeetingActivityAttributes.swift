import Foundation
#if canImport(ActivityKit) && os(iOS)
    import ActivityKit

    /// The Live Activity's shape (issue #31).
    ///
    /// It lives in `ThirdHandCore` rather than in the extension because two targets need the
    /// *same* type: the extension declares `ActivityConfiguration(for:)`, and the app
    /// constructs the `Activity<MeetingAttributes>` it requests. A type declared in the
    /// extension would be invisible to the app, and a duplicate would fail to match at
    /// runtime.
    ///
    /// `ActivityAttributes` is only available with ActivityKit, so the whole type is
    /// guarded: the package still builds for macOS (where the core tests run) with the
    /// type simply absent.
    public struct MeetingAttributes: ActivityAttributes {
        /// The part of the activity that changes while it is live.
        public struct ContentState: Codable, Hashable, Sendable {
            /// Where the meeting is in its lifecycle. Drives the copy and whether the
            /// activity is still worth showing.
            public enum Phase: String, Codable, Hashable, Sendable {
                case upcoming, starting, inProgress
            }

            public var phase: Phase
            /// Whole minutes until the start, floored at 0. Updated once a minute.
            public var minutesRemaining: Int
            /// A second accepted event overlaps this one, so the user is double-booked.
            public var hasConflict: Bool

            public init(phase: Phase, minutesRemaining: Int, hasConflict: Bool = false) {
                self.phase = phase
                self.minutesRemaining = minutesRemaining
                self.hasConflict = hasConflict
            }

            /// "in 12 min" / "starting now" / "in progress".
            public var countdownText: String {
                switch phase {
                case .upcoming: minutesRemaining <= 0 ? "starting now" : "in \(minutesRemaining) min"
                case .starting: "starting now"
                case .inProgress: "in progress"
                }
            }
        }

        /// The item id, so a running activity can be matched against a fresh board and
        /// ended or replaced without guessing (`ImminentItemRule.shouldStart`).
        public var itemID: String
        public var title: String
        public var startDate: Date
        public var endDate: Date
        public var people: [String]

        public init(itemID: String, title: String, startDate: Date, endDate: Date, people: [String] = []) {
            self.itemID = itemID
            self.title = title
            self.startDate = startDate
            self.endDate = endDate
            self.people = people
        }

        /// The content state for `now`. Pure, so the controller updates it on a timer
        /// without inventing a clock.
        public func state(at now: Date, hasConflict: Bool = false) -> ContentState {
            let remaining = startDate.timeIntervalSince(now)
            let phase: ContentState.Phase = if now >= endDate {
                .inProgress
            } else if now >= startDate {
                .inProgress
            } else if remaining <= 60 {
                .starting
            } else {
                .upcoming
            }
            return ContentState(
                phase: phase,
                minutesRemaining: max(0, Int(remaining / 60)),
                hasConflict: hasConflict
            )
        }

        /// Whether the meeting has finished, so the controller can end the activity.
        public func hasEnded(at now: Date) -> Bool {
            now >= endDate
        }

        /// "With Priya and Marco" for the expanded presentation; empty when solo.
        public var peopleLine: String {
            guard !people.isEmpty else { return "" }
            let firstNames = people.prefix(2).map { $0.split(separator: " ").first.map(String.init) ?? $0 }
            let extra = people.count - min(people.count, 2)
            let joined = firstNames.joined(separator: ", ")
            return extra > 0 ? "With \(joined) +\(extra)" : "With \(joined)"
        }
    }
#endif
