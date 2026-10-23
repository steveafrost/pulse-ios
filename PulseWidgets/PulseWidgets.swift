import WidgetKit
import SwiftUI
import PulseCore

struct PulseEntry: TimelineEntry {
    let date: Date
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(PulseEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        completion(Timeline(entries: [PulseEntry(date: .now)], policy: .atEnd))
    }
}

struct PulseWidgetView: View {
    var entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pulse")
                .font(.headline)
            Text("Nothing needs you yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct PulseWidget: Widget {
    let kind = "PulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            PulseWidgetView(entry: entry)
        }
        .configurationDisplayName("Pulse")
        .description("What needs you, at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PulseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PulseWidget()
    }
}
