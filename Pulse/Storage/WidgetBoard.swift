import Foundation
import PulseCore

/// The widget-facing projection of one item. Only the fields a widget needs, so
/// a future field addition in `PulseItem` cannot silently bloat the cache or
/// break the widget's decode.
public struct WidgetItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var kind: String
    public var priority: String
    public var due: Date?
    public var horizon: String

    public init(item: PulseItem, horizon: Horizon) {
        id = item.id
        title = item.title
        kind = item.kind.rawValue
        priority = item.priority.rawValue
        due = item.due
        self.horizon = horizon.rawValue
    }
}

/// `board.json` — the read-only cache the widget timeline reads.
public struct WidgetBoard: Codable, Sendable, Hashable {
    public var generatedAt: Date
    public var nowCount: Int
    public var items: [WidgetItem]

    public init(generatedAt: Date, nowCount: Int, items: [WidgetItem]) {
        self.generatedAt = generatedAt
        self.nowCount = nowCount
        self.items = items
    }

    /// Projects a board. `nowCount` excludes `.fyi` items, mirroring the board's
    /// rule that Nice to Know never contributes to the Now badge (§1, M1.5).
    public init(board: [Horizon: [PulseItem]], generatedAt: Date, calendar: Calendar = .current) {
        self.generatedAt = generatedAt
        var projected: [WidgetItem] = []
        for horizon in Horizon.allCases.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            for item in board[horizon] ?? [] {
                projected.append(WidgetItem(item: item, horizon: horizon))
            }
        }
        items = projected
        nowCount = (board[.now] ?? []).filter { $0.kind != .fyi }.count
    }
}

/// Reads and writes `board.json` in the app group atomically (tmp + rename).
/// `FileManager` is documented thread-safe, and every write here is a
/// self-contained tmp+rename, so the store is safe to share across actors.
public struct WidgetBoardStore: @unchecked Sendable {
    public let paths: PulsePaths
    private let fileManager: FileManager

    public init(paths: PulsePaths = PulsePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func write(_ board: WidgetBoard) throws {
        paths.ensureDirectory(fileManager: fileManager)
        let data = try PulseJSON.makeEncoder(prettyPrinted: true).encode(board)
        let target = paths.boardURL
        let tmp = target.deletingLastPathComponent().appendingPathComponent("board.json.tmp")
        try data.write(to: tmp, options: .atomic)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.moveItem(at: tmp, to: target)
    }

    public func read() -> WidgetBoard? {
        guard let data = try? Data(contentsOf: paths.boardURL) else { return nil }
        return try? PulseJSON.makeDecoder().decode(WidgetBoard.self, from: data)
    }
}
