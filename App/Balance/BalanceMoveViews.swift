import AVFoundation
import SwiftUI
import UIKit

// MARK: - Section on the hub

struct MoveSection: View {
    @Environment(BalanceStore.self) private var balance
    let start: (Routine) -> Void

    var body: some View {
        let today: BalanceDay = balance.today
        let streak: Int = balance.moveStreak
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "figure.walk", title: tr("Move", "Bewegung"))

            HStack(spacing: 12) {
                StatTile(icon: "flame.fill", value: "\(today.moveMinutes)",
                         label: tr("Active minutes", "Aktive Minuten"), tint: Zen.matcha)
                StatTile(icon: "checkmark.circle.fill", value: "\(today.moveSessions)",
                         label: tr("Sessions today", "Einheiten heute"), tint: Zen.ai)
                StatTile(icon: "calendar", value: "\(streak)",
                         label: streak == 1 ? tr("Day in a row", "Tag am Stück") : tr("Days in a row", "Tage am Stück"),
                         tint: Zen.kin)
            }
            .zenCard()

            VStack(spacing: 10) {
                ForEach(Routine.all) { routine in
                    routineRow(routine)
                }
            }

            goalAndVoice

            BalanceNote(icon: "heart.text.square",
                        text: tr("Stop if anything hurts, and ask a doctor first if you are unsure whether exercise is right for you.",
                                 "Hör auf, wenn etwas wehtut, und frag vorher eine Ärztin oder einen Arzt, wenn du unsicher bist, ob Sport gerade gut für dich ist."))
        }
    }

    private func routineRow(_ routine: Routine) -> some View {
        let detail: String = tr("\(routine.nominalMinutes) min · \(routine.exerciseCount) exercises",
                                "\(routine.nominalMinutes) Min. · \(routine.exerciseCount) Übungen")
        return Button {
            Haptics.tap()
            start(routine)
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: routine.symbol, tint: routine.tint, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.title)
                        .scaledFont(size: 17, weight: .semibold, design: .rounded)
                        .foregroundStyle(Zen.ink)
                    Text(routine.blurb)
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .scaledFont(size: 12, weight: .semibold, design: .rounded)
                        .foregroundStyle(routine.tint)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(routine.tint, in: Circle())
            }
            .zenCard(padding: 16)
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("Starts the guided routine", "Startet die angeleitete Einheit"))
    }

    private var goalAndVoice: some View {
        let goal: Int = balance.settings.moveGoalMinutes
        let voice = Binding<Bool>(
            get: { balance.settings.voice },
            set: { balance.setVoice($0) }
        )
        return VStack(alignment: .leading, spacing: 14) {
            Text(tr("Daily movement goal", "Tagesziel Bewegung"))
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Zen.ink)
            HStack(spacing: 8) {
                ForEach(BalanceSettings.moveGoalChoices, id: \.self) { minutes in
                    Chip(title: tr("\(minutes) min", "\(minutes) Min."), selected: goal == minutes) {
                        balance.setMoveGoal(minutes)
                    }
                }
                Spacer(minLength: 0)
            }
            Divider().overlay(Zen.line)
            Toggle(isOn: voice) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Voice announcements", "Sprachansagen"))
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    Text(tr("Says each exercise out loud, so you can keep your eyes off the screen.",
                            "Sagt jede Übung an, damit dein Blick nicht am Bildschirm hängt."))
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Zen.matcha)
        }
        .zenCard()
    }
}

// MARK: - Player

/// Full-screen guide through one routine. The clock is derived from dates,
/// so pausing, skipping and a trip to the background never throw it off.
struct MovePlayerView: View {
    let routine: Routine
    @Environment(BalanceStore.self) private var balance
    @Environment(\.dismiss) private var dismiss
    @State private var clock: RoutineClock
    @State private var now = Date()
    @State private var voice = RoutineVoice()
    @State private var recorded = false
    @State private var finishedSeconds: Int?
    @State private var lastSecondLeft = -1
    @State private var lastElapsed: Double = 0

