import PulseCore
import SwiftUI

/// #18: each quick action — text-only shows Copy, url-only shows Open, both show
/// a Menu. The whole row is at least 44pt.
public struct QuickActionRow: View {
    let quickActions: [QuickAction]
    let itemURL: String?
    var onCopy: (QuickAction) -> Void
    var onOpen: (String) -> Void

    public init(
        quickActions: [QuickAction],
        itemURL: String?,
        onCopy: @escaping (QuickAction) -> Void,
        onOpen: @escaping (String) -> Void
    ) {
        self.quickActions = quickActions
        self.itemURL = itemURL
        self.onCopy = onCopy
        self.onOpen = onOpen
    }

    public var body: some View {
        if !quickActions.isEmpty || itemURL != nil {
            VStack(alignment: .leading, spacing: PulseSpacing.xs) {
                Text("Quick actions")
                    .font(PulseTypography.eyebrow)
                    .foregroundStyle(PulseColor.textTertiary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
                    actionButton(action)
                }
                if let itemURL {
                    Button {
                        onOpen(itemURL)
                    } label: {
                        Label("Open link", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: PulseSpacing.minimumHitTarget)
                    .accessibilityIdentifier("detail.openLink")
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: QuickAction) -> some View {
        if action.text != nil, action.url != nil {
            Menu {
                Button("Copy", systemImage: "doc.on.doc") { onCopy(action) }
                if let url = action.url {
                    Button("Open", systemImage: "arrow.up.right.square") { onOpen(url) }
                }
            } label: {
                Label(action.label, systemImage: "doc.on.doc")
            }
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .buttonStyle(.bordered)
        } else if action.text != nil {
            Button {
                onCopy(action)
            } label: {
                Label("Copy “\(action.label)”", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .accessibilityIdentifier("detail.copy")
        } else if let url = action.url {
            Button {
                onOpen(url)
            } label: {
                Label("Open “\(action.label)”", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .accessibilityIdentifier("detail.open")
        }
    }
}
