import SwiftUI

/// "Friends without a feed": small circles that see each other's daily
/// numbers and nothing else. Expects a `FriendsStore` in the environment and
/// a surrounding NavigationStack (push it, or wrap it in one).
struct FriendsView: View {
    @Environment(FriendsStore.self) private var store
    @State private var profileSheet: FriendsProfileSheet.Mode?
    @State private var confirmDisable = false
    @State private var confirmDelete = false
    @State private var newCircleName = ""
    @State private var joinCode = ""
    @State private var openCircle: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ScreenHeader(title: tr("Friends", "Freunde"),
                             subtitle: tr("Without a feed. Just a few numbers a day.", "Ohne Feed. Nur ein paar Zahlen am Tag."))
                if let message = store.errorMessage {
                    FriendsErrorBanner(message: message) { store.errorMessage = nil }
                }
                if store.isEnabled {
                    profileCard
                    circlesSection
                    createCard
                    joinCard
                    sharedSummary
                    deleteSection
                } else {
                    Illustration(name: "IllustrationHabits", height: 170)
                    intro
                    optInCard
                    if store.hasIdentity { deleteSection }
                }
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openCircle) { id in
            FriendsCircleView(circleId: id)
                .environment(store)
        }
        .sheet(item: $profileSheet) { mode in
            FriendsProfileSheet(mode: mode,
                                nickname: store.profile?.nickname ?? "",
                                avatar: store.profile?.avatar ?? FriendAvatar.fallback)
                .environment(store)
        }
        .confirmationDialog(tr("Stop sharing?", "Teilen beenden?"), isPresented: $confirmDisable, titleVisibility: .visible) {
            Button(tr("Stop sharing", "Teilen beenden")) { store.disable() }
        } message: {
            Text(tr("Nothing new is uploaded from now on. Your circles and the numbers already sent stay until you delete your data.",
                    "Ab jetzt wird nichts Neues hochgeladen. Deine Kreise und die schon gesendeten Zahlen bleiben, bis du deine Daten löschst."))
        }
        .confirmationDialog(tr("Delete all your Friends data?", "Alle deine Friends-Daten löschen?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("Delete everything", "Alles löschen"), role: .destructive) {
                Task {
                    if await store.deleteAllData() { Haptics.success() }
                }
            }
        } message: {
            Text(tr("Your nickname, your numbers and your place in every circle are removed from the server right away. Circles you created pass to the next member. This cannot be undone.",
                    "Dein Spitzname, deine Zahlen und dein Platz in jedem Kreis werden sofort vom Server entfernt. Kreise, die du gegründet hast, gehen an das nächste Mitglied. Das lässt sich nicht rückgängig machen."))
        }
        .task {
            if store.isEnabled { await store.refreshCircles() }
        }
        .refreshable {
            await store.refreshCircles()
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("Keep each other going, without a feed. A circle of up to 20 people sees how your day went in numbers. No posts, no messages, no likes.",
                    "Haltet euch gegenseitig bei der Stange, ohne Feed. Ein Kreis aus bis zu 20 Leuten sieht in Zahlen, wie dein Tag lief. Keine Posts, keine Nachrichten, keine Likes."))
                .scaledFont(size: 16)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "eye", title: tr("What your circles see", "Was deine Kreise sehen"))
                VStack(alignment: .leading, spacing: 12) {
                    FriendsFactRow(icon: "person.crop.circle", text: tr("A nickname and a symbol you pick", "Ein Spitzname und ein Symbol, die du aussuchst"))
                    FriendsFactRow(icon: "flame", text: tr("Your streak in days", "Deine Serie in Tagen"))
                    FriendsFactRow(icon: "timer", text: tr("Focus minutes and focus rounds", "Fokusminuten und Fokusrunden"))
                    FriendsFactRow(icon: "hand.raised", text: tr("How often you let an app be", "Wie oft du eine App ruhen gelassen hast"))
                    FriendsFactRow(icon: "checkmark.seal", text: tr("How many cards you answered right", "Wie viele Karten du richtig beantwortet hast"))
                    FriendsFactRow(icon: "leaf", text: tr("How many habits you ticked off, only the count", "Wie viele Gewohnheiten du abgehakt hast, nur die Zahl"))
                    Text(tr("One set of numbers per day. The server keeps them for 30 days at most.",
                            "Eine Reihe Zahlen pro Tag. Der Server behält sie höchstens 30 Tage."))
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .zenCard()
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "lock", title: tr("What never leaves your phone", "Was dein Handy nie verlässt"))
                VStack(alignment: .leading, spacing: 12) {
                    FriendsFactRow(icon: "app.badge", text: tr("Which apps and sites you use or block", "Welche Apps und Seiten du nutzt oder sperrst"), tint: Zen.matcha)
                    FriendsFactRow(icon: "book.closed", text: tr("Your journal, mood, intentions and habit names", "Dein Tagebuch, deine Stimmung, Vorsätze und Namen der Gewohnheiten"), tint: Zen.matcha)
                    FriendsFactRow(icon: "rectangle.stack", text: tr("Your topics, cards and answers", "Deine Themen, Karten und Antworten"), tint: Zen.matcha)
                    FriendsFactRow(icon: "person.2.slash", text: tr("Your name, email, phone number and contacts", "Dein Name, deine E-Mail, Telefonnummer und Kontakte"), tint: Zen.matcha)
                    FriendsFactRow(icon: "location.slash", text: tr("Where you are", "Wo du bist"), tint: Zen.matcha)
                    Text(tr("There is no account. Your phone makes a random key and keeps it in the Keychain. You can delete everything on the server with one tap.",
                            "Es gibt kein Konto. Dein Handy erzeugt einen zufälligen Schlüssel und bewahrt ihn im Schlüsselbund auf. Mit einem Tipp löschst du alles auf dem Server."))
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .zenCard()
            }
        }
    }

    private var optInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: sharingBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Share my daily numbers", "Meine Tageszahlen teilen"))
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    Text(tr("Off by default. Nothing is sent until you switch this on.",
                            "Standardmäßig aus. Nichts wird gesendet, bevor du das einschaltest."))
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Zen.shu)
            .disabled(store.isLoading)
            if store.isLoading { ProgressView().frame(maxWidth: .infinity) }
        }
        .zenCard()
    }

    /// On: first time asks for a nickname, later just resumes. Off: asks first.
    private var sharingBinding: Binding<Bool> {
        Binding(
            get: { store.isEnabled },
            set: { on in
                if on {
                    if let profile = store.profile, store.hasIdentity {
                        Task { _ = await store.enable(nickname: profile.nickname, avatar: profile.avatar) }
                    } else {
                        profileSheet = .setup
                    }
                } else {
                    confirmDisable = true
                }
            }
        )
    }

    // MARK: Enabled

    private var profileCard: some View {
        HStack(spacing: 14) {
            FriendAvatarBadge(avatar: store.profile?.avatar ?? FriendAvatar.fallback, size: 52, highlighted: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.profile?.nickname ?? "")
                    .displayFont(20)
                    .foregroundStyle(Zen.ink)
                Text(tr("Sharing your daily numbers", "Du teilst deine Tageszahlen"))
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
            }
            // The card's tap gesture is invisible to VoiceOver; the name acts as the button.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(tr("Edit profile", "Profil bearbeiten"))
            .accessibilityAction { profileSheet = .edit }
            Spacer(minLength: 8)
            Toggle("", isOn: sharingBinding)
                .labelsHidden()
                .tint(Zen.shu)
                .accessibilityLabel(tr("Share my daily numbers", "Meine Tageszahlen teilen"))
        }
        .zenCard()
        .contentShape(Rectangle())
        .onTapGesture { profileSheet = .edit }
    }

    private var circlesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "person.3", title: tr("Your circles", "Deine Kreise")) {
                if store.isLoading { ProgressView().controlSize(.small) }
            }
            if store.circles.isEmpty {
                Text(tr("No circle yet. Start one below and send the code to a few friends, or join theirs.",
                        "Noch kein Kreis. Gründe unten einen und schick den Code an ein paar Freunde, oder tritt ihrem bei."))
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .zenCard()
            } else {
                ForEach(store.circles) { circle in
                    Button {
                        openCircle = circle.id
                    } label: {
                        circleRow(circle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func circleRow(_ circle: CircleSummary) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: circle.isCreator ? "person.3.fill" : "person.3", tint: Zen.shu, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(circle.name)
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Zen.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(tr("\(circle.memberCount) of \(circle.maxMembers)", "\(circle.memberCount) von \(circle.maxMembers)"))
                        .monospacedDigit()
                    if let challenge = ChallengeKind.find(circle.challengeKind) {
                        Label(challenge.title, systemImage: challenge.icon)
                            .lineLimit(1)
                    }
                }
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Zen.inkSoft)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Zen.inkFaint)
                .accessibilityHidden(true)
        }
        .zenCard(padding: 14)
        .contentShape(Rectangle())
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "plus.circle", title: tr("Start a circle", "Kreis gründen"))
            VStack(spacing: 12) {
                TextField(tr("Name, e.g. Morning crew", "Name, z. B. Frühaufsteher"), text: $newCircleName)
                    .scaledFont(size: 17)
                    .submitLabel(.done)
                    .padding(14)
                    .background(Zen.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: newCircleName) { _, value in
                        if value.count > FriendLimits.circleName {
                            newCircleName = String(value.prefix(FriendLimits.circleName))
                        }
                    }
                Button(tr("Create circle", "Kreis gründen")) {
                    Task {
                        if let circle = await store.createCircle(name: newCircleName) {
                            Haptics.success()
                            newCircleName = ""
                            openCircle = circle.id
                        }
                    }
                }
                .buttonStyle(.primary)
                .disabled(newCircleName.trimmingCharacters(in: .whitespaces).isEmpty || store.isLoading)
            }
            .zenCard()
        }
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "key", title: tr("Join with a code", "Mit Code beitreten"))
            VStack(spacing: 12) {
                TextField(tr("8 characters", "8 Zeichen"), text: $joinCode)
                    .scaledFont(size: 22, weight: .semibold, design: .monospaced)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .padding(14)
                    .background(Zen.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: joinCode) { _, value in
                        // Pasted codes often carry spaces or a dash; keep only code letters.
                        let clean = FriendLimits.cleanCode(value)
                        if clean != value { joinCode = clean }
                    }
                    .onSubmit(join)
                Button(tr("Join circle", "Kreis beitreten"), action: join)
                    .buttonStyle(.ink)
                    .disabled(joinCode.count != FriendLimits.codeLength || store.isLoading)
            }
            .zenCard()
        }
    }

    private func join() {
        guard joinCode.count == FriendLimits.codeLength else { return }
        Task {
            if let circle = await store.join(code: joinCode) {
                Haptics.success()
                joinCode = ""
                openCircle = circle.id
            }
        }
    }

    private var sharedSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "eye", title: tr("What you share", "Was du teilst"))
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Once a day, when you open Ma: streak, focus minutes, focus rounds, impulses resisted, right answers and the number of habits done. Nothing else.",
                        "Einmal am Tag, wenn du Ma öffnest: Serie, Fokusminuten, Fokusrunden, abgewehrte Impulse, richtige Antworten und die Zahl erledigter Gewohnheiten. Sonst nichts."))
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let last = store.settings.lastUpload {
                    Text(tr("Last sent: \(last.date)", "Zuletzt gesendet: \(last.date)"))
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .monospacedDigit()
                }
            }
            .zenCard()
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(tr("Delete my data", "Meine Daten löschen"), role: .destructive) {
                confirmDelete = true
            }
            .buttonStyle(.destructive)
            .disabled(store.isLoading)
            Text(tr("Removes your nickname, numbers and memberships from the server at once and forgets the key on this phone.",
                    "Entfernt Spitzname, Zahlen und Mitgliedschaften sofort vom Server und vergisst den Schlüssel auf diesem Handy."))
                .scaledFont(size: 13)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }
}

extension FriendsProfileSheet.Mode: Identifiable {
    var id: Self { self }
}
