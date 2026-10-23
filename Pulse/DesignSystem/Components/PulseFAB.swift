import SwiftUI

/// §6.1: the FAB is glass, interactive, and the single prominent action on the
/// board. §8.1: at AX1+ it carries the topmost Now item's title above the glyph.
public struct PulseFAB: View {
    let title: String
    var caption: String?
    let systemImage: String
    var tint: Color = PulseColor.horizonNow
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        title: String,
        caption: String? = nil,
        systemImage: String = "checkmark",
        tint: Color = PulseColor.horizonNow,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.caption = caption
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    private var isAX: Bool {
        dynamicTypeSize >= .accessibility1
    }

    private var isVeryLargeAX: Bool {
        dynamicTypeSize >= .accessibility3
    }

    public var body: some View {
        Button(action: action) {
            content
                .frame(minHeight: PulseSpacing.minimumHitTarget)
        }
        .buttonStyle(.pulseProminent(tint: tint))
        .accessibilityLabel(title)
        .accessibilityHint("Runs the board's main action")
    }

    /// §8.1: at AX1+ the caption sits above the glyph, so the control becomes a
    /// short bar. It is capped in width and never lays out a label one letter per
    /// line: at AX5 an unconstrained pill covered half the board.
    @ViewBuilder
    private var content: some View {
        if isAX {
            VStack(alignment: .trailing, spacing: PulseSpacing.xxs) {
                /// §8.1 puts the item title above the glyph from AX1. Past AX2 the
                /// caption is several lines of AX5 type and the control stops being
                /// a control, so it is dropped and the label alone carries the
                /// action (the full title is still in the accessibility label and
                /// the row directly behind).
                if let caption, !isVeryLargeAX {
                    Text(caption)
                        .font(PulseTypography.meta)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                HStack(spacing: PulseSpacing.xs) {
                    glyph
                    Text(title)
                        .font(PulseTypography.buttonLabel)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 260, alignment: .trailing)
        } else {
            HStack(spacing: PulseSpacing.xs) {
                glyph
                Text(title)
                    .font(PulseTypography.buttonLabel)
                    .lineLimit(1)
            }
        }
    }

    private var glyph: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .accessibilityHidden(true)
    }
}
