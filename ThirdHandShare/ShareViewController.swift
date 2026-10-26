import ThirdHandCore
import UIKit
import UniformTypeIdentifiers

/// The Share Extension's whole job: take whatever the user shared, pull out a URL,
/// write one line into the app group, and get out of the way (M7.1).
///
/// **Why an extension at all.** Slack, Gmail and GitHub have no OAuth app for
/// Pulse, so the only honest way to see them is for the user to hand Pulse a link.
/// The share sheet is where that happens, and the extension cannot reach the app's
/// `ItemStore` -- it is a separate, short-lived process. So it appends to
/// `shared-links.jsonl` through `SharedLinkWriter` and the app's next capture pass
/// turns each line into an item. Same write path as the widgets' snooze command:
/// a file the app already owns, never a second copy of state.
final class ShareViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "Adding to Pulse…"
        label.textAlignment = .center
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        spinner.startAnimating()

        Task { await self.handleShare() }
    }

    private func handleShare() async {
        let input = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        guard let payload = await Self.payload(from: input) else {
            // Nothing link-shaped. Say so rather than a silent dismiss: a share that
            // vanishes reads as broken.
            finish(message: "Pulse needs a link to share. Try sharing the message from its own menu.")
            return
        }

        do {
            try SharedLinkWriter().append(
                url: payload.url,
                text: payload.text,
                title: payload.title,
                // The extension's clock, read here and nowhere else; `SharedLinkWriter`
                // and every ThirdHandCore rule take the instant they are given.
                now: Date()
            )
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            finish(message: "Pulse could not save that link.")
        }
    }

    private struct Payload {
        var url: String
        var text: String?
        var title: String?
    }

    /// Pulls a URL, and the surrounding text, out of whatever the host app offered.
    ///
    /// Tried in order, because a Slack share attaches a URL *and* a message body as
    /// separate providers, and a Gmail share often attaches only text containing the
    /// permalink. The first https URL found anywhere wins; the remaining text
    /// becomes the item's detail.
    private static func payload(from items: [NSExtensionItem]) async -> Payload? {
        var strings: [String] = []
        var directURLs: [String] = []
        let title = items.compactMap(\.attributedContentText?.string).first ?? items.first?.attributedTitle?.string

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                    if let url = value as? URL { directURLs.append(url.absoluteString) }
                    if let url = value as? NSURL, let string = url.absoluteString { directURLs.append(string) }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    if let text = value as? String { strings.append(text) }
                    if let data = value as? Data, let text = String(data: data, encoding: .utf8) { strings.append(text) }
                }
            }
        }

        // A direct `URL` provider is the strongest signal; otherwise scan the text.
        //
        // `Classifier.firstHTTPSLink` is reused rather than re-written here so the
        // extension and the capture classifier agree on what "the link" is.
        let joined = strings.joined(separator: "\n")
        guard let url = directURLs.first(where: { ItemIdentity.normalizedSharedURL($0) != nil })
            ?? Classifier.firstHTTPSLink(in: joined)
        else { return nil }

        let remainder = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return Payload(
            url: url,
            text: remainder.isEmpty ? nil : remainder,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func finish(message: String) {
        spinner.stopAnimating()
        label.text = message
        // Long enough to read, short enough not to trap the user in the sheet.
        Task {
            try? await Task.sleep(for: .seconds(2))
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