    init(routine: Routine) {
        self.routine = routine
        _clock = State(initialValue: RoutineClock(durations: routine.durations))
    }

    var body: some View {
        ZStack {
            AppBackground()
            if let finishedSeconds {
                done(seconds: finishedSeconds)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                session
                    .transition(.opacity)
            }
        }
        .task { await run() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            voice.stop()
            recordIfWorthIt()
        }
    }

    private var step: RoutineStep { routine.steps[min(clock.index, routine.steps.count - 1)] }

    // MARK: Session

    private var session: some View {
        let current: RoutineStep = step
        let secondsLeft: Int = Int(clock.remainingInStep(at: now).rounded(.up))
        let ringTint: Color = current.kind == .work ? routine.tint : (current.kind == .rest ? Zen.ai : Zen.kin)
        return VStack(spacing: 18) {
            topBar
            InkProgress(value: clock.totalProgress(at: now), color: routine.tint)
                .padding(.horizontal, Zen.gutter)
                .accessibilityMeter(tr("Routine", "Einheit"), value: clock.totalProgress(at: now).formatted(.percent.precision(.fractionLength(0))))

            Spacer(minLength: 0)

            Text(caption(for: current).uppercased(with: Loc.locale))
                .scaledFont(size: 13, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Zen.inkSoft)

            ZStack {
                ProgressRing(progress: clock.stepProgress(at: now), lineWidth: 16, tint: ringTint)
                    .animation(.linear(duration: 0.25), value: clock.stepProgress(at: now))
                VStack(spacing: 6) {
                    Image(systemName: current.kind == .rest ? "pause.circle" : current.exercise.symbol)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(ringTint)
                    Text("\(secondsLeft)")
                        .displayFont(64)
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: secondsLeft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 30)
            }
            .frame(width: 260, height: 260)
            .dynamicTypeSize(...denseTypeLimit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(current.title)
            .accessibilityValue(tr("\(secondsLeft) seconds left", "noch \(secondsLeft) Sekunden"))
            .accessibilityAddTraits(.updatesFrequently)

            VStack(spacing: 8) {
                Text(current.title)
                    .displayFont(30)
                    .foregroundStyle(Zen.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle(for: current))
                    .scaledFont(size: 16)
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Zen.gutter)
            .id(clock.index)
            .transition(.opacity)

            Spacer(minLength: 0)

            nextUp
                .padding(.horizontal, Zen.gutter)

            controls
                .padding(.horizontal, Zen.gutter)

            Text(tr("Stop if anything hurts.", "Hör auf, wenn etwas wehtut."))
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Zen.inkSoft)
                .padding(.bottom, 12)
        }
        .animation(.easeInOut(duration: 0.3), value: clock.index)
    }

