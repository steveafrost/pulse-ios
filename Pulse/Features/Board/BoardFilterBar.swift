import PulseCore
import SwiftUI

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
        VStack(spacing: PulseSpacing.xs) {
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
            HStack(spacing: PulseSpacing.xs) {
                PulseCapsuleButton(
                    "All",
                    isSelected: filter.source == nil,
                    badge: nowCount > 0 ? "\(nowCount)" : nil
                ) {
                    onChange(BoardFilter(source: nil, query: filter.query))
                }
                .accessibilityIdentifier("board.filter.all")

                ForEach(sources, id: \.identity) { entry in
                    PulseCapsuleButton(
                        entry.identity.title,
                        systemImage: entry.identity.systemImage,
                        isSelected: filter.source == entry.identity
                    ) {
                        let next: SourceIdentity? = filter.source == entry.identity ? nil : entry.identity
                        onChange(BoardFilter(source: next, query: filter.query))
                    }
                    .accessibilityIdentifier("board.filter.\(entry.identity.rawValue)")
                }

                PulseCapsuleButton("Search", systemImage: "magnifyingglass", isSelected: isSearching) {
                    isSearching.toggle()
                    if !isSearching {
                        query = ""
                        onChange(BoardFilter(source: filter.source, query: ""))
                    }
                }
                .accessibilityIdentifier("board.filter.search")
            }
            .padding(.horizontal, PulseSpacing.screenMargin)
            .padding(.vertical, PulseSpacing.xxs)
        }
        .scrollIndicators(.hidden)
        .pulseGlassContainer(spacing: PulseSpacing.xs)
    }

    private var searchField: some View {
        HStack(spacing: PulseSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PulseColor.textTertiary)
                .accessibilityHidden(true)
            TextField("Search the board", text: $query)
                .font(PulseTypography.itemDetail)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onChange(of: query) { _, value in
                    onChange(BoardFilter(source: filter.source, query: value))
                }
                .accessibilityIdentifier("board.filter.searchField")
        }
        .padding(.horizontal, PulseSpacing.s)
        .frame(minHeight: PulseSpacing.minimumHitTarget)
        .pulseGlass(.regular, in: .capsule)
        .padding(.horizontal, PulseSpacing.screenMargin)
    }

    private var resetRow: some View {
        HStack(spacing: PulseSpacing.s) {
            Text(BoardCopy.shown(totalCount))
                .font(PulseTypography.meta)
                .foregroundStyle(PulseColor.textTertiary)
            Spacer(minLength: 0)
            Button("Reset") {
                query = ""
                isSearching = false
                onReset()
            }
            .font(PulseTypography.meta)
            .frame(minHeight: PulseSpacing.minimumHitTarget)
            .accessibilityIdentifier("board.filter.reset")
        }
        .padding(.horizontal, PulseSpacing.screenMargin)
    }
}
