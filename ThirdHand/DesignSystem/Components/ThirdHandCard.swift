import SwiftUI

/// §6.2: an item row is an opaque card. Never glass, never material.
public struct ThirdHandCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))
    }
}
