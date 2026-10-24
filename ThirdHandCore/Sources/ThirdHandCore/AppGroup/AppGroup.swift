import Foundation

/// Resolves the app-group container the app and the widget extension share (#21).
///
/// The extension cannot read the app's `Documents`, so the widget-facing cache
/// lives in `group.com.steveafrost.thirdhand`. On a simulator without the entitlement
/// applied — and in previews — `containerURL(forSecurityApplicationGroupIdentifier:)`
/// returns `nil`, so we fall back to a temp directory rather than crashing: a widget
/// cache is not worth a crash on launch.
public enum AppGroup {
    public static let identifier = "group.com.steveafrost.thirdhand"

    /// The container root, or a temp fallback when the group is unavailable.
    public static func containerURL(
        fileManager: FileManager = .default,
        identifier: String = AppGroup.identifier
    ) -> URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = fileManager.temporaryDirectory.appendingPathComponent("pulse-app-group", isDirectory: true)
        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Whether the real container resolved (as opposed to the temp fallback).
    public static func isGroupAvailable(fileManager: FileManager = .default) -> Bool {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}

/// Named paths inside the container. One place, so the widget and the app cannot
/// drift apart.
///
/// Two files, two purposes, deliberately not merged:
///   * `board.json`    — on-device widget cache (written on every board load/mutation).
///   * `snapshot.json` — the iCloud transport for the Mac mirror (M4.2).
public struct ThirdHandPaths: Sendable {
    public let root: URL

    public init(root: URL = AppGroup.containerURL()) {
        self.root = root
    }

    /// `Documents/ThirdHand/` inside the group.
    public var appGroupRoot: URL {
        root.appendingPathComponent("Documents/ThirdHand", isDirectory: true)
    }

    /// The Mac-mirror transport envelope (M4).
    public var snapshotURL: URL { appGroupRoot.appendingPathComponent("snapshot.json") }
    /// Mirror -> iOS commands (M4).
    public var commandsURL: URL { appGroupRoot.appendingPathComponent("commands.jsonl") }
    /// iOS -> mirror acks (M4).
    public var commandsAckURL: URL { appGroupRoot.appendingPathComponent("commands.ack.jsonl") }
    /// The widget's read-only board cache.
    public var boardURL: URL { appGroupRoot.appendingPathComponent("board.json") }
    /// How far into `commands.jsonl` this device has read.
    ///
    /// Device-local bookkeeping, so it sits in the group container root rather than
    /// in `Documents/ThirdHand/`: the data contract pins that directory to exactly the
    /// three transport files the Mac plugin enumerates.
    public var commandCursorURL: URL { root.appendingPathComponent("commands.cursor") }
    /// The Share Extension's inbox: one JSON object per line, one line per share
    /// (M7.1). Append-only, and read by `FileSharedLinkProvider`.
    ///
    /// In the group root rather than `Documents/ThirdHand/` for the same reason as the
    /// cursor: that directory is the Mac transport, and this file is the app group's
    /// own hand-off between two processes of this app.
    public var sharedLinksURL: URL { root.appendingPathComponent("shared-links.jsonl") }

    /// The bounded on-device sync log, for the debug sheet.
    ///
    /// In the group root for the same reason as the cursor: `Documents/ThirdHand/` is
    /// the shared transport, and this file is ours alone.
    public var syncLogURL: URL { root.appendingPathComponent("sync.log") }

    /// Creates the directory if it is missing. Safe to call repeatedly.
    @discardableResult
    public func ensureDirectory(fileManager: FileManager = .default) -> URL {
        try? fileManager.createDirectory(at: appGroupRoot, withIntermediateDirectories: true)
        return appGroupRoot
    }
}
