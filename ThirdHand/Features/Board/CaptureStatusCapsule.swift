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
            HStack(spacing: ThirdHandSpacing.xs) {
                Image(systemName: glyph)
                    .font(ThirdHandTypography.captureCapsule)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(status.text(now: now))
                        .font(ThirdHandTypography.captureCapsule)
                        .foregroundStyle(status.isFailed ? ThirdHandColor.statusError : ThirdHandColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                    if let syncText = status.syncText {
                        Text(syncText)
                            .font(ThirdHandTypography.captureCapsule)
                            .foregroundStyle(ThirdHandColor.textTertiary)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, ThirdHandSpacing.s)
            .padding(.vertical, ThirdHandSpacing.xs)
            .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
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
        if status.isFailed { return ThirdHandColor.statusError }
        if status.isCapturing { return ThirdHandColor.horizonNow }
        return ThirdHandColor.statusDone
    }

    /// §8.1: the capsule is one element. The visible line is already a sentence,
    /// so this only has to say the count and the time without repeating the
    /// implementation words the second line shows; "Mac mirror" named a file the
    /// user has never seen and is VoiceOver's only way to reach it, so it reads
    /// "On your Mac" instead.
    private var accessibilityText: String {
        CaptureCopy.accessibility(status, now: now)
    }
}
