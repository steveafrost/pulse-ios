import Foundation
import Observation
import ThirdHandCore

/// The detail sheet's state owner (#18). Optimistic: every action updates the
/// local item and history immediately, and rolls back with an inline message if
/// the store throws — so a slow store never freezes the button.
@MainActor
@Observable
public final class ItemDetailViewModel {
    public private(set) var item: ThirdHandItem
    public private(set) var isBusy = false
    public var errorMessage: String?
    public private(set) var copiedConfirmation = false

    private let store: any ItemStoring
    private let clock: @Sendable () -> Date

    public init(item: ThirdHandItem, store: any ItemStoring, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.item = item
        self.store = store
        self.clock = clock
    }

    public var now: Date {
        clock()
    }

    public var canReopen: Bool {
        item.status == .done || item.status == .dismissed || item.status == .resolved
    }

    public var history: [HistoryEntry] {
        Array(item.history.reversed())
    }

    /// §18: the detail's primary button follows the status.
    public var primaryTitle: String {
        if canReopen {
            return "Reopen"
        }
        return "Done"
    }

    public func done(reason: String? = nil) async {
        await perform(.done, until: nil, reason: reason)
    }

    public func dismiss(reason: String? = nil) async {
        await perform(.dismiss, until: nil, reason: reason)
    }

    public func snooze(until: Date) async {
        await perform(.snooze, until: until, reason: nil)
    }

    public func unsnooze() async {
        await perform(.reopen, until: nil, reason: "Unsnoozed")
    }

    public func reopen(reason: String) async {
        await perform(.reopen, until: nil, reason: reason)
    }

    /// §18: copy writes `UIPasteboard.general` and flashes a confirmation.
    public func copy(_ quickAction: QuickAction) {
        guard let text = quickAction.text else { return }
        copyText(text)
    }

    public func copyText(_ text: String) {
        Pasteboard.write(text)
        copiedConfirmation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copiedConfirmation = false
        }
    }

    /// §18: opening a URL is scheme-guarded to https.
    public func openURL(_ raw: String, opener: @escaping @MainActor (URL) -> Void) {
        guard let url = URL(string: raw), url.scheme == "https" else {
            errorMessage = "That link can't be opened."
            return
        }
        opener(url)
    }

    private func perform(_ verb: ItemActionVerb, until: Date?, reason: String?) async {
        let snapshot = item
        // Optimistic local mutation, so the UI reflects the intent instantly.
        var optimistic = item
        switch verb {
        case .done: optimistic.status = .done
        case .dismiss: optimistic.status = .dismissed
        case .snooze:
            optimistic.status = .snoozed
            optimistic.snoozedUntil = until
        case .reopen:
            optimistic.status = .open
            optimistic.snoozedUntil = nil
        }
        optimistic.updatedAt = now
        item = optimistic

        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await store.userAction(
                id: snapshot.id,
                verb: verb,
                until: until,
                reason: reason,
                by: "user",
                now: now
            )
            item = updated
            errorMessage = nil
        } catch {
            item = snapshot
            errorMessage = "Couldn't save that. Try again."
        }
    }
}

// MARK: - Pasteboard

/// The only type that touches the pasteboard (#18 acceptance: `grep UIPasteboard`
/// matches one file). The protocol keeps previews off the real clipboard.
public enum Pasteboard {
    public nonisolated(unsafe) static var writer: @MainActor (String) -> Void = { UIPasteboardShim.write($0) }

    public static func write(_ text: String) {
        MainActor.assumeIsolated { writer(text) }
    }
}
