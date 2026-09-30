import AVFoundation
import SwiftUI
import UIKit

// MARK: - Snapshot from the stores

extension CompanionSnapshot {
    @MainActor
    static func make(fitness: FitnessStore, day: DayStore, model: AppModel, now: Date = Date()) -> CompanionSnapshot {
        var s = CompanionSnapshot()
        let report: FitnessReport = fitness.report
        s.hour = Calendar.current.component(.hour, from: now)
        s.level = report.progress.level
        s.levelTitle = FitnessXP.title(report.progress.level)
        s.xp = report.xp
        s.xpToNext = report.progress.left
        s.hasGoal = fitness.goal != nil
        s.weekKcal = report.week.kcal
        s.weekTarget = Int((report.target ?? 0).rounded())
        s.remainingKcal = Int(report.remaining.rounded())
        s.weekDone = s.hasGoal && report.weekFraction >= 1
        if let next = report.plan.first {
            s.nextSession = "\(FitnessFormat.planDay(next.dayOffset, from: now)): \(FitnessFormat.duration(next.minutes)) \(next.kind.title), "
                + tr("about \(FitnessFormat.kcal(next.kcal))", "etwa \(FitnessFormat.kcal(next.kcal))")
            s.nextSessionToday = next.dayOffset == 0
        }
        s.quests = report.quests.map {
            CompanionSnapshot.Quest(title: $0.title, detail: $0.detail, progress: $0.progress,
                                    target: $0.target, reward: $0.reward, done: $0.done)
        }
        s.currentKg = report.currentKg
        s.goalKg = fitness.goal?.goalKg
        s.lostKg = report.lostKg
        s.kgLeft = report.kgLeft
        s.eta = report.eta.map { FitnessFormat.monthYear($0) }
        s.weeksInARow = report.weeksInARow
        if let last = fitness.workouts.first, let date = FitnessDate.date(last.date) {
            let days: Int = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                            to: Calendar.current.startOfDay(for: now)).day ?? 0
            s.daysSinceWorkout = days
            s.lastWorkout = "\(last.kind.title), \(FitnessFormat.duration(last.minutes)), \(FitnessFormat.kcal(last.calories)), "
                + (days == 0 ? tr("today", "heute") : days == 1 ? tr("yesterday", "gestern") : tr("\(days) days ago", "vor \(days) Tagen"))
        }
        if let latest = fitness.latestDay {
            s.steps = latest.day.steps
            s.stepGoal = latest.day.stepGoal
        }
        s.learningStreak = model.decks.currentStreak
        s.learnedToday = model.decks.learnedToday
        s.habitsDone = day.habitsDoneToday
        s.habitsTotal = day.habits.count
        let stats: DayStats = SharedStore.today()
        s.resistedToday = stats.resisted
        s.focusMinutesToday = stats.focusMinutes
        return s
    }
}

// MARK: - Portrait

/// The companion, still or breathing. The idle loop plays only in the
/// neutral mood and never with Reduce Motion; every other mood is a still
/// that fades in and back out.
struct CompanionPortrait: View {
    let companion: CompanionID
    var mood: CompanionMood = .neutral
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(companion.image(mood))
                .resizable()
                .scaledToFill()
                .id("\(companion.rawValue)-\(mood.rawValue)")
                .transition(.opacity)
            if animated && !reduceMotion && mood == .neutral, let url = Bundle.main.url(forResource: companion.loopName, withExtension: "mp4") {
                LoopingVideo(url: url)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: mood)
        .animation(.easeInOut(duration: 0.6), value: companion)
        .accessibilityHidden(true)
    }
}

/// A silent looping video. It has no sound track, so it never touches the
/// audio session or stops music that is playing.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func play(_ url: URL) {
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: item)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .clear
            self.player = player
            player.play()
        }

        func stop() {
            player?.pause()
            looper = nil
            player = nil
        }
    }
}

/// Round face crop for rows and cards.
struct CompanionAvatar: View {
    let companion: CompanionID
    var mood: CompanionMood = .neutral
    var size: CGFloat = 56

    var body: some View {
        Image(companion.image(mood))
            .resizable()
            .scaledToFill()
            // The face sits in the upper third of the portrait.
            .frame(width: size, height: size * 1.46, alignment: .top)
            .offset(y: size * 0.18)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(CompanionStyle.glow(), lineWidth: 1.5))
            .shadow(color: CompanionStyle.glowColor.opacity(0.5), radius: 8)
            .accessibilityHidden(true)
    }
}

