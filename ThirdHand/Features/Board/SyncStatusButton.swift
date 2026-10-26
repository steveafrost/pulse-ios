import SwiftUI
import ThirdHandCore

/// The board's sync indicator: one small glyph in the navigation bar that opens a
/// popover with the last capture time and any source that could not be read.
///
/// This replaces the wide "12 items · 2d ago" capsule that used to sit under the
/// title. That capsule carried three facts in a strip that pushed the whole board
/// down, and it doubled as the refresh button, so a tap meant two different things
/// depending on state. The count and the age are still reachable — they are here —
/// but the board itself now starts with the first section instead of with chrome.
///
/// It deliberately does **not** capture on tap. Pull-to-refresh does that on the
/// board, and a status readout that also mutates state is the same conflation the
/// capsule suffered from.
public struct SyncStatusButton: View {
    let status: CaptureStatusModel
    let failures: [SourceFailure]
    let now: Date

    @State private var isShowingDetail = false

    public init(status: CaptureStatusModel, failures: [SourceFailure] = [], now: Date) {
        self.status = status
        self.failures = failures
        self.now = now
    }

    public var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            Image(systemName: glyph)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .opacity(status.isCapturing ? 0.6 : 1)
        }
        .accessibilityIdentifier("board.syncStatus")
        .accessibilityLabel(CaptureCopy.accessibility(status, now: now))
        .accessibilityHint("Shows when the board last updated and anything that needs attention")
        .popover(isPresented: $isShowingDetail, arrowEdge: .top) {
            detail
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: Glyph and tint

    /// Three states, and they must be distinguishable without colour: a failure is
    /// an exclamation, a pass in flight is a spinner, a settled board is a tick.
    private var glyph: String {
        if status.isFailed || !failures.isEmpty {
            return "exclamationmark.triangle"
        }
        if status.isCapturing {
            return "arrow.trianglehead.2.clockwise.rotate.90"
        }
        return "checkmark.circle"
    }

    private var tint: Color {
        if status.isFailed || !failures.isEmpty {
            return ThirdHandColor.horizonNow
        }
        if status.isCapturing {
            return ThirdHandColor.textSecondary
        }
        return ThirdHandColor.statusDone
    }

    // MARK: Popover

    private var detail: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
            Text("Last updated")
                .font(ThirdHandTypography.sectionHeader)
                .foregroundStyle(ThirdHandColor.textPrimary)

            Text(lastUpdatedLine)
                .font(ThirdHandTypography.itemDetail)
                .foregroundStyle(ThirdHandColor.textSecondary)

            if let syncText = status.syncText {
                Text(syncText)
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.textTertiary)
            }

            if !failures.isEmpty {
                Divider()
                // One row per source that could not be read. The same sentences the
                // board's banners use, so the two cannot describe a failure
                // differently.
                ForEach(failures) { failure in
                    Label(failure.message, systemImage: failure.identity.systemImage)
                        .font(ThirdHandTypography.meta)
                        .foregroundStyle(ThirdHandColor.textSecondary)
                }
            }

            Divider()

            Text("Pull down on the board to check again.")
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textTertiary)
        }
        .padding(ThirdHandSpacing.m)
        .frame(idealWidth: 300, alignment: .leading)
        .accessibilityIdentifier("board.syncStatus.detail")
    }

    /// The count belongs in the tooltip rather than on the board: "12 items" was
    /// never what the user needed at a glance, and the board already shows the
    /// items. The age is the part that was doing real work. Delegated to
    /// `CaptureCopy` so the wording is covered by tests.
    private var lastUpdatedLine: String {
        CaptureCopy.syncDetail(status, now: now)
    }
}
