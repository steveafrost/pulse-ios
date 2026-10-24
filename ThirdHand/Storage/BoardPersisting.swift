import Foundation
import ThirdHandCore

/// Persists what the app needs across launches: the widget board cache (in the
/// app group) and the last-viewed marker (§5.2 newness, #21).
///
/// Everything here is best-effort. A failed write must never take the board down
/// with it, so the protocol returns `throws` and the caller logs-and-continues.
public protocol BoardPersisting: Sendable {
    func save(board: [Horizon: [ThirdHandItem]], generatedAt: Date) throws
    func loadBoard() -> WidgetBoard?
}

public struct AppGroupBoardPersistence: BoardPersisting {
    public let store: WidgetBoardStore

    public init(store: WidgetBoardStore = WidgetBoardStore()) {
        self.store = store
    }

    public func save(board: [Horizon: [ThirdHandItem]], generatedAt: Date) throws {
        try store.write(WidgetBoard(board: board, generatedAt: generatedAt))
    }

    public func loadBoard() -> WidgetBoard? {
        store.read()
    }
}

/// In-memory persistence for previews and tests.
public final class InMemoryBoardPersistence: BoardPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var board: WidgetBoard?

    public init(board: WidgetBoard? = nil) {
        self.board = board
    }

    public func save(board: [Horizon: [ThirdHandItem]], generatedAt: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        self.board = WidgetBoard(board: board, generatedAt: generatedAt)
    }

    public func loadBoard() -> WidgetBoard? {
        lock.lock()
        defer { lock.unlock() }
        return board
    }
}
