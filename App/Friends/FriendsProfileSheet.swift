import SwiftUI

/// Nickname and avatar. The first time, this is also where sharing starts.
struct FriendsProfileSheet: View {
    enum Mode { case setup, edit }

    let mode: Mode
    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var avatar: String
    @FocusState private var nameFocused: Bool

    init(mode: Mode, nickname: String = "", avatar: String = FriendAvatar.fallback) {
        self.mode = mode
        _nickname = State(initialValue: nickname)
        _avatar = State(initialValue: FriendAvatar.symbol(avatar))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    private var cleaned: String { FriendsStore.cleanNickname(nickname) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    preview
                    nameField
                    avatarGrid
                    if let message = store.errorMessage {
                        FriendsErrorBanner(message: message) { store.errorMessage = nil }
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        if store.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode == .setup ? tr("Start sharing", "Teilen beginnen") : tr("Save", "Sichern"))
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(cleaned.isEmpty || store.isLoading)
                    .opacity(cleaned.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(mode == .setup ? tr("Your nickname", "Dein Spitzname") : tr("Profile", "Profil"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                        .foregroundStyle(Zen.ink)
                }
            }
            .onAppear {
                store.errorMessage = nil
                if nickname.isEmpty { nameFocused = true }
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 10) {
            FriendAvatarBadge(avatar: avatar, size: 76, highlighted: true)
            Text(cleaned.isEmpty ? tr("Nickname", "Spitzname") : cleaned)
                .font(.display(22))
                .foregroundStyle(cleaned.isEmpty ? Zen.inkFaint : Zen.ink)
            Text(tr("Only people in your circles see this. Pick anything, it does not have to be your name.",
                    "Nur Leute in deinen Kreisen sehen das. Nimm irgendwas, es muss nicht dein Name sein."))
                .font(.system(size: 14))
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "person.text.rectangle", title: tr("Nickname", "Spitzname")) {
                Text("\(cleaned.count)/\(FriendLimits.nickname)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Zen.inkFaint)
            }
            TextField(tr("e.g. Night Owl", "z. B. Nachteule"), text: $nickname)
                .font(.system(size: 17, weight: .medium))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .zenCard(padding: 16)
                .onChange(of: nickname) { _, value in
                    // Hard stop at the server's limit instead of an error later.
                    if value.count > FriendLimits.nickname {
                        nickname = String(value.prefix(FriendLimits.nickname))
                    }
                }
        }
    }

    private var avatarGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "face.smiling", title: tr("Avatar", "Avatar"))
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(FriendAvatar.all, id: \.self) { symbol in
                    Button {
                        Haptics.tap()
                        avatar = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(avatar == symbol ? Color.white : Zen.ink)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(avatar == symbol ? AnyShapeStyle(Zen.shu) : AnyShapeStyle(Zen.sand))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(avatar == symbol ? .isSelected : [])
                }
            }
            .zenCard(padding: 14)
        }
    }

    private func save() async {
        let ok: Bool
        switch mode {
        case .setup: ok = await store.enable(nickname: cleaned, avatar: avatar)
        case .edit: ok = await store.updateProfile(nickname: cleaned, avatar: avatar)
        }
        if ok {
            Haptics.success()
            dismiss()
        }
    }
}
