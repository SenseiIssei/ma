import SwiftUI

/// Settings row: who is signed in, or an invitation to sign in.
struct AccountSettingsRow: View {
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        NavigationLink {
            AccountView()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(accounts.account?.email ?? tr("Sign in or create an account", "Anmelden oder Konto anlegen"))
                    Text(subtitle)
                        .scaledFont(size: 12)
                        .foregroundStyle(Zen.inkSoft)
                }
            } icon: {
                Image(systemName: accounts.isSignedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
            }
        }
    }

    private var subtitle: String {
        guard let account = accounts.account else { return tr("Optional. Ma works without one.", "Freiwillig. Ma funktioniert auch ohne.") }
        return account.verified ? tr("Signed in", "Angemeldet") : tr("Please confirm your email", "Bitte bestätige deine E-Mail")
    }
}

struct AccountView: View {
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let account = accounts.account {
                    SignedInCard(account: account)
                } else {
                    SignInCard()
                }
                if let info = accounts.infoMessage {
                    Label(info, systemImage: "envelope.badge")
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.matcha)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = accounts.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(tr("An account is optional. Everything you do in Ma stays on your iPhone either way; the account only holds your email and, for some features, what they need.",
                        "Ein Konto ist freiwillig. Was du in Ma machst, bleibt so oder so auf deinem iPhone; das Konto enthält nur deine E-Mail und, für manche Funktionen, was diese brauchen."))
                    .scaledFont(size: 12)
                    .foregroundStyle(Zen.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle(tr("Account", "Konto"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await accounts.refresh() }
        .onDisappear {
            accounts.errorMessage = nil
            accounts.infoMessage = nil
        }
    }
}

private struct SignInCard: View {
    @Environment(AccountStore.self) private var accounts
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var field: Field?

    enum Field { case email, password }

    private var ready: Bool {
        email.contains("@") && password.count >= (creating ? 8 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $creating) {
                Text(tr("Sign in", "Anmelden")).tag(false)
                Text(tr("Create account", "Registrieren")).tag(true)
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                TextField(tr("Email", "E-Mail"), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($field, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { field = .password }
                    .modifier(AccountFieldStyle())
                SecureField(creating ? tr("Password, at least 8 characters", "Passwort, mindestens 8 Zeichen") : tr("Password", "Passwort"), text: $password)
                    .textContentType(creating ? .newPassword : .password)
                    .focused($field, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
                    .modifier(AccountFieldStyle())
            }

            Button {
                Task { await submit() }
            } label: {
                if accounts.busy {
                    ProgressView().tint(.white)
                } else {
                    Text(creating ? tr("Create account", "Konto anlegen") : tr("Sign in", "Anmelden"))
                }
            }
            .buttonStyle(.primary)
            .disabled(!ready || accounts.busy)
            .opacity(ready ? 1 : 0.5)

            if !creating {
                Button(tr("Forgot password?", "Passwort vergessen?")) {
                    Task { _ = await accounts.forgotPassword(email: email) }
                }
                .scaledFont(size: 14, weight: .semibold)
                .disabled(!email.contains("@") || accounts.busy)
            }

            if GoogleSignIn.isAvailable {
                HStack {
                    Rectangle().fill(Zen.line).frame(height: 1)
                    Text(tr("or", "oder")).scaledFont(size: 12).foregroundStyle(Zen.inkFaint)
                    Rectangle().fill(Zen.line).frame(height: 1)
                }
                Button {
                    Task { _ = await accounts.signInWithGoogle() }
                } label: {
                    Label(tr("Continue with Google", "Weiter mit Google"), systemImage: "g.circle.fill")
                }
                .buttonStyle(.quiet)
                .disabled(accounts.busy)
            }
        }
        .zenCard()
    }

    private func submit() async {
        guard ready else { return }
        field = nil
        let ok: Bool = creating
            ? await accounts.register(email: email, password: password)
            : await accounts.login(email: email, password: password)
        if ok {
            password = ""
            Haptics.success()
        }
    }
}

private struct SignedInCard: View {
    @Environment(AccountStore.self) private var accounts
    let account: AccountDTO
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                IconBadge(systemName: "person.crop.circle.fill", tint: Zen.shu, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.email)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    Label(account.verified ? tr("Email confirmed", "E-Mail bestätigt") : tr("Email not confirmed yet", "E-Mail noch nicht bestätigt"),
                          systemImage: account.verified ? "checkmark.seal.fill" : "envelope.badge")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(account.verified ? Zen.matcha : Zen.kin)
                    if account.google {
                        Text(tr("Linked with Google", "Mit Google verbunden"))
                            .scaledFont(size: 12)
                            .foregroundStyle(Zen.inkSoft)
                    }
                }
            }
            if !account.verified {
                Text(tr("Tap the link in the mail we sent you. Nothing arrived?", "Tipp auf den Link in der Mail, die wir dir geschickt haben. Nichts angekommen?"))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                Button(tr("Send the mail again", "Mail nochmal schicken")) {
                    Task { await accounts.resendConfirmation() }
                }
                .buttonStyle(.quiet)
                .disabled(accounts.busy)
            }
            if account.has("daily") || account.has("reminders") {
                Divider().overlay(Zen.line)
                Text(tr("Just for you", "Nur für dich"))
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Zen.inkSoft)
                if account.has("daily") {
                    NavigationLink {
                        DailyLinkView()
                    } label: {
                        Label(tr("Link senseiissei.dev", "Mit senseiissei.dev verbinden"), systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                if account.has("reminders") {
                    NavigationLink {
                        NotifyView()
                    } label: {
                        Label(tr("Reminders on Telegram and Discord", "Erinnerungen per Telegram und Discord"), systemImage: "bell.badge")
                    }
                }
            }
            Divider().overlay(Zen.line)
            Button(tr("Sign out", "Abmelden")) {
                Task { await accounts.signOut() }
            }
            .buttonStyle(.quiet)
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text(tr("Delete account", "Konto löschen")).foregroundStyle(Zen.negative)
            }
            .scaledFont(size: 14, weight: .semibold)
            .confirmationDialog(tr("Delete your account?", "Konto löschen?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(tr("Delete account", "Konto löschen"), role: .destructive) {
                    Task { _ = await accounts.deleteAccount() }
                }
            } message: {
                Text(tr("The account and everything linked to it on the server are removed. Ma on this iPhone keeps working.",
                        "Das Konto und alles, was auf dem Server daran hängt, wird gelöscht. Ma auf diesem iPhone funktioniert weiter."))
            }
        }
        .zenCard()
    }
}

