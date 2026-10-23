#if DEBUG
import PulseCore
import SwiftUI

/// §16: every token and component in both appearances. No fixed point sizes.
public struct DesignSystemGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                colourSection
                typeSection
                componentSection
            }
            .padding(PulseSpacing.screenMargin)
        }
        .background(PulseColor.surfaceCanvas)
    }

    private var colourSection: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.xs) {
            Text("Colour").font(PulseTypography.sectionHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: PulseSpacing.xs) {
                swatch("TextPrimary", PulseColor.textPrimary)
                swatch("TextSecondary", PulseColor.textSecondary)
                swatch("TextTertiary", PulseColor.textTertiary)
                swatch("SurfaceCanvas", PulseColor.surfaceCanvas)
                swatch("SurfaceCard", PulseColor.surfaceCard)
                swatch("HorizonNow", PulseColor.horizonNow)
                swatch("HorizonNext", PulseColor.horizonNext)
                swatch("HorizonLater", PulseColor.horizonLater)
                swatch("HorizonFYI", PulseColor.horizonFYI)
                swatch("SourceCalendar", PulseColor.sourceCalendar)
                swatch("SourceReminders", PulseColor.sourceReminders)
                swatch("SourceGmail", PulseColor.sourceGmail)
                swatch("KindNeutral", PulseColor.kindNeutral)
                swatch("KindAttention", PulseColor.kindAttention)
                swatch("KindDeadline", PulseColor.kindDeadline)
                swatch("StatusWaiting", PulseColor.statusWaiting)
                swatch("StatusSnoozed", PulseColor.statusSnoozed)
                swatch("StatusDone", PulseColor.statusDone)
                swatch("StatusError", PulseColor.statusError)
            }
        }
    }

    private func swatch(_ name: String, _ colour: Color) -> some View {
        HStack(spacing: PulseSpacing.xs) {
            RoundedRectangle(cornerRadius: 6)
                .fill(colour)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(PulseColor.separator))
            Text(name)
                .font(PulseTypography.chip)
                .foregroundStyle(PulseColor.textSecondary)
                .lineLimit(1)
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.xs) {
            Text("Type").font(PulseTypography.sectionHeader)
            Text("Board title").font(PulseTypography.boardTitle)
            Text("Section header").font(PulseTypography.sectionHeader)
            Text("Section hint").font(PulseTypography.sectionHint)
            Text("Item title").font(PulseTypography.itemTitle)
            Text("Item detail").font(PulseTypography.itemDetail)
            Text("Meta line").font(PulseTypography.meta)
            Text("Chip").font(PulseTypography.chip)
            Text("Button label").font(PulseTypography.buttonLabel)
        }
        .foregroundStyle(PulseColor.textPrimary)
    }

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.m) {
            Text("Components").font(PulseTypography.sectionHeader)

            HStack(spacing: PulseSpacing.xs) {
                PulseBadge(source: .calendar)
                PulseBadge(source: .reminders)
                PulseBadge(kind: .decision)
                PulseBadge(kind: .fyi)
            }

            HStack(spacing: PulseSpacing.xs) {
                PulseCapsuleButton("All", isSelected: true, badge: "3") {}
                PulseCapsuleButton("Calendar", systemImage: "calendar", isSelected: false) {}
            }
            .pulseGlassContainer()

            PulseSectionHeader(horizon: .now, count: 3)

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

            PulseFAB(title: "Done", caption: "Pick the launch date", systemImage: "checkmark") {}
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
