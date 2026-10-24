import Foundation

/// A deterministic `CaptureSource` for tests and SwiftUI previews.
///
/// Lives in `ThirdHandCore` itself rather than a separate `ThirdHandCoreTestSupport`
/// target on purpose: the app target needs it for previews, the test target needs
/// it for fixtures, and a third SPM product would have to be threaded through
/// `project.yml` and every embedding target for no benefit. It is a dozen lines
/// of code with no dependencies and no production call site.
///
/// `@unchecked Sendable` because `detectCallCount` is the one piece of mutable
/// state, and it is guarded.
public final class FakeSource: CaptureSource, @unchecked Sendable {
    public let sourceID: Source

    private let items: [DetectedItem]
    private let delay: Duration?
    private let error: CaptureError?
    private let lock = NSLock()
    private var calls = 0
    /// Every `now` the source was asked about, in call order. Lets a test assert
    /// that the engine passes one instant to every source.
    private var seenInstants: [Date] = []

    /// - Parameters:
    ///   - sourceID: reported source; also the default for items that omit one.
    ///   - items: the canned answer, returned verbatim on every call.
    ///   - delay: an artificial pause, so a test can force two overlapping runs.
    ///   - error: when set, `detect` throws this instead of returning items.
    public init(
        sourceID: Source = .other,
        items: [DetectedItem] = [],
        delay: Duration? = nil,
        error: CaptureError? = nil
    ) {
        self.sourceID = sourceID
        self.items = items
        self.delay = delay
        self.error = error
    }

    /// How many times `detect` was entered.
    public var detectCallCount: Int { withLock { calls } }

    /// The instants `detect` was called with.
    public var detectInstants: [Date] { withLock { seenInstants } }

    /// `NSLock.lock()` is unavailable from an async context, so every use goes
    /// through this synchronous scope.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func detect(now: Date, window: DateInterval) async throws -> [DetectedItem] {
        withLock {
            calls += 1
            seenInstants.append(now)
        }

        if let delay {
            try? await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
        return items
    }
}

/// A `SharedLinkSnapshot` provider backed by a literal array.
///
/// Keeps `SharedLinkSource` testable without the app group, a share sheet or a
/// second process: the host and kind rules are pure functions over these.
public struct FakeSharedLinkProvider: SharedLinkProviding {
    public let links: [SharedLinkSnapshot]
    public let error: CaptureError?

    public init(links: [SharedLinkSnapshot], error: CaptureError? = nil) {
        self.links = links
        self.error = error
    }

    public func sharedLinks() throws -> [SharedLinkSnapshot] {
        if let error { throw error }
        return links
    }
}

/// A `CalendarEventSnapshot` provider backed by a literal array.
///
/// This is what keeps the detector rules testable: no EventKit, no permission
/// prompt, no simulator calendar. A SwiftUI preview uses it the same way.
public struct FakeEventProvider: EventProviding {
    public let events: [CalendarEventSnapshot]
    public let error: CaptureError?

    public init(events: [CalendarEventSnapshot], error: CaptureError? = nil) {
        self.events = events
        self.error = error
    }

    public func events(in window: DateInterval) async throws -> [CalendarEventSnapshot] {
        if let error { throw error }
        return events
    }
}

/// A `ReminderSnapshot` provider backed by a literal array.
public struct FakeReminderProvider: ReminderProviding {
    public let reminders: [ReminderSnapshot]
    public let error: CaptureError?

    public init(reminders: [ReminderSnapshot], error: CaptureError? = nil) {
        self.reminders = reminders
        self.error = error
    }

    public func incompleteReminders() async throws -> [ReminderSnapshot] {
        if let error { throw error }
        return reminders
    }
}
