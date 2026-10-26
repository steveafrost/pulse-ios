import SwiftUI
import ThirdHandCore

/// #19: the review screen for done / dismissed / resolved items.
public struct ClosedItemsView: View {
    @State private var model: ClosedItemsViewModel
    @State private var reopenTarget: ThirdHandItem?
    @State private var reason = ""
    @Environment(\.dismiss) private var dismiss

    public init(model: ClosedItemsViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.groups.isEmpty {
                    ContentUnavailableView(
                        "Nothing closed recently",
                        systemImage: "checkmark.circle",
                        description: Text(
                            "Items you finish or dismiss appear here for three days, so you can reopen them."
                        )
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Recently closed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.load() }
        .sheet(item: $reopenTarget) { item in
            ReopenPrompt(reason: $reason) {
                let submitted = reason
                reason = ""
                reopenTarget = nil
                Task { await model.reopen(item, reason: submitted) }
            }
            .pulseSheetChrome()
        }
        .accessibilityIdentifier("closed.root")
    }

    private var list: some View {
        List {
            ForEach(model.groups) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        row(item)
                    }
                }
            }
            if model.canLoadMore {
                // #19: a bare "Load more" leaves the user guessing; the count is
                // already known from `allClosed`, so name it.
                Button(BoardCopy.loadMore(model.remainingCount)) { model.loadMore() }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ item: ThirdHandItem) -> some View {
        HStack(alignment: .top, spacing: ThirdHandSpacing.xs) {
            Image(systemName: item.status == .done ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(item.status.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(ThirdHandTypography.itemTitle)
                    .foregroundStyle(ThirdHandColor.textPrimary)
                if let resolution = item.resolution, !resolution.isEmpty {
                    Text(resolution)
                        .font(ThirdHandTypography.meta)
                        .foregroundStyle(ThirdHandColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button("Reopen") {
                reason = ""
                reopenTarget = item
            }
            .font(ThirdHandTypography.meta)
            .buttonStyle(.bordered)
            .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
            .accessibilityLabel("Reopen \(item.title)")
            .accessibilityIdentifier("closed.reopen.\(item.id)")
        }
        .accessibilityElement(children: .combine)
    }
}
