import ThirdHandCore
import SwiftUI

/// §8.2: content on an opaque card, glass only on the header capsule and the
/// action bar. The header is the `glassEffectID` morph target (§6.4).
public struct ItemDetailView: View {
    @State private var model: ItemDetailViewModel
    @State private var isSnoozePresented = false
    @State private var isReopenPresented = false
    @State private var reopenReason = ""
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private let namespace: Namespace.ID?

    public init(model: ItemDetailViewModel, namespace: Namespace.ID? = nil) {
        _model = State(initialValue: model)
        self.namespace = namespace
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThirdHandSpacing.l) {
                header
                content
                if let message = model.errorMessage {
                    Text(message)
                        .font(ThirdHandTypography.meta)
                        .foregroundStyle(ThirdHandColor.statusError)
                        .accessibilityIdentifier("detail.error")
                }
                QuickActionRow(
                    quickActions: model.item.quickActions,
                    itemURL: model.item.url,
                    onCopy: { model.copy($0) },
                    onOpen: { open($0) }
                )
                if model.item.status == .waiting {
                    Text(waitingCopy)
                        .font(ThirdHandTypography.meta)
                        .foregroundStyle(ThirdHandColor.statusWaiting)
                }
                HistoryTimeline(entries: model.history, now: model.now)
            }
            .padding(.horizontal, ThirdHandSpacing.screenMargin)
            .padding(.top, ThirdHandSpacing.l)
            .padding(.bottom, 120)
            .frame(maxWidth: ThirdHandSpacing.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ThirdHandColor.surfaceCanvas)
        .safeAreaInset(edge: .bottom) {
            ItemActionBar(
                item: model.item,
                isBusy: model.isBusy,
                onPrimary: primary,
                onDismiss: { Task { await model.dismiss() } },
                onSnooze: { isSnoozePresented = true },
                onCopyLink: copyLink,
                onReopen: { isReopenPresented = true }
            )
        }
        .overlay(alignment: .top) { copiedToast }
        .sheet(isPresented: $isSnoozePresented) {
            SnoozeMenu(now: model.now) { date in
                isSnoozePresented = false
                Task { await model.snooze(until: date) }
            }
            .pulseSheetChrome()
        }
        .sheet(isPresented: $isReopenPresented) {
            ReopenPrompt(reason: $reopenReason) {
                isReopenPresented = false
                let reason = reopenReason
                reopenReason = ""
                Task { await model.reopen(reason: reason) }
            }
            .pulseSheetChrome()
        }
        .accessibilityIdentifier("detail.root")
    }

    // MARK: Header capsule (§6.4)

    private var header: some View {
        HStack(spacing: ThirdHandSpacing.xs) {
            Image(systemName: model.item.kind.systemImage)
                .foregroundStyle(model.item.kind.tint)
                .accessibilityHidden(true)
            Text(metaSummary)
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ThirdHandSpacing.s)
        .padding(.vertical, ThirdHandSpacing.xs)
        .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
        .pulseGlass(.regular, in: .capsule)
        .modifier(GlassIdentity(id: model.item.id, namespace: namespace))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metaSummary)
    }

    /// §8.2: "Waiting on Marco since Oct 20" when the row names exactly one other
    /// person, otherwise the honest general form. "Waiting on someone else" told
    /// the user nothing the row did not already say.
    private var waitingCopy: String {
        let since = model.item.updatedAt.formatted(.dateTime.month(.abbreviated).day())
        let others = model.item.people
        guard others.count == 1, let name = others.first?.split(separator: " ").first else {
            return "Waiting on someone else since \(since)"
        }
        return "Waiting on \(name) since \(since)"
    }

    private var metaSummary: String {
        var parts = [model.item.kind.title, model.item.sourceIdentity.title]
        let people = ThirdHandPeople.shortLine(model.item.people, limit: 1)
        if !people.isEmpty { parts.append("with \(people)") }
        return parts.joined(separator: " · ")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
            Text(model.item.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(ThirdHandColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if !model.item.detail.isEmpty {
                Text(model.item.detail)
                    .font(.body)
                    .foregroundStyle(ThirdHandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            keyValues
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ThirdHandSpacing.m)
        .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))
        .opacity(model.item.status == .done ? 0.6 : 1)
    }

    private var keyValues: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
            keyValue("Due", ThirdHandDateFormat.duePhrase(model.item.due, now: model.now))
            if !model.item.people.isEmpty {
                keyValue("People", model.item.people.joined(separator: ", "))
            }
            keyValue("Source", model.item.sourceIdentity.title)
            keyValue("Priority", model.item.priority.title)
            if let resolution = model.item.resolution, !resolution.isEmpty {
                keyValue("Reason", resolution)
            }
        }
        .padding(.top, ThirdHandSpacing.xxs)
    }

    private func keyValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThirdHandSpacing.s) {
            Text(label)
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textTertiary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(ThirdHandTypography.itemDetail)
                .foregroundStyle(ThirdHandColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var copiedToast: some View {
        if model.copiedConfirmation {
            Label("Copied", systemImage: "checkmark")
                .font(ThirdHandTypography.captureCapsule)
                .padding(.horizontal, ThirdHandSpacing.s)
                .padding(.vertical, ThirdHandSpacing.xs)
                .pulseGlass(.regular, in: .capsule)
                .padding(.top, ThirdHandSpacing.xs)
                .transition(.opacity)
                .accessibilityLabel("Copied")
        }
    }

    // MARK: Actions

    private func primary() {
        if model.canReopen {
            isReopenPresented = true
        } else {
            Task { await model.done() }
        }
    }

    private func open(_ raw: String) {
        model.openURL(raw) { url in openURL(url) }
    }

    private func copyLink() {
        guard let url = model.item.url else { return }
        model.copyText(url)
    }
}

/// §6.4: `glassEffectID` is used in exactly one place — the detail header capsule.
/// Absent on the iOS 18 SDK path and under Reduce Motion.
struct GlassIdentity: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    @Environment(\.pulseMotion) private var motion

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), let namespace, motion.allowsMatchedGeometry {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

/// A reason is mandatory to reopen (#18 acceptance).
public struct ReopenPrompt: View {
    @Binding var reason: String
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(reason: Binding<String>, onConfirm: @escaping () -> Void) {
        _reason = reason
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reopening this?") {
                    TextField("Reason", text: $reason, axis: .vertical)
                        .accessibilityIdentifier("reopen.reason")
                }
            }
            .navigationTitle("Reopen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reopen", action: onConfirm)
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("reopen.confirm")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