private struct AccountFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scaledFont(size: 16)
            .padding(14)
            .background(Zen.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Reminders

/// Telegram and Discord, each linked with one tap. Only for accounts with
/// the "reminders" feature.
struct NotifyView: View {
    @Environment(AccountStore.self) private var accounts
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: NotifyStatusDTO?
    @State private var time = Date()
    @State private var testResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("Every morning Ma sends you the lesson of the day, the streak and music to work to. Tap to link; no ids to copy.",
                        "Jeden Morgen schickt dir Ma die Lektion des Tages, die Serie und Musik zum Arbeiten. Einmal antippen zum Verbinden, keine IDs abtippen."))
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if let status {
                    channelRow("telegram", title: "Telegram", symbol: "paperplane.fill", tint: Zen.ai, channel: status.telegram)
                    channelRow("discord", title: "Discord", symbol: "bubble.left.and.bubble.right.fill", tint: Zen.shu, channel: status.discord)
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker(tr("Reminder time", "Uhrzeit der Erinnerung"), selection: $time, displayedComponents: .hourAndMinute)
                            .scaledFont(size: 16, weight: .semibold)
                            .onChange(of: time) { _, value in
                                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                                let text = String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
                                Task { await accounts.notifyTime(text) }
                            }
                        Button(tr("Send a test message", "Testnachricht schicken")) {
                            Task {
                                if let failures = await accounts.notifyTest() {
                                    testResult = failures.isEmpty ? tr("Sent. Check Telegram and Discord.", "Gesendet. Schau in Telegram und Discord.")
                                                                  : failures.joined(separator: "\n")
                                }
                            }
                        }
                        .buttonStyle(.quiet)
                        .disabled(!(status.telegram.connected || status.discord.connected) || accounts.busy)
                        if let testResult {
                            Text(testResult).scaledFont(size: 13).foregroundStyle(Zen.inkSoft)
                        }
                    }
                    .zenCard()
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if let error = accounts.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.negative)
                }
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.vertical, 12)
        }
        .background(AppBackground())
        .navigationTitle(tr("Reminders", "Erinnerungen"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // Back from Telegram or the Discord page: show the new link.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .maNotifyLinked)) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        guard let fresh = await accounts.notifyStatus() else { return }
        status = fresh
        let parts = fresh.time.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2, let date = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) {
            time = date
        }
    }

    private func channelRow(_ id: String, title: String, symbol: String, tint: Color, channel: NotifyChannelDTO) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).scaledFont(size: 16, weight: .semibold).foregroundStyle(Zen.ink)
                Text(channel.connected ? tr("Linked: \(channel.label ?? title)", "Verbunden: \(channel.label ?? title)")
                                       : channel.available ? tr("Not linked", "Nicht verbunden")
                                                           : tr("Not set up on the server yet", "Auf dem Server noch nicht eingerichtet"))
                    .scaledFont(size: 13)
                    .foregroundStyle(channel.connected ? Zen.matcha : Zen.inkSoft)
            }
            Spacer(minLength: 0)
            if channel.connected {
                Button(tr("Unlink", "Trennen")) {
                    Task {
                        await accounts.notifyUnlink(id)
                        await load()
                    }
                }
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Zen.negative)
            } else if channel.available {
                Button(tr("Link", "Verbinden")) {
                    Task {
                        if let url = await accounts.notifyLink(id) { openURL(url) }
                    }
                }
                .buttonStyle(InkButtonStyle(kind: .shu, fullWidth: false))
                .disabled(accounts.busy)
            }
        }
        .zenCard()
    }
}

extension Notification.Name {
    static let maNotifyLinked = Notification.Name("ma.notifyLinked")
}
