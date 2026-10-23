import SwiftUI

/// §8.1 / §6.1: the glass pill showing "12 items · 2m ago", "Capturing…", or
/// "Couldn't refresh · Try again". Tinted `HorizonNow` only while capturing or
/// while an error pends; a tap forces a capture.
public struct CaptureStatusCapsule: View {
    let status: CaptureStatusModel
    let now: Date
    var onRetry: () -> Void

    public init(status: CaptureStatusModel, now: Date, onRetry: @escaping () -> Void) {
        self.status = status
        self.now = now
        self.onRetry = onRetry
    }

    public var body: some View {
        Button(action: onRetry) {
            HStack(spacing: PulseSpacing.xs) {
                Image(systemName: glyph)
                    .font(PulseTypography.captureCapsule)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(status.text(now: now))
                    .font(PulseTypography.captureCapsule)
                    .foregroundStyle(status.isFailed ? PulseColor.statusError : PulseColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, PulseSpacing.s)
            .padding(.vertical, PulseSpacing.xs)
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pulseGlass(status.isCapturing || status.isFailed ? .tintedUrgent : .regular, in: .capsule)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Refreshes the board")
        .accessibilityIdentifier("board.captureCapsule")
    }

    private var glyph: String {
        if status.isFailed {
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
        if status.isCapturing { return "arrow.trianglehead.2.clockwise.rotate.90" }
        return "checkmark.circle"
    }

    private var tint: Color {
        if status.isFailed { return PulseColor.statusError }
        if status.isCapturing { return PulseColor.horizonNow }
        return PulseColor.statusDone
    }

    private var accessibilityText: String {
        if status.isFailed { return "Couldn't refresh. Try again." }
        if status.isCapturing { return "Capturing" }
        guard let date = status.lastCapturedAt else { return "Not captured yet" }
        return "\(status.itemCount) items, updated \(PulseDateFormat.relative(date, now: now))"
    }
}