enum CompanionStyle {
    static let glowColor = Color(light: 0x5B5FEF, dark: 0x8FB4FF)
    static func glow(_ opacity: Double = 1) -> LinearGradient {
        LinearGradient(colors: [Color(light: 0x5B5FEF, dark: 0xA3A1FF).opacity(opacity),
                                Color(light: 0x0EA5B7, dark: 0x7BD8FF).opacity(opacity)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let window = Color(light: 0xFFFFFF, dark: 0x0E1430)
}

// MARK: - Card on the Balance hub

struct CompanionCard: View {
    @Environment(CompanionStore.self) private var companions
    @Environment(FitnessStore.self) private var fitness
    @Environment(DayStore.self) private var day
    @Environment(AppModel.self) private var model

    var body: some View {
        let who: CompanionID = companions.companion
        let snapshot: CompanionSnapshot = CompanionSnapshot.make(fitness: fitness, day: day, model: model)
        let quest = CompanionScript.dailyQuest(snapshot)
        return NavigationLink {
            CompanionView()
        } label: {
            HStack(spacing: 14) {
                CompanionAvatar(companion: who, size: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(CompanionID.hasChosen ? who.name : tr("Your companion", "Dein Begleiter"))
                        .displayFont(18)
                        .foregroundStyle(Zen.ink)
                    if let quest {
                        Text(quest.title.uppercased(with: Loc.locale))
                            .scaledFont(size: 11, weight: .bold, design: .rounded)
                            .tracking(1)
                            .foregroundStyle(Zen.ai)
                        Text(quest.detail)
                            .scaledFont(size: 14)
                            .foregroundStyle(Zen.inkSoft)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(tr("Talk about your training, your quests and your day.",
                                "Sprich über dein Training, deine Quests und deinen Tag."))
                            .scaledFont(size: 14)
                            .foregroundStyle(Zen.inkSoft)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .foregroundStyle(Zen.shu)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(CompanionStyle.window.opacity(0.9), in: RoundedRectangle(cornerRadius: Zen.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Zen.radius, style: .continuous).strokeBorder(CompanionStyle.glow(0.7), lineWidth: 1))
            .shadow(color: CompanionStyle.glowColor.opacity(0.18), radius: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat

struct CompanionView: View {
    @Environment(CompanionStore.self) private var companions
    @Environment(FitnessStore.self) private var fitness
    @Environment(DayStore.self) private var day
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var picking = false
    @FocusState private var typing: Bool

    private var snapshot: CompanionSnapshot {
        CompanionSnapshot.make(fitness: fitness, day: day, model: model)
    }

    var body: some View {
        Group {
            if CompanionID.hasChosen && !picking {
                chat
            } else {
                CompanionPicker { id in
                    companions.choose(id)
                    picking = false
                    companions.open(snapshot)
                }
            }
        }
        .background(AppBackground())
        .navigationTitle(CompanionID.hasChosen && !picking ? companions.companion.name : tr("Choose a companion", "Wähle deinen Begleiter"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if CompanionID.hasChosen && !picking {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        companions.voiceOn.toggle()
                    } label: {
                        Image(systemName: companions.voiceOn ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .accessibilityLabel(companions.voiceOn ? tr("Voice on", "Stimme an") : tr("Voice off", "Stimme aus"))
                    Menu {
                        Button { picking = true } label: {
                            Label(tr("Change companion", "Begleiter wechseln"), systemImage: "person.2")
                        }
                        Button(role: .destructive) { companions.clear() } label: {
                            Label(tr("Clear chat", "Verlauf löschen"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            if CompanionID.hasChosen { companions.open(snapshot) }
        }
        .onDisappear { companions.stopVoice() }
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(companions.messages) { message in
                        MessageView(message: message, companion: companions.companion)
                            .id(message.id)
                    }
                    if companions.thinking && companions.messages.last?.role == .user {
                        TypingDots()
                            .id("typing")
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: companions.messages) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var header: some View {
        let who: CompanionID = companions.companion
        return VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                CompanionPortrait(companion: who, mood: companions.mood)
                    .frame(height: 340)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                VStack(spacing: 2) {
                    Text(who.name.uppercased())
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Zen.ink)
                        .shadow(color: CompanionStyle.glowColor.opacity(0.8), radius: 10)
                    Text(tr("Level \(fitness.report.progress.level) · \(FitnessXP.title(fitness.report.progress.level))",
                            "Level \(fitness.report.progress.level) · \(FitnessXP.title(fitness.report.progress.level))"))
                        .scaledFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundStyle(Zen.ai)
                }
                .padding(.bottom, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: Zen.radius, style: .continuous))
            if companions.usesModel {
                AIPrivacyLabel()
            } else {
                Text(tr("Without Apple Intelligence \(who.name) answers from a set of lines built on your numbers.",
                        "Ohne Apple Intelligence antwortet \(who.name) mit festen Sätzen, gebaut aus deinen Zahlen."))
                    .scaledFont(size: 12)
                    .foregroundStyle(Zen.inkFaint)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    private var suggestions: [String] {
        [tr("What should I train today?", "Was trainiere ich heute?"),
         tr("How am I doing?", "Wie stehe ich?"),
         tr("Motivate me", "Motivier mich"),
         tr("I don't feel like it", "Ich hab keine Lust"),
         tr("My quests", "Meine Quests"),
         tr("How is my weight?", "Wie läuft mein Gewicht?")]
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { text in
                        Button {
                            Haptics.tap()
                            submit(text)
                        } label: {
                            Text(text)
                                .scaledFont(size: 14, weight: .semibold, design: .rounded)
                                .foregroundStyle(Zen.ink)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 13)
                                .background(Zen.sand, in: Capsule())
                                .overlay(Capsule().strokeBorder(CompanionStyle.glow(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(companions.thinking)
                    }
                }
                .padding(.horizontal, Zen.gutter)
            }
            HStack(spacing: 10) {
                TextField(tr("Write to \(companions.companion.name)…", "Schreib \(companions.companion.name)…"), text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($typing)
                    .scaledFont(size: 16)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    .background(Zen.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Zen.line, lineWidth: 1))
                    .submitLabel(.send)
                    .onSubmit { submit(draft) }
                Button {
                    submit(draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 42, height: 42)
                        .background(Zen.accentGradient, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companions.thinking)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .accessibilityLabel(tr("Send", "Senden"))
            }
            .padding(.horizontal, Zen.gutter)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func submit(_ text: String) {
        let message: String = text
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        let current: CompanionSnapshot = self.snapshot
        Task { await companions.send(message, snapshot: current) }
    }
}

struct MessageView: View {
    let message: CompanionMessage
    let companion: CompanionID

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .scaledFont(size: 16)
                    .foregroundStyle(Color.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Zen.accentGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        case .companion:
            HStack(alignment: .top, spacing: 10) {
                CompanionAvatar(companion: companion, mood: message.mood, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(companion.name.uppercased())
                        .scaledFont(size: 11, weight: .heavy, design: .rounded)
                        .tracking(1.5)
                        .foregroundStyle(Zen.ai)
                    Text(message.text.isEmpty ? " " : message.text)
                        .scaledFont(size: 16)
                        .foregroundStyle(Zen.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(CompanionStyle.window.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CompanionStyle.glow(0.6), lineWidth: 1))
                .shadow(color: CompanionStyle.glowColor.opacity(0.15), radius: 10)
                Spacer(minLength: 24)
            }
            .accessibilityElement(children: .combine)
        case .quest:
            QuestWindow(title: message.title ?? tr("Quest", "Quest"), text: message.text, reward: message.reward)
        }
    }
}

/// The game-style window a new quest arrives in.
struct QuestWindow: View {
    let title: String
    let text: String
    let reward: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Zen.ai)
                Text(title.uppercased(with: Loc.locale))
                    .scaledFont(size: 13, weight: .heavy, design: .rounded)
                    .tracking(2)
                    .foregroundStyle(Zen.ink)
                Spacer()
                if let reward {
                    Text("+\(reward) XP")
                        .scaledFont(size: 12, weight: .bold, design: .rounded)
                        .foregroundStyle(Zen.kin)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 9)
                        .background(Zen.kin.opacity(0.14), in: Capsule())
                }
            }
            Rectangle()
                .fill(CompanionStyle.glow())
                .frame(height: 1)
                .opacity(0.7)
            Text(text)
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanionStyle.window.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CompanionStyle.glow(), lineWidth: 1.5))
        .shadow(color: CompanionStyle.glowColor.opacity(0.35), radius: 14)
        .accessibilityElement(children: .combine)
    }
}

struct TypingDots: View {
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Zen.ai)
                    .frame(width: 8, height: 8)
                    .opacity(phase == index ? 1 : 0.35)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(CompanionStyle.window.opacity(0.9), in: Capsule())
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                phase = (phase + 1) % 3
            }
        }
        .accessibilityLabel(tr("Thinking", "Denkt nach"))
    }
}

// MARK: - Picker

struct CompanionPicker: View {
    let choose: (CompanionID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("Who walks with you? Your companion knows your level, your quests and your week, and keeps you going. You can switch any time.",
                        "Wer begleitet dich? Dein Begleiter kennt dein Level, deine Quests und deine Woche und hält dich auf Kurs. Wechseln geht jederzeit."))
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    ForEach(CompanionID.allCases) { who in
                        Button {
                            Haptics.success()
                            choose(who)
                        } label: {
                            VStack(spacing: 0) {
                                Image(who.image(.neutral))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 250)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(who.name)
                                        .displayFont(20)
                                        .foregroundStyle(Zen.ink)
                                    Text(who.tagline)
                                        .scaledFont(size: 13)
                                        .foregroundStyle(Zen.inkSoft)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .background(CompanionStyle.window, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CompanionStyle.glow(0.7), lineWidth: 1))
                            .shadow(color: CompanionStyle.glowColor.opacity(0.25), radius: 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(who.name). \(who.tagline)")
                    }
                }
                AIPrivacyLabel()
            }
            .padding(.horizontal, Zen.gutter)
            .padding(.vertical, 12)
        }
    }
}
