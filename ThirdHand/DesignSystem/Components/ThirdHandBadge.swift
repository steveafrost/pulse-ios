import SwiftUI
import ThirdHandCore

/// §2 chip: `.caption2` `.medium`, foreground = token, background = same token
/// @12% (22% at increased contrast), `RoundedRectangle(cornerRadius: 4)`,
/// padding H6 V2. Never wraps.
public struct ThirdHandBadge: View {
    let text: String
    let tint: Color
    var systemImage: String?

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ text: String, tint: Color, systemImage: String? = nil) {
        self.text = text
        self.tint = tint
        self.systemImage = systemImage
    }

    public init(source: SourceIdentity) {
        self.init(source.title, tint: source.tint, systemImage: source.systemImage)
    }

    public init(kind: Kind) {
        self.init(kind.title, tint: kind.tint, systemImage: kind.systemImage)
    }

    public var body: some View {
        HStack(spacing: ThirdHandSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(ThirdHandTypography.chip)
        .lineLimit(1)
        // §2 "never wraps" holds at standard sizes. At AX sizes `.fixedSize()`
        // makes the chip demand its full scaled width, which widens the whole
        // card past the screen; there the chip compresses instead.
        .fixedSize(horizontal: dynamicTypeSize < .accessibility1, vertical: true)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: ThirdHandRadius.chip, style: .continuous)
                .fill(tint.opacity(ThirdHandContrast(colorSchemeContrast: contrast).chipFillOpacity))
        )
    }
}
