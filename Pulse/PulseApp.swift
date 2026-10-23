import SwiftUI
import PulseCore

@main
struct PulseApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
    }
}

/// Temporary landing screen. Replaced by the real board (M2).
private struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Pulse")
                .font(.largeTitle.bold())
            Text("One board of what needs you. Coming together now.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

#Preview {
    PlaceholderView()
}
