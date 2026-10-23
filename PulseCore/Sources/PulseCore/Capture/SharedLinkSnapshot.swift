import Foundation

/// One link the user shared into Pulse, as plain values.
///
/// This is the boundary between the Share Extension (which writes a JSON line into
/// the app group) and the detector rules. `SharedLinkSource` maps these into
/// `DetectedItem`s; every heuristic is a pure function over arrays of these, so the
/// rules are testable on macOS without a share sheet, an extension host or a device.
///
/// **Why this exists at all.** Slack, Gmail and GitHub have no OAuth app registered
/// for Pulse and this build must not pretend otherwise (issue #39). The honest
/// on-device path is the one the user drives: they share a thread, a message or a
/// pull request, and Pulse remembers it. See `docs/DEFERRED-SOURCES.md` for what a
/// real API integration would need.
public struct SharedLinkSnapshot: Sendable, Hashable {
    /// The absolute URL, as shared. `https:` only once normalised -- see
    /// `ItemIdentity.normalizedSharedURL`.
    public var url: String
    /// The accompanying text from the share sheet: Slack's "Share a message"
    /// payload, or the message body. The Slack kinds are read from this.
    public var text: String?
    /// A title, when the host app supplied one (a Gmail subject, a PR title).
    public var title: String?
    /// When the user shared it. Injected from the caller's clock, never read from
    /// `Date()` inside logic.
    public var sharedAt: Date

    public init(url: String, text: String? = nil, title: String? = nil, sharedAt: Date) {
        self.url = url
        self.text = text
        self.title = title
        self.sharedAt = sharedAt
    }
}

// MARK: - Wire coding

extension SharedLinkSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case url, text, title, sharedAt
    }

    /// Lenient on the way in, on purpose: the file is written by an extension this
    /// app ships but also, in principle, by a build of it the reader has never seen
    /// (a beta sharing into a release app). A missing `text`, a `null` title or an
    /// unexpected extra key must not cost the user a shared link. Only a missing or
    /// empty `url` disqualifies a line, because without a URL there is no item.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SharedLinkError.missingURL }
        url = trimmed
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? nil
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        // A line with no parsable instant is dated by the reader, so the item still
        // appears rather than vanishing.
        sharedAt = (try? container.decodeIfPresent(Date.self, forKey: .sharedAt)) ?? .distantPast
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(sharedAt, forKey: .sharedAt)
    }

    /// Rewrites `sharedAt` when the wire carried none. The reader supplies the
    /// instant so this type never reads the clock itself.
    func dating(at instant: Date) -> SharedLinkSnapshot {
        guard sharedAt == .distantPast else { return self }
        var copy = self
        copy.sharedAt = instant
        return copy
    }
}

/// The ways a shared link can fail to be a link.
public enum SharedLinkError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The record had no `url` (or an empty one), so it cannot become an item.
    case missingURL
    /// The URL did not parse, or was not `http(s)`.
    case unsupportedURL(String)

    public var description: String {
        switch self {
        case .missingURL: "shared link had no url"
        case .unsupportedURL(let raw): "unsupported shared url: \(raw)"
        }
    }
}

// MARK: - Reading

/// Anything that can hand back the links the user has shared.
///
/// The real conformance is `FileSharedLinkProvider` (the app group); tests use
/// `FakeSharedLinkProvider`.
public protocol SharedLinkProviding: Sendable {
    func sharedLinks() throws -> [SharedLinkSnapshot]
}

/// Reads `shared-links.jsonl` from the app group.
///
/// Append-only JSONL, the same shape as `commands.jsonl`: the extension appends one
/// line per share and never rewrites the file, so a half-written line can only ever
/// be the last one, and that line is skipped rather than failing the read.
///
/// A missing file is the fresh-install state, not an error: no shares means no
/// items, which is the honest answer.
/// `@unchecked Sendable` for the same reason `WidgetBoardReader` is: `FileManager`
/// is not declared `Sendable`, but the `exists`/`contents` calls used here are
/// documented thread-safe and this type holds no mutable state.
public struct FileSharedLinkProvider: SharedLinkProviding, @unchecked Sendable {
    public let paths: PulsePaths
    private let fileManager: FileManager

    public init(paths: PulsePaths = PulsePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func sharedLinks() throws -> [SharedLinkSnapshot] {
        let url = paths.sharedLinksURL
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // The container is there but unreadable. That is a permission-shaped
            // failure, not "you shared nothing", so it must not read as an empty
            // source -- say so and let the engine report it.
            throw CaptureError.underlying("shared links are unreadable: \(error.localizedDescription)")
        }
        return FileSharedLinkProvider.decode(data, at: Date(timeIntervalSince1970: 0))
    }

    /// Splits on newlines and decodes each line on its own. A bad line is dropped;
    /// the rest of the file still counts.
    ///
    /// `undated` is the instant a record that carried no `sharedAt` is dated with.
    /// The caller passes its own clock so this stays reproducible.
    public static func decode(_ data: Data, at undated: Date) -> [SharedLinkSnapshot] {
        let decoder = PulseJSON.makeDecoder()
        return data
            .split(separator: UInt8(ascii: "\n"))
            .compactMap { line in
                let trimmed = line.drop { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
                guard !trimmed.isEmpty else { return nil }
                guard let decoded = try? decoder.decode(SharedLinkSnapshot.self, from: Data(trimmed)) else {
                    return nil
                }
                return decoded.dating(at: undated)
            }
    }
}

// MARK: - Writing

/// Appends a shared link to the app group, for the Share Extension.
///
/// The extension cannot touch `ItemStore` -- it is a different process and the
/// store is the app's -- so it writes a line and the app's next capture pass picks
/// it up. Same discipline as `SnoozeCommandWriter`: one atomic append per record,
/// never a read-modify-write that could drop a concurrent line.
public struct SharedLinkWriter: @unchecked Sendable {
    public let paths: PulsePaths
    private let fileManager: FileManager

    public init(paths: PulsePaths = PulsePaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    /// Records one shared link. Throws when the URL is unusable, so the extension
    /// can tell the user rather than silently swallowing the share.
    public func append(url raw: String, text: String?, title: String?, now instant: Date) throws {
        guard let normalised = ItemIdentity.normalizedSharedURL(raw) else {
            throw SharedLinkError.unsupportedURL(raw)
        }
        try append(SharedLinkSnapshot(url: normalised, text: text, title: title, sharedAt: instant))
    }

    public func append(_ link: SharedLinkSnapshot) throws {
        let object: [String: Any] = [
            "url": link.url,
            "text": link.text ?? NSNull(),
            "title": link.title ?? NSNull(),
            "sharedAt": PulseJSON.dates.string(from: link.sharedAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try appendLine(data + Data("\n".utf8))
    }

    private func appendLine(_ line: Data) throws {
        paths.ensureDirectory(fileManager: fileManager)
        let url = paths.sharedLinksURL
        if !fileManager.fileExists(atPath: url.path) {
            try line.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
