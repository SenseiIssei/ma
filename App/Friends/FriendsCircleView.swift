import SwiftUI
import UIKit

/// One circle: everyone's last seven days as rings, the weekly challenge and
/// the invite code. Creator-only actions appear only for the creator.
struct FriendsCircleView: View {
    let circleId: String
    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = []
    @State private var confirmLeave = false
    @State private var confirmRotate = false
    @State private var memberToRemove: CircleMember?
    @State private var showChallenges = false
    @State private var copied = false

    private var detail: CircleDetail? { store.details[circleId] }
    private var isMember: Bool { store.circles.contains { $0.id == circleId } }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let message = store.errorMessage {
                    FriendsErrorBanner(message: message) { store.errorMessage = nil }
                }
                if let detail {
                    header(detail)
                    challengeCard(detail)
                    membersSection(detail)
                    inviteCard(detail)
                    leaveSection(detail)
                } else if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.bottom, 40)
        }
        .background(AppBackground())
        .navigationTitle(detail?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadCircle(circleId) }
        .refreshable { await store.loadCircle(circleId) }
        .onChange(of: isMember) { _, stillIn in
            // Removed, left or deleted elsewhere: there is nothing to show.
            if !stillIn && detail == nil { dismiss() }
        }
        .sheet(isPresented: $showChallenges) {
            if let detail {
                ChallengePickerSheet(circleId: detail.id, current: detail.challengeKind)
                    .environment(store)
            }
        }
        .confirmationDialog(tr("Leave this circle?", "Diesen Kreis verlassen?"), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(tr("Leave", "Verlassen"), role: .destructive) {
                Task {
                    if await store.leave(circleId) { dismiss() }
                }
            }
        } message: {
            Text(detail?.isCreator == true
                 ? tr("You created it, so the member who joined first after you takes over. If you are the last one, the circle is deleted.",
                      "Du hast ihn gegründet, also übernimmt das Mitglied, das nach dir als Erstes beigetreten ist. Bist du die letzte Person, wird der Kreis gelöscht.")
                 : tr("The others will no longer see your numbers. You can come back with the invite code.",
                      "Die anderen sehen deine Zahlen dann nicht mehr. Mit dem Einladungscode kannst du zurückkommen."))
        }
        .confirmationDialog(tr("Make a new code?", "Neuen Code erzeugen?"), isPresented: $confirmRotate, titleVisibility: .visible) {
            Button(tr("New code", "Neuer Code")) {
                Task { await store.rotateCode(circleId) }
            }
        } message: {
            Text(tr("The old code stops working at once. Everyone already in the circle stays.",
                    "Der alte Code funktioniert sofort nicht mehr. Wer schon im Kreis ist, bleibt."))
        }
        .confirmationDialog(
            tr("Remove \(memberToRemove?.nickname ?? "")?", "\(memberToRemove?.nickname ?? "") entfernen?"),
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button(tr("Remove from circle", "Aus dem Kreis entfernen"), role: .destructive) {
                if let member = memberToRemove {
                    Task { await store.remove(member.id, from: circleId) }
                }
                memberToRemove = nil
            }
        } message: {
            Text(tr("They can rejoin with the current code. Make a new code if they should not.",
                    "Mit dem aktuellen Code kann die Person wieder beitreten. Erzeug einen neuen Code, wenn das nicht passieren soll."))
        }
    }

    // MARK: Header

    private func header(_ detail: CircleDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.name)
                .displayFont(30)
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(tr("\(detail.memberCount) of \(detail.maxMembers) members", "\(detail.memberCount) von \(detail.maxMembers) Mitgliedern"))
                .scaledFont(size: 15)
                .foregroundStyle(Zen.inkSoft)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: Challenge

    private func challengeCard(_ detail: CircleDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "flag.checkered", title: tr("This week", "Diese Woche")) {
                if detail.isCreator {
                    Button(detail.challenge == nil ? tr("Choose", "Wählen") : tr("Change", "Ändern")) {
                        showChallenges = true
                    }
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Zen.shu)
                }
            }
            Group {
                if let challenge = detail.challenge {
                    challengeProgress(challenge, memberCount: detail.members.count)
                } else {
                    Text(detail.isCreator
                         ? tr("No challenge yet. Pick one the whole circle can work on this week.",
                              "Noch keine Challenge. Such eine aus, an der der ganze Kreis diese Woche arbeiten kann.")
                         : tr("No challenge this week. The creator of the circle can pick one.",
                              "Diese Woche keine Challenge. Wer den Kreis gegründet hat, kann eine aussuchen."))
                        .scaledFont(size: 15)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .zenCard()
        }
    }

    private func challengeProgress(_ challenge: ChallengeProgress, memberCount: Int) -> some View {
        let kind = ChallengeKind.find(challenge.kind)
        let tint = challenge.completed ? Zen.matcha : Zen.shu
        let percent = Int((challenge.progress * 100).rounded())
        let doneCount = challenge.members.filter { $0.value >= challenge.target }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(systemName: challenge.completed ? "checkmark" : (kind?.icon ?? "flag"), tint: tint, size: 44, filled: challenge.completed)
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind?.title ?? challenge.title)
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    if let detail = kind?.detail {
                        Text(detail)
                            .scaledFont(size: 13)
                            .foregroundStyle(Zen.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            InkProgress(value: challenge.progress, color: tint, height: 10)
                // The line below says the same in words.
                .accessibilityHidden(true)
            HStack {
                if challenge.mode == "each" {
                    Text(tr("\(doneCount) of \(memberCount) there", "\(doneCount) von \(memberCount) geschafft"))
                } else {
                    Text(tr("\(challenge.total) of \(challenge.goal)", "\(challenge.total) von \(challenge.goal)"))
                }
                Spacer()
                Text(challenge.completed ? tr("Done this week", "Diese Woche geschafft") : tr("\(percent)%", "\(percent) %"))
                    .foregroundStyle(tint)
            }
            .scaledFont(size: 14, weight: .semibold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(Zen.inkSoft)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Members

    private func membersSection(_ detail: CircleDetail) -> some View {
        let keys = FriendWeek.keys()
        let letters = FriendWeek.letters()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "person.3", title: tr("Last 7 days", "Letzte 7 Tage"))
            VStack(spacing: 0) {
                ForEach(Array(detail.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 {
                        Divider().overlay(Zen.line).padding(.vertical, 12)
                    }
                    memberRow(member, keys: keys, letters: letters, canRemove: detail.isCreator && !member.isMe)
                }
            }
            .zenCard()
            legend
        }
    }

    private func memberRow(_ member: CircleMember, keys: [String], letters: [String], canRemove: Bool) -> some View {
        let isOpen = expanded.contains(member.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FriendAvatarBadge(avatar: member.avatar, size: 40, highlighted: member.isMe)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.nickname)
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(Zen.ink)
                            .lineLimit(2)
                        if member.isMe {
                            Text(tr("you", "du"))
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(Zen.shu)
                        }
                        if member.isCreator {
                            Image(systemName: "crown.fill")
                                .scaledFont(size: 11)
                                .foregroundStyle(Zen.kin)
                                .accessibilityLabel(tr("creator", "gegründet"))
                        }
                    }
                    if member.streak > 0 {
                        Label(tr("\(member.streak) day streak", "\(member.streak) Tage Serie"), systemImage: "flame.fill")
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundStyle(Zen.kin)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Zen.inkFaint)
                    .accessibilityHidden(true)
            }
            // The tap gesture below is invisible to VoiceOver, so the name
            // row acts as the button that shows today's numbers.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOpen ? tr("Expanded", "Ausgeklappt") : tr("Collapsed", "Eingeklappt"))
            .accessibilityAction {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if isOpen { expanded.remove(member.id) } else { expanded.insert(member.id) }
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<keys.count, id: \.self) { i in
                    VStack(spacing: 4) {
                        FriendDayRings(day: member.day(keys[i]), size: 34)
                        Text(letters[i])
                            .scaledFont(size: 11, weight: i == keys.count - 1 ? .bold : .medium)
                            .foregroundStyle(i == keys.count - 1 ? Zen.ink : Zen.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekSummary(member, keys: keys))
            if isOpen {
                dayTiles(member.day(keys.last ?? "") ?? member.days.first)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                if isOpen { expanded.remove(member.id) } else { expanded.insert(member.id) }
            }
        }
        .contextMenu {
            if canRemove {
                Button(role: .destructive) {
                    memberToRemove = member
                } label: {
                    Label(tr("Remove from circle", "Aus dem Kreis entfernen"), systemImage: "person.badge.minus")
                }
            }
        }
    }

    @ViewBuilder
    private func dayTiles(_ day: FriendDay?) -> some View {
        if let day {
            VStack(alignment: .leading, spacing: 10) {
                Text(day.date == FriendWeek.keys().last ? tr("Today", "Heute") : day.date)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Zen.inkSoft)
                    .monospacedDigit()
                HStack(alignment: .top, spacing: 8) {
                    StatTile(icon: "timer", value: "\(day.focusMinutes)", label: tr("focus min", "Fokus-Min."), tint: Zen.shu)
                    StatTile(icon: "circle.dashed", value: "\(day.pomodoros)", label: tr("rounds", "Runden"), tint: Zen.shu)
                    StatTile(icon: "hand.raised", value: "\(day.resisted)", label: tr("resisted", "widerstanden"), tint: Zen.kin)
                }
                HStack(alignment: .top, spacing: 8) {
                    StatTile(icon: "checkmark.seal", value: "\(day.correctAnswers)", label: tr("right", "richtig"), tint: Zen.ai)
                    StatTile(icon: "leaf", value: "\(day.habitsDone)", label: tr("habits", "Gewohnheiten"), tint: Zen.matcha)
                    StatTile(icon: "flame", value: "\(day.streakDays)", label: tr("streak", "Serie"), tint: Zen.kin)
                }
            }
            .padding(12)
            .background(Zen.sand.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Text(tr("Nothing shared yet this week.", "Diese Woche noch nichts geteilt."))
                .scaledFont(size: 13)
                .foregroundStyle(Zen.inkSoft)
        }
    }

    private func weekSummary(_ member: CircleMember, keys: [String]) -> String {
        let active = keys.filter { member.day($0) != nil }.count
        guard let today = member.day(keys.last ?? "") else {
            return tr("\(member.nickname): shared on \(active) of the last 7 days, nothing today yet.",
                      "\(member.nickname): an \(active) der letzten 7 Tage geteilt, heute noch nichts.")
        }
        return tr("\(member.nickname): shared on \(active) of the last 7 days. Today \(today.focusMinutes) focus minutes, \(today.correctAnswers) right answers, \(today.habitsDone) habits.",
                  "\(member.nickname): an \(active) der letzten 7 Tage geteilt. Heute \(today.focusMinutes) Fokusminuten, \(today.correctAnswers) richtige Antworten, \(today.habitsDone) Gewohnheiten.")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Zen.shu, tr("Focus \(FriendDayGoal.focusMinutes) min", "Fokus \(FriendDayGoal.focusMinutes) Min."))
            legendItem(Zen.ai, tr("\(FriendDayGoal.correctAnswers) right", "\(FriendDayGoal.correctAnswers) richtig"))
            legendItem(Zen.matcha, tr("\(FriendDayGoal.habits) habits", "\(FriendDayGoal.habits) Gewohnh."))
        }
        .scaledFont(size: 12, weight: .medium)
        .foregroundStyle(Zen.inkSoft)
        .padding(.horizontal, 4)
    }

    private func legendItem(_ tint: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(text).lineLimit(2).minimumScaleFactor(0.8)
        }
    }

    // MARK: Invite

    private func inviteCard(_ detail: CircleDetail) -> some View {
        let code = detail.inviteCode
        let spaced = code.count == 8 ? "\(code.prefix(4)) \(code.suffix(4))" : code
        let message = tr("Join my circle \"\(detail.name)\" in Ma. Friends without a feed, just a few numbers a day. Invite code: \(code)",
                         "Komm in meinen Kreis \"\(detail.name)\" in Ma. Freunde ohne Feed, nur ein paar Zahlen am Tag. Einladungscode: \(code)")
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "envelope.open", title: tr("Invite", "Einladen"))
            VStack(spacing: 16) {
                Text(spaced)
                    .scaledFont(size: 34, weight: .bold, design: .monospaced)
                    .foregroundStyle(Zen.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(tr("Invite code \(code.map(String.init).joined(separator: " "))",
                                           "Einladungscode \(code.map(String.init).joined(separator: " "))"))
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = code
                        Haptics.success()
                        withAnimation { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? tr("Copied", "Kopiert") : tr("Copy", "Kopieren"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.quiet)
                    ShareLink(item: message) {
                        Label(tr("Share", "Teilen"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.primary)
                }
                if detail.isCreator {
                    Button {
                        confirmRotate = true
                    } label: {
                        Label(tr("Make a new code", "Neuen Code erzeugen"), systemImage: "arrow.triangle.2.circlepath")
                            .scaledFont(size: 15, weight: .semibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Zen.shu)
                    .disabled(store.isLoading)
                }
                Text(tr("Anyone with this code can join until the circle has \(detail.maxMembers) members.",
                        "Wer diesen Code hat, kann beitreten, bis der Kreis \(detail.maxMembers) Mitglieder hat."))
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .zenCard()
        }
    }

    // MARK: Leave

    private func leaveSection(_ detail: CircleDetail) -> some View {
        Button(role: .destructive) {
            confirmLeave = true
        } label: {
            // Inner style wins over the button style's ink colour.
            Text(tr("Leave circle", "Kreis verlassen")).foregroundStyle(Zen.negative)
        }
        .buttonStyle(.quiet)
        .disabled(store.isLoading)
        .padding(.top, 8)
    }
}

/// The fixed list of weekly challenges, for the creator.
private struct ChallengePickerSheet: View {
    let circleId: String
    let current: String?
    @Environment(FriendsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(tr("Everyone sees the same goal. Progress counts from Monday to Sunday and starts fresh each week.",
                            "Alle sehen dasselbe Ziel. Gezählt wird von Montag bis Sonntag, jede Woche beginnt neu."))
                        .scaledFont(size: 15)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(ChallengeKind.all) { kind in
                        option(icon: kind.icon, title: kind.title, detail: kind.detail, selected: kind.id == current) {
                            pick(kind.id)
                        }
                    }
                    if current != nil {
                        option(icon: "xmark", title: tr("No challenge", "Keine Challenge"),
                               detail: tr("Just the rings, no shared goal.", "Nur die Ringe, kein gemeinsames Ziel."),
                               selected: false) {
                            pick(nil)
                        }
                    }
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.vertical, 20)
            }
            .background(AppBackground())
            .navigationTitle(tr("Weekly challenge", "Wochen-Challenge"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                        .foregroundStyle(Zen.ink)
                }
            }
        }
    }

    private func option(icon: String, title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(systemName: icon, tint: Zen.shu, size: 44, filled: selected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    Text(detail)
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Zen.shu)
                        .accessibilityHidden(true)
                }
            }
            .zenCard(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ kind: String?) {
        Task {
            await store.setChallenge(kind, for: circleId)
            if store.errorMessage == nil {
                Haptics.success()
                dismiss()
            }
        }
    }
}