    private var topBar: some View {
        let counter: String = tr("\(workNumber) of \(routine.exerciseCount)", "\(workNumber) von \(routine.exerciseCount)")
        return HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Zen.inkSoft)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(tr("Close", "Schließen"))
            Spacer()
            VStack(spacing: 2) {
                Text(routine.title)
                    .scaledFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(Zen.ink)
                Text(counter)
                    .scaledFont(size: 12, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer()
            Button {
                toggleVoice()
            } label: {
                Image(systemName: balance.settings.voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(balance.settings.voice ? Zen.shu : Zen.inkFaint)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(balance.settings.voice ? tr("Mute the voice", "Stimme stumm") : tr("Turn the voice on", "Stimme an"))
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var nextUp: some View {
        if let next = routine.nextWork(after: clock.index) {
            HStack(spacing: 12) {
                IconBadge(systemName: next.exercise.symbol, tint: routine.tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Next up", "Als Nächstes"))
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Zen.inkSoft)
                    Text(next.exercise.name)
                        .scaledFont(size: 16, weight: .semibold, design: .rounded)
                        .foregroundStyle(Zen.ink)
                }
                Spacer(minLength: 0)
                Text(tr("\(Int(next.seconds)) sec", "\(Int(next.seconds)) Sek."))
                    .scaledFont(size: 14, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(Zen.inkSoft)
            }
            .zenCard(padding: 14)
        } else {
            BalanceNote(icon: "flag.checkered", text: tr("Last one. Finish it gently.", "Die letzte. Bring sie ruhig zu Ende."))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                togglePause()
            } label: {
                Label(clock.isRunning ? tr("Pause", "Pause") : tr("Go on", "Weiter"),
                      systemImage: clock.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.primary)
            Button {
                skip()
            } label: {
                Label(tr("Skip", "Überspringen"), systemImage: "forward.fill")
            }
            .buttonStyle(InkButtonStyle(kind: .quiet, fullWidth: false))
        }
    }

    /// Number of the exercise in view; during a rest the one coming up.
    private var workNumber: Int {
        let upTo: Int = min(clock.index, routine.steps.count - 1)
        let done: Int = routine.steps[0...upTo].filter { $0.kind == .work }.count
        return step.kind == .work ? done : min(routine.exerciseCount, done + 1)
    }

    private func caption(for step: RoutineStep) -> String {
        switch step.kind {
        case .prepare: routine.title
        case .rest: tr("Breathe, shake it out", "Durchatmen, locker schütteln")
        case .work: tr("Exercise \(workNumber) of \(routine.exerciseCount)", "Übung \(workNumber) von \(routine.exerciseCount)")
        }
    }

    private func subtitle(for step: RoutineStep) -> String {
        switch step.kind {
        case .prepare: tr("First: \(step.exercise.name)", "Als Erstes: \(step.exercise.name)")
        case .rest: tr("Coming up: \(step.exercise.name)", "Gleich: \(step.exercise.name)")
        case .work:
            step.exercise.switchesSides
                ? step.exercise.howTo + " " + tr("Switch sides halfway.", "Nach der Hälfte Seite wechseln.")
                : step.exercise.howTo
        }
    }

    // MARK: Done

    private func done(seconds: Int) -> some View {
        let minutes: Int = max(1, Int((Double(seconds) / 60).rounded()))
        let sessions: Int = balance.today.moveSessions
        return VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Zen.matcha.opacity(0.14)).frame(width: 140, height: 140)
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Zen.matcha)
            }
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(tr("Well moved", "Gut bewegt"))
                    .displayFont(30)
                    .foregroundStyle(Zen.ink)
                Text(tr("\(minutes) active \(minutes == 1 ? "minute" : "minutes"). Session \(sessions) today.",
                        "\(minutes) aktive \(minutes == 1 ? "Minute" : "Minuten"). Heute Einheit Nummer \(sessions)."))
                    .scaledFont(size: 16)
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Zen.gutter)
            Spacer()
            Button(tr("Done", "Fertig")) { dismiss() }
                .buttonStyle(.primary)
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 24)
        }
    }

    // MARK: Flow

    /// Watches the clock five times a second. The drawing reads `now`; this
    /// loop only moves it along and fires the voice and the haptics.
    private func run() async {
        if !clock.isRunning && !clock.isFinished && finishedSeconds == nil {
            clock.start(at: Date())
            announce(step)
        }
        while !Task.isCancelled && finishedSeconds == nil {
            try? await Task.sleep(for: .milliseconds(200))
            tick()
        }
    }

    private func tick() {
        let date = Date()
        let changed: Bool = clock.sync(at: date)
        now = date
        if clock.isFinished {
            complete()
            return
        }
        if changed {
            lastElapsed = 0
            lastSecondLeft = -1
            stepHaptic()
            announce(step)
            return
        }
        guard clock.isRunning else { return }
        let elapsed: Double = clock.elapsedInStep(at: date)
        if step.kind == .work && step.exercise.switchesSides
            && RoutineClock.crossedHalf(stepSeconds: step.seconds, from: lastElapsed, to: elapsed) {
            Haptics.tap()
            speak(tr("Switch sides.", "Seite wechseln."))
        }
        lastElapsed = elapsed
        // A soft tick for each of the last three seconds.
        let left: Int = Int(clock.remainingInStep(at: date).rounded(.up))
        if left != lastSecondLeft {
            lastSecondLeft = left
            if (1...3).contains(left) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    private func togglePause() {
        Haptics.tap()
        let date = Date()
        if clock.isRunning {
            clock.pause(at: date)
            voice.stop()
        } else {
            clock.start(at: date)
        }
        now = date
    }

    private func skip() {
        Haptics.tap()
        let date = Date()
        clock.skip(at: date)
        now = date
        lastElapsed = 0
        lastSecondLeft = -1
        if clock.isFinished {
            complete()
        } else {
            announce(step)
        }
    }

    private func toggleVoice() {
        Haptics.tap()
        let on = !balance.settings.voice
        balance.setVoice(on)
        if !on { voice.stop() }
    }

    private func stepHaptic() {
        switch step.kind {
        case .work: Haptics.success()
        case .rest, .prepare: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func announce(_ step: RoutineStep) {
        let seconds = Int(step.seconds)
        switch step.kind {
        case .prepare:
            speak(tr("Get ready. First: \(step.exercise.name).", "Mach dich bereit. Als Erstes: \(step.exercise.name)."))
        case .rest:
            speak(tr("Rest. Next: \(step.exercise.name).", "Pause. Gleich: \(step.exercise.name)."))
        case .work:
            speak(tr("\(step.exercise.name). \(seconds) seconds.", "\(step.exercise.name). \(seconds) Sekunden."))
        }
    }

    private func speak(_ text: String) {
        guard balance.settings.voice else {
            // With the voice off, VoiceOver still hears each step.
            AccessibilityNotification.Announcement(text).post()
            return
        }
        voice.say(text)
    }

    private func complete() {
        guard finishedSeconds == nil else { return }
        let seconds = Int(clock.spent(at: now).rounded())
        recordIfWorthIt()
        Haptics.success()
        speak(tr("Well done. That was it.", "Gut gemacht. Das war's."))
        UIApplication.shared.isIdleTimerDisabled = false
        withAnimation(.easeInOut(duration: 0.4)) { finishedSeconds = seconds }
    }

    /// Counts once, and only with at least a minute of real movement, so an
    /// accidental start does not pad the stats.
    private func recordIfWorthIt() {
        guard !recorded else { return }
        let seconds = Int(clock.spent(at: Date()).rounded())
        guard seconds >= 60 || clock.isFinished else { return }
        recorded = true
        balance.recordMove(seconds: seconds)
    }
}

// MARK: - Voice

/// Speaks the announcements in the app language. The audio session ducks
/// other audio only while a line is spoken and hands it back afterwards.
@MainActor
final class RoutineVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var previous: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// `voice` and `pitch` let the companions sound like themselves; the
    /// routines use the plain voice of the app language.
    func say(_ text: String, voice: AVSpeechSynthesisVoice? = nil, pitch: Float = 1) {
        claimSession()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: Loc.isGerman ? "de-DE" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = pitch
        synthesizer.speak(utterance)
    }

    /// Silences the voice and gives the audio session back as it was.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        releaseSession(restore: true)
    }

    /// Ma's own ambient sound owns the session while it plays. The voice
    /// then only speaks over it and must never switch the session off.
    private var ambientPlaying: Bool { SoundEngine.shared.playing != .off }

    private func claimSession() {
        guard !ambientPlaying else { return }
        let session = AVAudioSession.sharedInstance()
        if previous == nil {
            previous = (session.category, session.mode, session.categoryOptions)
        }
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    private func releaseSession(restore: Bool) {
        guard !ambientPlaying else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if restore, let previous {
            try? session.setCategory(previous.category, mode: previous.mode, options: previous.options)
            self.previous = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Un-duck the music between lines, keep our category for the next.
            if !self.synthesizer.isSpeaking { self.releaseSession(restore: false) }
        }
    }
}
