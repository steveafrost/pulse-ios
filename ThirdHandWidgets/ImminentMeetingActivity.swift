import SwiftUI
import ThirdHandCore
import WidgetKit

#if canImport(ActivityKit) && os(iOS)
    import ActivityKit

    /// The Live Activity presentation for the next imminent meeting (issue #31).
    ///
    /// The attributes and content state live in `ThirdHandCore` (`MeetingAttributes`) because
    /// the app constructs the `Activity` and the extension renders it, and both must
    /// refer to the same type. This file is only the views.
    struct ImminentMeetingActivityWidget: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: MeetingAttributes.self) { context in
                lockScreen(context)
                    .activityBackgroundTint(nil)
                    .activitySystemActionForegroundColor(nil)
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .accessibilityHidden(true)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        Text(context.state.countdownText)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                    DynamicIslandExpandedRegion(.center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.title)
                                .font(.headline)
                                .lineLimit(1)
                            if !context.attributes.peopleLine.isEmpty {
                                Text(context.attributes.peopleLine)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        if context.state.hasConflict {
                            Label("Overlaps another meeting", systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } compactLeading: {
                    Image(systemName: "calendar")
                        .accessibilityHidden(true)
                } compactTrailing: {
                    Text(compactCountdown(context))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                } minimal: {
                    Image(systemName: "calendar")
                        .accessibilityLabel("Meeting \(context.state.countdownText)")
                }
                .keylineTint(.primary)
            }
        }

        /// The Lock Screen presentation: title, countdown, people, conflict hint.
        private func lockScreen(_ context: ActivityViewContext<MeetingAttributes>) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(context.state.countdownText)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                        if !context.attributes.peopleLine.isEmpty {
                            Text("\u{00B7}")
                                .foregroundStyle(.secondary)
                            Text(context.attributes.peopleLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if context.state.hasConflict {
                        Label("Overlaps another meeting", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }

        /// The compact trailing slot is ~4 characters wide; "42m" fits, "in 42 min" does
        /// not, so the compact form drops the preposition and the word.
        private func compactCountdown(_ context: ActivityViewContext<MeetingAttributes>) -> String {
            switch context.state.phase {
            case .starting: "now"
            case .inProgress: "live"
            case .upcoming: "\(context.state.minutesRemaining)m"
            }
        }
    }

    // MARK: - Previews

    #if DEBUG
        extension MeetingAttributes {
            /// A meeting starting in 40 minutes: the imminent case the activity exists for.
            static var preview: MeetingAttributes {
                MeetingAttributes(
                    itemID: "calendar:event:preview-imminent",
                    title: "Design review",
                    startDate: Date(timeIntervalSinceNow: 40 * 60),
                    endDate: Date(timeIntervalSinceNow: 70 * 60),
                    people: ["Priya Raman", "Marco Silva", "Ana Costa"]
                )
            }

            /// The same meeting with a second accepted event overlapping it.
            static var previewConflict: MeetingAttributes {
                MeetingAttributes(
                    itemID: "calendar:event:preview-conflict",
                    title: "Platform sync",
                    startDate: Date(timeIntervalSinceNow: 12 * 60),
                    endDate: Date(timeIntervalSinceNow: 55 * 60),
                    people: ["Marco Silva"]
                )
            }

            static var previewStates: [MeetingAttributes.ContentState] {
                [
                    MeetingAttributes.ContentState(phase: .upcoming, minutesRemaining: 40),
                    MeetingAttributes.ContentState(phase: .starting, minutesRemaining: 0),
                    MeetingAttributes.ContentState(phase: .inProgress, minutesRemaining: 0, hasConflict: true)
                ]
            }
        }

        #Preview("Lock Screen", as: .content, using: MeetingAttributes.preview) {
            ImminentMeetingActivityWidget()
        } contentStates: {
            MeetingAttributes.previewStates[0]
            MeetingAttributes.ContentState(phase: .upcoming, minutesRemaining: 40, hasConflict: true)
        }

        #Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: MeetingAttributes.preview) {
            ImminentMeetingActivityWidget()
        } contentStates: {
            MeetingAttributes.previewStates[0]
            MeetingAttributes.ContentState(phase: .upcoming, minutesRemaining: 40, hasConflict: true)
        }

        #Preview("Compact", as: .dynamicIsland(.compact), using: MeetingAttributes.preview) {
            ImminentMeetingActivityWidget()
        } contentStates: {
            MeetingAttributes.previewStates[0]
            MeetingAttributes.previewStates[1]
        }

        #Preview("Minimal", as: .dynamicIsland(.minimal), using: MeetingAttributes.preview) {
            ImminentMeetingActivityWidget()
        } contentStates: {
            MeetingAttributes.previewStates[0]
        }
    #endif
#endif
