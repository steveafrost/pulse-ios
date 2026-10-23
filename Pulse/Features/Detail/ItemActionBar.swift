import PulseCore
import SwiftUI

/// §8.2: the glass action bar at the bottom of the detail sheet. One primary
/// action by state, plus a secondary overflow for Dismiss / Snooze / Copy link.
public struct ItemActionBar: View {
    let item: PulseItem
    let isBusy: Bool
    var onPrimary: () -> Void
    var onDismiss: () -> Void
    var onSnooze: () -> Void
    var onCopyLink: () -> Void
    var onReopen: () -> Void

    public init(
        item: PulseItem,
        isBusy: Bool,
        onPrimary: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onCopyLink: @escaping () -> Void,
        onReopen: @escaping () -> Void
    ) {
        self.item = item
        self.isBusy = isBusy
        self.onPrimary = onPrimary
        self.onDismiss = onDismiss
        self.onSnooze = onSnooze
        self.onCopyLink = onCopyLink
        self.onReopen = onReopen
    }

    public var body: some View {
        HStack(spacing: PulseSpacing.s) {
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.pulseProminent(tint: item.status.isClosed ? PulseColor.statusDone : PulseColor.horizonNow))
                .disabled(isBusy)
                .accessibilityLabel(primaryTitle)
                .accessibilityIdentifier("detail.primary")

            Menu {
                if !item.status.isClosed {
                    Button("Snooze", systemImage: "moon.zzz", action: onSnooze)
                    Button("Dismiss", systemImage: "xmark.circle", action: onDismiss)
                }
                if item.url != nil {
                    Button("Copy link", systemImage: "link", action: onCopyLink)
                }
                if item.status.isClosed {
                    Button("Reopen", systemImage: "arrow.uturn.backward", action: onReopen)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: PulseSpacing.minimumHitTarget, height: PulseSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More actions")
            .accessibilityIdentifier("detail.more")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PulseSpacing.screenMargin)
        .padding(.vertical, PulseSpacing.xs)
        .pulseGlass(.regular, in: .rounded(PulseRadius.card))
        .accessibilityElement(children: .contain)
    }

    private var primaryTitle: String {
        if item.status.isClosed { return "Reopen" }
        if item.isSnoozed { return "Unsnooze" }
        return "Done"
    }
}
