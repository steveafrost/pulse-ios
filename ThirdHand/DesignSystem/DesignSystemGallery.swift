#if DEBUG
import ThirdHandCore
import SwiftUI

/// §16: every token and component in both appearances. No fixed point sizes.
public struct DesignSystemGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThirdHandSpacing.xxl) {
                colourSection
                typeSection
                componentSection
            }
            .padding(ThirdHandSpacing.screenMargin)
        }
        .background(ThirdHandColor.surfaceCanvas)
    }

    private var colourSection: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
            Text("Colour").font(ThirdHandTypography.sectionHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: ThirdHandSpacing.xs) {
                swatch("TextPrimary", ThirdHandColor.textPrimary)
                swatch("TextSecondary", ThirdHandColor.textSecondary)
                swatch("TextTertiary", ThirdHandColor.textTertiary)
                swatch("SurfaceCanvas", ThirdHandColor.surfaceCanvas)
                swatch("SurfaceCard", ThirdHandColor.surfaceCard)
                swatch("HorizonNow", ThirdHandColor.horizonNow)
                swatch("HorizonNext", ThirdHandColor.horizonNext)
                swatch("HorizonLater", ThirdHandColor.horizonLater)
                swatch("HorizonFYI", ThirdHandColor.horizonFYI)
                swatch("SourceCalendar", ThirdHandColor.sourceCalendar)
                swatch("SourceReminders", ThirdHandColor.sourceReminders)
                swatch("SourceGmail", ThirdHandColor.sourceGmail)
                swatch("KindNeutral", ThirdHandColor.kindNeutral)
                swatch("KindAttention", ThirdHandColor.kindAttention)
                swatch("KindDeadline", ThirdHandColor.kindDeadline)
                swatch("StatusWaiting", ThirdHandColor.statusWaiting)
                swatch("StatusSnoozed", ThirdHandColor.statusSnoozed)
                swatch("StatusDone", ThirdHandColor.statusDone)
                swatch("StatusError", ThirdHandColor.statusError)
            }
        }
    }

    private func swatch(_ name: String, _ colour: Color) -> some View {
        HStack(spacing: ThirdHandSpacing.xs) {
            RoundedRectangle(cornerRadius: 6)
                .fill(colour)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(ThirdHandColor.separator))
            Text(name)
                .font(ThirdHandTypography.chip)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .lineLimit(1)
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
            Text("Type").font(ThirdHandTypography.sectionHeader)
            Text("Board title").font(ThirdHandTypography.boardTitle)
            Text("Section header").font(ThirdHandTypography.sectionHeader)
            Text("Section hint").font(ThirdHandTypography.sectionHint)
            Text("Item title").font(ThirdHandTypography.itemTitle)
            Text("Item detail").font(ThirdHandTypography.itemDetail)
            Text("Meta line").font(ThirdHandTypography.meta)
            Text("Chip").font(ThirdHandTypography.chip)
            Text("Button label").font(ThirdHandTypography.buttonLabel)
        }
        .foregroundStyle(ThirdHandColor.textPrimary)
    }

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.m) {
            Text("Components").font(ThirdHandTypography.sectionHeader)

            HStack(spacing: ThirdHandSpacing.xs) {
                ThirdHandBadge(source: .calendar)
                ThirdHandBadge(source: .reminders)
                ThirdHandBadge(kind: .decision)
                ThirdHandBadge(kind: .fyi)
            }

            HStack(spacing: ThirdHandSpacing.xs) {
                ThirdHandCapsuleButton("All", isSelected: true, badge: "3") {}
                ThirdHandCapsuleButton("Calendar", systemImage: "calendar", isSelected: false) {}
            }
            .thirdHandGlassContainer()

            ThirdHandSectionHeader(horizon: .now, count: 3)

            BoardItemRow(
                item: Fixtures.highPriorityRSVP,
                horizon: .now,
                now: Fixtures.fixtureNow,
                isNew: true,
                onAction: { _ in },
                onOpen: {}
            )

            Button("Primary action") {}
                .buttonStyle(.pulseProminent())

            CaptureStatusCapsule(
                status: CaptureStatusModel(phase: .idle(Fixtures.ago(120)), itemCount: 12),
                now: Fixtures.fixtureNow,
                onRetry: {}
            )

            ThirdHandFAB(title: "Done", caption: "Pick the launch date", systemImage: "checkmark") {}
        }
    }
}

#Preview("Preview: DesignSystemGallery — light") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}

#Preview("Preview: DesignSystemGallery — dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}
#endif
