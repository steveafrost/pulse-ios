import SwiftUI

/// §8.3 / #19: a medium sheet of computed presets plus a future-only date picker.
public struct SnoozeMenu: View {
    let now: Date
    var calendar: Calendar = .current
    var onSnooze: (Date) -> Void

    @State private var picked: Date
    @State private var isPicking = false
    @Environment(\.dismiss) private var dismiss

    public init(now: Date, calendar: Calendar = .current, onSnooze: @escaping (Date) -> Void) {
        self.now = now
        self.calendar = calendar
        self.onSnooze = onSnooze
        _picked = State(initialValue: now.addingTimeInterval(3600))
    }

    private var presets: SnoozePresets {
        SnoozePresets(now: now, calendar: calendar)
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(presets.all) { preset in
                    Button {
                        onSnooze(preset.date)
                        dismiss()
                    } label: {
                        HStack {
                            Text(preset.label)
                            Spacer()
                            Text(preset.detail)
                                .foregroundStyle(ThirdHandColor.textTertiary)
                        }
                        .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                    }
                    .accessibilityIdentifier("snooze.preset.\(preset.label)")
                }

                Section {
                    DatePicker(
                        "Pick a time",
                        selection: $picked,
                        in: now...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .accessibilityIdentifier("snooze.datePicker")
                    Button("Snooze until then") {
                        onSnooze(picked)
                        dismiss()
                    }
                    .disabled(picked <= now)
                    .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                }
            }
            .navigationTitle("Snooze")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
