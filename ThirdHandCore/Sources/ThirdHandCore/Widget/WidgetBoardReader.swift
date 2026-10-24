import Foundation

/// The one read path every widget, intent and preview uses to get the board.
///
/// It is deliberately *not* a `WidgetBoardStore` read: the store is the app's
/// writer and lives where it can throw, while this has to be total. A missing
/// `board.json` is the fresh-install state, a corrupt one is treated the same way
/// (an empty board is honest; crashing on the Lock Screen is not), and neither
/// case may fabricate data.
///
/// `ThirdHandCore` owns this so the widget extension, the app-intent code and the tests
/// all read the app group through one implementation, and because the extension
/// cannot import the app target.
///
/// `@unchecked Sendable` for the same reason `WidgetBoardStore` is: `FileManager` is
/// not declared `Sendable` but its `exists`/`contents` calls are documented
/// thread-safe, and this type holds no mutable state.
public struct WidgetBoardReader: @unchecked Sendable {
    public let paths: ThirdHandPaths
    private let fileManager: FileManager

    public init(paths: ThirdHandPaths = ThirdHandPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    /// The projection at one instant. Never throws: empty on every failure.
    ///
    /// `hasBoard` comes from the file's existence, not from a successful decode: a
    /// present-but-corrupt projection is a bug in us, not a fresh install, and the
    /// widget should say "Nothing needs you" rather than "set up Third Hand".
    public func snapshot() -> WidgetSnapshot {
        var snapshot = WidgetSnapshot(board: readBoard())
        snapshot.hasBoard = hasBoard
        return snapshot
    }

    /// The decoded board, or nil when it is absent or unreadable.
    ///
    /// Reads through the same decoder the writer's counterpart uses (`ThirdHandJSON`),
    /// so the wire format cannot drift between the two halves.
    public func readBoard() -> WidgetBoard? {
        guard fileManager.fileExists(atPath: paths.boardURL.path),
              let data = try? Data(contentsOf: paths.boardURL)
        else { return nil }
        return try? ThirdHandJSON.makeDecoder().decode(WidgetBoard.self, from: data)
    }

    /// Whether the app has ever written a projection. Used to tell "fresh install"
    /// from "nothing needs you", which is a different sentence on screen.
    public var hasBoard: Bool {
        fileManager.fileExists(atPath: paths.boardURL.path)
    }
}
