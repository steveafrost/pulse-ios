import SwiftUI
import ThirdHandCore

/// §8.1: one horizontally scrolling row of glass chips — "All 11", then one per
/// source present in the Calendar / Reminders / Email / Slack / Docs order — plus
/// a search field and a reset. §6.3: the chips share one `GlassEffectContainer`.
public struct BoardFilterBar: View {
    let sources: [(identity: SourceIdentity, count: Int)]
    let totalCount: Int
    let nowCount: Int
    let filter: BoardFilter
    var onChange: (BoardFilter) -> Void
    var onReset: () -> Void

    @State private var query: String = ""
    @State private var isSearching = false

    public init(
        sources: [(identity: SourceIdentity, count: Int)],
        totalCount: Int,
        nowCount: Int,
        filter: BoardFilter,
        onChange: @escaping (BoardFilter) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.sources = sources
        self.totalCount = totalCount
        self.nowCount = nowCount
        self.filter = filter
        self.onChange = onChange
        self.onReset = onReset
    }

    public var body: some View {
        VStack(spacing: ThirdHandSpacing.xs) {
            if isSearching {
                searchField
            }
            chips
            if filter.isActive || filter.source != nil {
                resetRow
            }
        }
        .onAppear { query = filter.query }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: ThirdHandSpacing.xs) {
                ThirdHandCapsuleButton(
                    "All",
                    isSelected: filter.source == nil,
                    badge: nowCount > 0 ? "\(nowCount)" : nil
                ) {
                    onChange(BoardFilter(source: nil, query: filter.query))
                }
                .accessibilityIdentifier("board.filter.all")

                ForEach(sources, id: \.identity) { entry in
                    ThirdHandCapsuleButton(
                        entry.identity.title,
                        systemImage: entry.identity.systemImage,
                        isSelected: filter.source == entry.identity
                    ) {
                        let next: SourceIdentity? = filter.source == entry.identity ? nil : entry.identity
                        onChange(BoardFilter(source: next, query: filter.query))
                    }
                    .accessibilityIdentifier("board.filter.\(entry.identity.rawValue)")
                }

                ThirdHandCapsuleButton("Search", systemImage: "magnifyingglass", isSelected: isSearching) {
                    isSearching.toggle()
                    if !isSearching {
                        query = ""
                        onChange(BoardFilter(source: filter.source, query: ""))
                    }
                }
                .accessibilityIdentifier("board.filter.search")
            }
            .padding(.horizontal, ThirdHandSpacing.screenMargin)
            .padding(.vertical, ThirdHandSpacing.xxs)
        }
        .scrollIndicators(.hidden)
        .thirdHandGlassContainer(spacing: ThirdHandSpacing.xs)
    }

    private var searchField: some View {
        HStack(spacing: ThirdHandSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ThirdHandColor.textTertiary)
                .accessibilityHidden(true)
            TextField("Search the board", text: $query)
                .font(ThirdHandTypography.itemDetail)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onChange(of: query) { _, value in
                    onChange(BoardFilter(source: filter.source, query: value))
                }
                .accessibilityIdentifier("board.filter.searchField")
        }
        .padding(.horizontal, ThirdHandSpacing.s)
        .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
        .pulseGlass(.regular, in: .capsule)
        .padding(.horizontal, ThirdHandSpacing.screenMargin)
    }

    private var resetRow: some View {
        HStack(spacing: ThirdHandSpacing.s) {
            Text(BoardCopy.shown(totalCount))
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textTertiary)
            Spacer(minLength: 0)
            Button("Reset") {
                query = ""
                isSearching = false
                onReset()
            }
            .font(ThirdHandTypography.meta)
            .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
            .accessibilityIdentifier("board.filter.reset")
        }
        .padding(.horizontal, ThirdHandSpacing.screenMargin)
    }
}
