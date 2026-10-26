import SwiftUI
import ThirdHandCore

/// §8.3 — the mailbox connection screen.
///
/// Three things it must get right, in order of importance:
///
/// 1. **The password is a `SecureField` and is never logged.** It lives in `@State`
///    for the length of the edit and goes straight to the Keychain through
///    `EmailAccountModel.save(password:)`. The model has no property to store it in,
///    so there is no path by which it can reach a snapshot, a log line, or the
///    account value's `description` (which `EmailAccount` already restricts to host,
///    port and username).
/// 2. **The account state is honest.** "Not connected", "Checking…" and "N unread"
///    are the only three the chip shows, and each is a fact rather than a mood. The
///    fourth state — a mailbox saved but with no password in the Keychain, which is
///    what a restore-from-backup produces — is surfaced here rather than being
///    flattened into "Not connected", because the fix is different.
/// 3. **The rationale is short and true.** It names what is stored, where, and what
///    is not done.
public struct EmailAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pulseMotion) private var motion

    @Bindable private var model: EmailAccountModel
    @State private var password: String = ""
    @State private var isPasswordFocused = false
    @State private var isConfirmingDisconnect = false

    public init(model: EmailAccountModel) {
        self._model = Bindable(model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThirdHandSpacing.xxl) {
                    switch model.phase {
                    case .notConnected:
                        form
                    case .connected(let account):
                        connected(account)
                    case .needsPassword(let account):
                        needsPassword(account)
                    }
                }
                .padding(.horizontal, ThirdHandSpacing.screenMargin)
                .padding(.vertical, ThirdHandSpacing.l)
                .frame(maxWidth: ThirdHandSpacing.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(ThirdHandColor.surfaceCanvas)
            .navigationTitle("Mailbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("email.done")
                }
            }
            .alert("Disconnect this mailbox?", isPresented: $isConfirmingDisconnect) {
                Button("Disconnect", role: .destructive) {
                    withAnimation(motion.sectionExpansion) { model.disconnect() }
                    password = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Third Hand will forget the address and delete the password from the Keychain. Unread mail will stop appearing on your board.")
            }
        }
    }

    // MARK: Not connected — the form

    private var form: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xl) {
            VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
                Text("Connect a mailbox")
                    .font(ThirdHandTypography.emptyTitle)
                    .foregroundStyle(ThirdHandColor.textPrimary)
                // The orientation paragraph is dropped at AX4+, where it would be
                // three screens of text standing between the user and the first
                // field they came here to fill in. The same facts are on the screen
                // twice more — the password rationale and the Settings privacy
                // block — so nothing is lost that the screen cannot say elsewhere.
                if dynamicTypeSize < .accessibility4 {
                    // "nothing leaves the phone" was false: the password is sent to the
                    // user's own mail server on every check. Say what actually happens
                    // here, because this paragraph sits directly above the field where
                    // the user is about to type it.
                    Text("Third Hand reads unread messages that need you and puts them on the board. It reads only the inbox, and only your password ever leaves the phone - sent to your own mail server, over an encrypted connection, to sign in.")
                        .font(ThirdHandTypography.emptyBody)
                        .foregroundStyle(ThirdHandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: ThirdHandSpacing.m) {
                field(
                    label: "Email address",
                    error: model.draftAddress.isEmpty || model.isAddressValid ? nil : "That doesn't look like an email address."
                ) {
                    TextField("you@example.com", text: $model.draftAddress)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("email.address")
                }

                field(label: "Provider", error: nil) {
                    Picker("Provider", selection: $model.draftProvider) {
                        ForEach(EmailAccount.Provider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("email.provider")
                }

                // Only "Other" asks for a host. A known provider fills it in, which
                // removes the single most common typo (a mail host that is close to,
                // but not, the provider's).
                if model.draftProvider == .other {
                    field(
                        label: "Mail server",
                        error: model.isHostValid ? nil : "Enter the IMAP host, for example imap.mail.me.com."
                    ) {
                        TextField("imap.mail.me.com", text: $model.draftHost)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("email.host")
                    }
                }

                field(label: "App password", error: nil) {
                    SecureField("Password", text: $password)
                        // `.password` opts into the Keychain's autofill *suggestion*
                        // without ever putting the value in a form the app can read
                        // back. `.newPassword` would offer to generate one, which is
                        // wrong here: the value must come from the mail provider.
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("email.password")
                }

                rationale

                if let saveError = model.saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(ThirdHandTypography.meta)
                        .foregroundStyle(ThirdHandColor.statusError)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("email.error")
                }

                Button {
                    save()
                } label: {
                    Text("Connect")
                        .frame(maxWidth: .infinity, minHeight: ThirdHandSpacing.minimumHitTarget)
                }
                .buttonStyle(.pulseProminent())
                .disabled(!model.canSave(password: password))
                .accessibilityIdentifier("email.connect")
            }
        }
    }

    // MARK: Connected

    private func connected(_ account: EmailAccount) -> some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xl) {
            statusHeader(
                title: account.username,
                subtitle: model.statusLine,
                symbol: "checkmark.circle.fill",
                tint: ThirdHandColor.statusDone
            )

            VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
                keyValue("Server", "\(account.host):\(account.port)")
                keyValue("Mailbox", account.mailbox)
                keyValue("Password", "Stored in the iOS Keychain")
            }
            .padding(ThirdHandSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
                Button("Replace password") {
                    withAnimation(motion.sectionExpansion) {
                        model.disconnect()
                        model.draftAddress = account.username
                        model.draftHost = account.host
                    }
                }
                .accessibilityIdentifier("email.replacePassword")

                Button("Disconnect", role: .destructive) { isConfirmingDisconnect = true }
                    .accessibilityIdentifier("email.disconnect")
            }
            .font(ThirdHandTypography.buttonLabel)
        }
    }

    // MARK: Needs password

    private func needsPassword(_ account: EmailAccount) -> some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xl) {
            statusHeader(
                title: account.username,
                subtitle: "Password needed",
                symbol: "exclamationmark.circle.fill",
                tint: ThirdHandColor.statusError
            )

            Text("This mailbox is set up, but the password is no longer on this device — which happens after restoring from a backup. Enter it again to start checking mail.")
                .font(ThirdHandTypography.emptyBody)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: ThirdHandSpacing.m) {
                field(label: "App-specific password", error: nil) {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("email.password")
                }
                rationale
                Button {
                    save()
                } label: {
                    Text("Save password")
                        .frame(maxWidth: .infinity, minHeight: ThirdHandSpacing.minimumHitTarget)
                }
                .buttonStyle(.pulseProminent())
                .disabled(password.isEmpty)
                .accessibilityIdentifier("email.connect")

                Button("Disconnect", role: .destructive) { isConfirmingDisconnect = true }
                    .font(ThirdHandTypography.buttonLabel)
            }
        }
    }

    // MARK: Pieces

    /// The password rationale, in the app's voice: what is stored, where, and what
    /// is not done. Never a reassurance that cannot be checked.
    private var rationale: some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xs) {
            Label {
                Text(EmailAccountModel.passwordRationale(for: model.draftProvider))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
            }
            .font(ThirdHandTypography.meta)
            .foregroundStyle(ThirdHandColor.textSecondary)

            DisclosureGroup("How do I get one?") {
                VStack(alignment: .leading, spacing: ThirdHandSpacing.s) {
                    // Provider-specific, because the phrase "app-specific password" is
                    // Gmail's and pasting Gmail's instructions under iCloud sends the
                    // user looking for a setting Apple does not have by that name.
                    Text(model.draftProvider.passwordGuidance)
                        .font(ThirdHandTypography.meta)
                        .foregroundStyle(ThirdHandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // The prose above is a path across an app switch; the button is
                    // that path in one tap. Offered only where the provider has a
                    // single page to land on (see `appPasswordURL`); where it does
                    // not, the prose is the whole answer rather than half of one.
                    if let url = model.draftProvider.appPasswordURL,
                       let name = model.draftProvider.appPasswordURLHost {
                        Link(destination: url) {
                            Label("Open \(name) settings", systemImage: "arrow.up.right.square")
                                .font(ThirdHandTypography.meta)
                        }
                        .accessibilityIdentifier("email.appPasswordLink")
                    }
                }
                .padding(.top, ThirdHandSpacing.xxs)
            }
            .font(ThirdHandTypography.meta)
            .foregroundStyle(ThirdHandColor.textTertiary)
            .accessibilityIdentifier("email.appPasswordHelp")
        }
        // The rationale is *secondary*; at AX4+ it would push the field it explains
        // off the screen, so it caps rather than competing with the form.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private func statusHeader(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThirdHandSpacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ThirdHandTypography.emptyTitle)
                    .foregroundStyle(ThirdHandColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThirdHandSpacing.s) {
            Text(key)
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textTertiary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(ThirdHandTypography.meta)
                .foregroundStyle(ThirdHandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// A labelled field with its error beneath it, so the message is adjacent to the
    /// control rather than in a banner the eye has to travel to.
    @ViewBuilder
    private func field<Content: View>(
        label: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ThirdHandSpacing.xxs) {
            Text(label)
                .font(ThirdHandTypography.eyebrow)
                .textCase(.uppercase)
                .tracking(ThirdHandTracking.eyebrow)
                .foregroundStyle(ThirdHandColor.textTertiary)
            content()
                .font(ThirdHandTypography.itemDetail)
                .foregroundStyle(ThirdHandColor.textPrimary)
                .padding(.horizontal, ThirdHandSpacing.s)
                .padding(.vertical, ThirdHandSpacing.s)
                .frame(minHeight: ThirdHandSpacing.minimumHitTarget)
                .background(ThirdHandColor.surfaceCard, in: RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ThirdHandRadius.card, style: .continuous)
                        .strokeBorder(
                            error == nil ? ThirdHandColor.separator : ThirdHandColor.statusError,
                            lineWidth: ThirdHandMetrics.hairline
                        )
                }
            if let error {
                Text(error)
                    .font(ThirdHandTypography.meta)
                    .foregroundStyle(ThirdHandColor.statusError)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    private func save() {
        guard model.save(password: password) else { return }
        // Clear the draft immediately: the only copy that should survive is the one
        // in the Keychain.
        password = ""
        isPasswordFocused = false
        dismiss()
    }
}