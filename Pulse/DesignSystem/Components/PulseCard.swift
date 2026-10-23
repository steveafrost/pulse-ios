import SwiftUI

/// §6.2: an item row is an opaque card. Never glass, never material.
public struct PulseCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColor.surfaceCard, in: RoundedRectangle(cornerRadius: PulseRadius.card, style: .continuous))
    }
}
