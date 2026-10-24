import SwiftUI
import ThirdHandCore

/// §8.3 — the Settings screen the design doc has described since v1 and the app has
/// never had.
///
/// It exists for one reason: the board is a *view* of what the app can reach, and
/// when a source is paused the board can only say "Calendar is off" — it cannot say
/// what to do about it. This screen is where "what Third Hand can see" is stated
/// plainly, with the one fix per source beside it.
///
/// Deliberately short. Settings screens fail by accumulating; every row here answers
/// a question the board can raise. There is no appearance switch (the app follows the
/// system, always), no notification toggles (the board is the notification), and no
/// account system (there are no accounts).
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let sources: [SourceRow]
    private let emailStatus: EmailAccountModel.Status
    private let lastChecked: Date?
    private let onOpenEmail: () -> Void

    /// One source and what the app currently knows about it.
    public struct SourceRow: Identifiable, Equatable {
        public let id: String
        public let source: Source
        /// The row's own label and glyph.
        ///
        /// Needed because the wire enum does not line up with the user's words:
        /// reminders and shared links both travel as `.other` (the contract reserves
        /// no case for either), so reading `source.title` would label the Reminders
        /// row "Other" and `source.systemImage` would give it a link glyph. The
        /// settings screen names what the user installed, not what the snapshot
        /// format calls it.
        public let title: String
        /// The row's SF Symbol, supplied per row for the same reason as `title`.
        public let systemImage: String
        /// A short state: "Connected", "Not connected", "Off in iOS Settings".
        public let state: String
        /// True when the state needs the user to do something.
        public let needsAttention: Bool

        public init(
            id: String,
            source: Source,
            title: String,
            systemImage: String,
            state: String,
            needsAttention: Bool
        ) {
            self.id = id
            self.source = source
            self.title = title
            self.systemImage = systemImage
            self.state = state
            self.needsAttention = needsAttention
        }
    }

    public init(
        sources: [SourceRow],
        emailStatus: EmailAccountModel.Status,
        lastChecked: Date?,
        onOpenEmail: @escaping () -> Void
    ) {
        self.sources = sources
        self.emailStatus = emailStatus
        self.lastChecked = lastChecked
        self.onOpenEmail = onOpenEmail
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThirdHandSpacing.xxl) {
                    sourcesSection
                    emailSection
                    privacySection
                    aboutSection
                }
                .padding(.horizontal, ThirdHandSpacing.screenMargin)
                .padding(.vertical, ThirdHandSpacing.l)
                .frame(maxWidth: ThirdHandSpacing.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(ThirdHandColor.surfaceCanvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    // MARK: Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
            eyebrow("What Third Hand can see")
            VStack(spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, row in
                    sourceRow(row)
                    if index < sources.count - 1 {
                        Divider().overlay(ThirdHandColor.separator)
                    }
                }
            }
            .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))

            // A degraded source has to say what to *do*, not just that it is off.
            // The board can only report the pause; the fix lives in iOS Settings,
            // so this is the one place the instruction can be given.
            if sources.contains(where: \.needsAttention) {
                Text("A paused source is fixed in iOS Settings → Privacy & Security. Third Hand never re-asks on its own.")
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastChecked {
                Text("Checked \(ThirdHandDateFormat.relative(lastChecked, now: Date()))")
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.textTertiary)
            }
        }
    }

    private func sourceRow(_ row: SourceRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThirdHandSpacing.s) {
            Image(systemName: row.systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(row.needsAttention ? ThirdHandColor.statusError : row.source.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(ThirdHandTypography.keyValueLabel)
                    .foregroundStyle(ThirdHandColor.textPrimary)
                Text(row.state)
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(row.needsAttention ? ThirdHandColor.statusError : ThirdHandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ThirdHandSpacing.m)
        .padding(.vertical, ThirdHandSpacing.s)
        .frame(minHeight: ThirdHandSpacing.minimumHitTarget, alignment: .leading)
    }

    // MARK: Email

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
            eyebrow("Email")
            Button(action: onOpenEmail) {
                HStack(alignment: .firstTextBaseline, spacing: ThirdHandSpacing.s) {
                    Image(systemName: "envelope")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(ThirdHandColor.sourceGmail)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mailbox")
                            .font(ThirdHandTypography.keyValueLabel)
                            .foregroundStyle(ThirdHandColor.textPrimary)
                        Text(emailLine)
                            .font(ThirdHandTypography.meta)
                            .foregroundStyle(ThirdHandColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ThirdHandColor.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, ThirdHandSpacing.m)
                .padding(.vertical, ThirdHandSpacing.s)
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))
            .accessibilityIdentifier("settings.email")
            .accessibilityLabel("Mailbox, \(emailLine)")
            .accessibilityHint("Opens the mailbox connection screen")
        }
    }

    private var emailLine: String {
        switch emailStatus {
        case .notConnected: "Not connected"
        case .checking: "Checking…"
        case .unread(let count): Plural.count(count, "unread message")
        case .failed: "Couldn't check"
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
            eyebrow("Privacy")
            VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
                Text("Your data stays yours.")
                    .font(ThirdHandTypography.keyValueLabel)
                    .foregroundStyle(ThirdHandColor.textPrimary)
                // Two outbound paths exist and both are the user's own: the iCloud
                // mirror, and signing in to their own mail server. The previous copy
                // said the iCloud mirror was "the only thing that leaves the device",
                // which stopped being true when the mailbox was added -- a privacy
                // claim that is subtly false is worse than a vague one, and this
                // sentence is the one a user checks before typing a password.
                Text(
                    "Third Hand reads your calendar, reminders and mailbox on the phone. "
                        + "It has no server of its own, no account and no analytics. "
                        + "Two things can leave the device, both to places you already own: "
                        + "the board your Mac syncs over your own iCloud Drive, and your "
                        + "password, sent only to your own mail server to sign in. "
                        + "Only if you turn each one on."
                )
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ThirdHandSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
            eyebrow("About")
            Text(versionLine)
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textTertiary)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Third Hand \(version) (\(build))"
    }

    // MARK: Eyebrow

    /// The small-caps-ish group label. Tracking does the work a bundled small-caps
    /// face would have, and uppercasing is limited to labels this short so no
    /// sentence is ever shouted.
    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(ThirdHandTypography.eyebrow)
            .tracking(ThirdHandTracking.eyebrow)
            .foregroundStyle(ThirdHandColor.textTertiary)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}