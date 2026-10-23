import Foundation
import PulseCore

// MARK: - Source failures

/// One source that could not be read. §8.1/§9.3: a denial is a paused source and
/// never a full-screen blocker when another source still works.
public struct SourceFailure: Sendable, Hashable, Identifiable {
    public var id: String { identity.rawValue }
    public var identity: SourceIdentity
    public var reason: Reason

    public enum Reason: Sendable, Hashable {
        case denied
        case unavailable
        case failed(String)
    }

    public init(identity: SourceIdentity, reason: Reason) {
        self.identity = identity
        self.reason = reason
    }

    public var isPermissionProblem: Bool {
        switch reason {
        case .denied, .unavailable: true
        case .failed: false
        }
    }

    public var message: String {
        switch reason {
        case .denied: "\(identity.title) access is off"
        case .unavailable: "\(identity.title) isn't available on this device"
        case .failed(let detail): "Couldn't read \(identity.title): \(detail)"
        }
    }
}

// MARK: - Capture seam

/// What one capture pass found. The real engine lives in `PulseCore/Capture`;
/// this is the app-side projection so the board never imports EventKit.
public struct CaptureOutcome: Sendable {
    public var detected: [DetectedItem]
    public var failures: [SourceFailure]
    public var ranAt: Date

    public init(detected: [DetectedItem], failures: [SourceFailure] = [], ranAt: Date) {
        self.detected = detected
        self.failures = failures
        self.ranAt = ranAt
    }

    public static func empty(at instant: Date) -> CaptureOutcome {
        CaptureOutcome(detected: [], failures: [], ranAt: instant)
    }
}

/// The one dependency the board has on capture. Implemented by the app's
/// EventKit wiring and, in previews/tests, by `FakeCaptureEngine`.
public protocol CaptureProviding: Sendable {
    func capture(now: Date) async -> CaptureOutcome
}

// MARK: - Permission seam (#20)

/// The four states the UI distinguishes. `restricted` is distinct from `denied`
/// because "you can't change this" is a different sentence from "you turned it off".
public enum PermissionStatus: String, Sendable, CaseIterable, Hashable {
    case notDetermined, granted, denied, restricted

    public var isUsable: Bool { self == .granted }
}

/// Per-source permission state, surfaced to the preamble and the banner.
public struct PermissionState: Sendable, Hashable {
    public var calendar: PermissionStatus
    public var reminders: PermissionStatus

    public init(calendar: PermissionStatus = .notDetermined, reminders: PermissionStatus = .notDetermined) {
        self.calendar = calendar
        self.reminders = reminders
    }

    public var allGranted: Bool { calendar.isUsable && reminders.isUsable }
    public var anyDenied: Bool { calendar == .denied || reminders == .denied }

    /// §9.2: "If only Reminders is available the primary becomes Connect Reminders."
    public var preferredSource: SourceIdentity {
        calendar == .notDetermined ? .calendar : .reminders
    }

    public func status(for identity: SourceIdentity) -> PermissionStatus {
        switch identity {
        case .calendar: calendar
        case .reminders: reminders
        default: .granted
        }
    }
}

/// Owns the EventKit permission conversation (#20). The app injects a concrete
/// implementation that talks to `EKEventStore`; this type only owns the screen
/// logic (has the preamble been shown, what is the current state).
@MainActor
@Observable
public final class PermissionCoordinator {
    public private(set) var state: PermissionState
    public private(set) var hasAsked: Bool

    /// Wired by the app to the real request. Returning the new status keeps the
    /// coordinator free of EventKit.
    public var request: (@MainActor (SourceIdentity) async -> PermissionStatus)?
    /// Wired by the app to the current status, with no prompt.
    public var refresh: (@MainActor () async -> PermissionState)?

    private let defaults: UserDefaults
    private static let askedKey = "pulse.permissionPreambleAsked"

    public init(state: PermissionState = PermissionState(), defaults: UserDefaults = .standard) {
        self.state = state
        self.defaults = defaults
        self.hasAsked = defaults.bool(forKey: Self.askedKey)
    }

    /// §9.2 / §8.3: the preamble shows until the user has answered once.
    public var shouldShowPreamble: Bool {
        !hasAsked && (state.calendar == .notDetermined || state.reminders == .notDetermined)
    }

    public func load() async {
        if let refresh { state = await refresh() }
    }

    @discardableResult
    public func allow(_ identity: SourceIdentity) async -> PermissionStatus {
        let status = await request?(identity) ?? .denied
        switch identity {
        case .calendar: state.calendar = status
        case .reminders: state.reminders = status
        default: break
        }
        markAsked()
        return status
    }

    public func markAsked() {
        hasAsked = true
        defaults.set(true, forKey: Self.askedKey)
    }

    /// §8.3 "Not now": leaves the board read-only and does not ask again until
    /// the user taps a source banner.
    public func declineForNow() {
        markAsked()
    }
}

// MARK: - Capture status

/// What the capture capsule renders (§8.1, #17).
public struct CaptureStatusModel: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case idle(Date?)
        case capturing
        case failed(Date?)
    }

    public var phase: Phase
    public var itemCount: Int
    /// The sync line under the capture line, e.g. "Mac · 2m ago", "Syncing…", or
    /// the failure that stopped publishing. `nil` when this build has no container,
    /// so the capsule renders exactly as it did before sync existed.
    public var syncText: String?

    public init(phase: Phase, itemCount: Int, syncText: String? = nil) {
        self.phase = phase
        self.itemCount = itemCount
        self.syncText = syncText
    }

    public var lastCapturedAt: Date? {
        switch phase {
        case .idle(let date), .failed(let date): date
        case .capturing: nil
        }
    }

    /// §3: "12 items · 2m ago".
    public func text(now: Date) -> String {
        switch phase {
        case .capturing:
            return "Capturing…"
        case .failed:
            return "Couldn't refresh · Try again"
        case .idle(let date):
            guard let date else { return "Not captured yet" }
            return "\(itemCount) item\(itemCount == 1 ? "" : "s") · \(PulseDateFormat.relative(date, now: now))"
        }
    }

    public var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    public var isCapturing: Bool {
        if case .capturing = phase { return true }
        return false
    }
}
