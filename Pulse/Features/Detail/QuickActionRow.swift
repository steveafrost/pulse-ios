import PulseCore
import SwiftUI

/// #18: each quick action — text-only shows Copy, url-only shows Open, both show
/// a Menu. The whole row is at least 44pt.
///
/// §8.2 / `docs/DATA-CONTRACT.md`: `QuickAction.label` is the **button title**,
/// written in the imperative ("Open thread", "Accept", "Open link", "Yes to
/// Oct 28"). It is not a noun describing the payload, so it is rendered as-is and
/// never quoted or prefixed with a second verb — `Label("Open “\(label)”")` turned
/// the label "Open thread" into "Open “Open thread”" and the payload into
/// "Copy “Copy action”" for any producer that named the verb.
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
        if !quickActions.isEmpty || showsStandaloneLink {
            VStack(alignment: .leading, spacing: PulseSpacing.xs) {
                Text("Quick actions")
                    .font(PulseTypography.eyebrow)
                    .foregroundStyle(PulseColor.textTertiary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
                    actionButton(action)
                }
                if let itemURL, showsStandaloneLink {
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

    /// A quick action that already opens this item's own URL is the same button,
    /// so the row must not offer both "Open thread" and "Open link" pointing at
    /// the same page.
    private var showsStandaloneLink: Bool {
        guard let itemURL else { return false }
        return !quickActions.contains { $0.url == itemURL }
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
                Label(action.label, systemImage: "ellipsis.circle")
            }
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("detail.quickAction.menu")
        } else if action.text != nil {
            Button {
                onCopy(action)
            } label: {
                Label(action.label, systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .accessibilityHint("Copies the text to the clipboard")
            .accessibilityIdentifier("detail.copy")
        } else if let url = action.url {
            Button {
                onOpen(url)
            } label: {
                Label(action.label, systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .accessibilityHint("Opens the link")
            .accessibilityIdentifier("detail.open")
        }
    }
}
