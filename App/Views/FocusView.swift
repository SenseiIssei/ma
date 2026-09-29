import FamilyControls
import SwiftUI

/// Pomodoro with a glowing ring that fills over the length of a round, plus
/// calm sounds and music shortcuts for the time in between.
struct FocusView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var sound: SoundEngine { SoundEngine.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ScreenHeader(title: tr("Focus", "Fokus"))
                    if phase == nil {
                        Illustration(name: "IllustrationFocus", height: 160)
                    }
                    header
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ring(at: context.date)
                    }
                    .frame(width: 280, height: 280)
                    .padding(.vertical, 6)
                    controls
                    soundCard
                    MusicCard()
                    footnote
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(AppBackground())
            .onChange(of: focusKey) { old, new in
                focusChanged(from: old, to: new)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(Zen.ink)
                    }
                    .accessibilityLabel(tr("Focus settings", "Fokus-Einstellungen"))
                }
            }
            .sheet(isPresented: $showSettings) {
                FocusSettingsView()
            }
            .onReceive(ticker) { _ in model.tick() }
        }
    }

    // MARK: Parts

    private var phase: FocusPhase? { model.focus?.phase }

    private var tint: Color {
        switch phase {
        case .focus, .none: Zen.shu
        case .shortBreak, .longBreak: Zen.matcha
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Text(phase?.title ?? tr("Ready when you are", "Bereit, wenn du es bist"))
                    .font(.display(24))
                    .foregroundStyle(Zen.ink)
            }
            roundDots
        }
        .frame(maxWidth: .infinity)
    }

    private var phaseIcon: String {
        switch phase {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        case .none: "circle.dashed"
        }
    }

    private var roundDots: some View {
        let total = max(1, model.focusSettings.roundsUntilLongBreak)
        let finished: Int = {
            guard let focus = model.focus else { return FocusEngine.upcomingRound - 1 }
            return focus.phase == .focus ? focus.round - 1 : focus.round
        }()
        let current: Int? = model.focus?.phase == .focus ? model.focus?.round : nil
        return HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                let done = index < finished
                let running = current == index + 1
                Circle()
                    .fill(done ? tint : (running ? tint.opacity(0.35) : Zen.line))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("\(finished) of \(total) rounds", "\(finished) von \(total) Runden"))
    }

    private func ring(at date: Date) -> some View {
        let focus = model.focus
        let duration = focus?.duration ?? TimeInterval(model.focusSettings.focusMinutes * 60)
        let elapsed = focus.map { max(0, date.timeIntervalSince($0.startedAt)) } ?? 0
        let remaining = max(0, duration - elapsed)
        let progress = focus == nil ? 0 : min(1, elapsed / max(1, duration))
        let running: Bool = focus != nil

        return ZStack {
            GlowRing(progress: progress, tint: tint, running: running)
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 6) {
                Text(Self.clock(remaining))
                    .font(.display(66, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(color: tint.opacity(running ? 0.35 : 0), radius: 12)
                if let focus {
                    Text(tr("until \(focus.endsAt.formatted(date: .omitted, time: .shortened))", "bis \(focus.endsAt.formatted(date: .omitted, time: .shortened))"))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                } else {
                    Text(tr("\(model.focusSettings.focusMinutes) min. focus, \(model.focusSettings.shortBreakMinutes) min. break", "\(model.focusSettings.focusMinutes) Min. Fokus, \(model.focusSettings.shortBreakMinutes) Min. Pause"))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            switch phase {
            case .none:
                Button(tr("Start focus", "Fokus beginnen")) {
                    Haptics.success()
                    model.startFocus()
                }
                .buttonStyle(.primary)
                Text(tr("Round \(FocusEngine.upcomingRound) of \(model.focusSettings.roundsUntilLongBreak)", "Runde \(FocusEngine.upcomingRound) von \(model.focusSettings.roundsUntilLongBreak)"))
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            case .focus:
                Button(tr("End round", "Runde beenden")) { model.requestStopFocus() }
                    .buttonStyle(.quiet)
                Text(tr("Put the phone down. Ma keeps watch.", "Leg das Handy weg. Ma passt auf."))
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            case .shortBreak, .longBreak:
                Button(tr("Skip break", "Pause überspringen")) {
                    Haptics.tap()
                    model.skipBreak()
                }
                .buttonStyle(.ink)
                Button(tr("Stop for today", "Für heute aufhören")) { model.stopFocus() }
                    .buttonStyle(.quiet)
            }
        }
    }

    private var footnote: some View {
        let count = ShieldEngine.focusSelection(settings: model.focusSettings, rules: model.rules).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: model.focusSettings.strict ? "lock.fill" : "lock.open")
                    .foregroundStyle(model.focusSettings.strict ? Zen.shu : Zen.inkSoft)
                Text(!BuildFlavor.screenTimeAvailable
                     ? (model.focusSettings.strict
                        ? tr("During focus the Shortcuts gate lets nothing through.", "Im Fokus lässt die Kurzbefehle-Schranke nichts durch.")
                        : tr("During focus the Shortcuts gate still asks its questions.", "Im Fokus stellt die Kurzbefehle-Schranke weiter ihre Fragen."))
                     : count == 0
                     ? tr("Focus blocks nothing yet. Add a boundary or pick your own focus list.", "Im Fokus ist noch nichts gesperrt. Leg eine Grenze an oder wähle eine eigene Fokus-Liste.")
                     : model.focusSettings.strict
                        ? tr("Blocked during focus: \(count) \(count == 1 ? "item" : "items"), no way through.", "Im Fokus gesperrt: \(count) \(count == 1 ? "Eintrag" : "Einträge"), ohne Ausweg.")
                        : tr("Blocked during focus: \(count) \(count == 1 ? "item" : "items"), questions allowed.", "Im Fokus gesperrt: \(count) \(count == 1 ? "Eintrag" : "Einträge"), Fragen erlaubt."))
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            }
            Text(tr("\(model.today.pomodoros) rounds and \(model.today.focusMinutes) minutes today.", "\(model.today.pomodoros) Runden und \(model.today.focusMinutes) Minuten heute."))
                .font(.system(size: 13))
                .foregroundStyle(Zen.inkFaint)
        }
        .zenCard()
    }

    // MARK: Sound

    private var soundCard: some View {
        let engine = sound
        let during = Binding<Bool>(
            get: { engine.playsDuringFocus },
            set: { engine.playsDuringFocus = $0 }
        )
        // A sound picked mid round ends with that round.
        let roundEnd: Date? = model.focus?.phase == .focus ? model.focus?.endsAt : nil
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "waveform", title: tr("Sound", "Klang"))
            VStack(alignment: .leading, spacing: 14) {
                SoundPicker(scope: .focus, until: roundEnd, showsSleepTimer: true)
                Divider().overlay(Zen.line)
                Toggle(isOn: during) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Play sound during focus", "Klang im Fokus abspielen"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Zen.ink)
                        Text(tr("Starts with each round and fades out when it ends.", "Beginnt mit jeder Runde und klingt mit ihr aus."))
                            .font(.system(size: 13))
                            .foregroundStyle(Zen.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Zen.shu)
            }
            .zenCard()
        }
    }

    /// Identity and phase of the running session: enough to tell a new round
    /// from a round that ended.
    private var focusKey: FocusSoundKey {
        FocusSoundKey(id: model.focus?.id, phase: model.focus?.phase)
    }

    /// A new focus round starts the chosen sound (when the user asked for
    /// that) or ties a sound that already plays to the round. When the round
    /// ends or is stopped, the focus sound fades out. The engine also keeps
    /// its own deadline, so this holds with the screen locked.
    private func focusChanged(from old: FocusSoundKey, to new: FocusSoundKey) {
        let wasFocus: Bool = old.phase == .focus
        let isFocus: Bool = new.phase == .focus
        if isFocus && (!wasFocus || old.id != new.id) {
            let endsAt: Date? = model.focus?.endsAt
            let chosen: AmbientSound = sound.sound(for: .focus)
            if sound.isPlaying(in: .focus) {
                sound.bind(until: endsAt)
            } else if sound.playsDuringFocus && chosen != .off && sound.playing == .off {
                sound.play(chosen, scope: .focus, until: endsAt)
            }
        } else if wasFocus && !isFocus {
            sound.stop(scope: .focus)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct FocusSoundKey: Equatable {
    var id: UUID?
    var phase: FocusPhase?
}

/// The focus ring. A blurred copy of the arc under the real one gives it a
/// soft glow against the night background, and while a round runs the glow
/// breathes slowly, so the screen feels alive without asking for attention.
private struct GlowRing: View {
    var progress: Double
    var tint: Color
    var running: Bool
    var lineWidth: CGFloat = 16

    var body: some View {
        Group {
            if running {
                PhaseAnimator([0.0, 1.0]) { pulse in
                    rings(pulse: pulse)
                } animation: { _ in
                    .easeInOut(duration: 2.6)
                }
            } else {
                // Idle: no animator at all, so nothing ticks while nothing runs.
                rings(pulse: 0)
            }
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }

    private func rings(pulse: Double) -> some View {
        let clamped: Double = min(1, max(0, progress))
        let glowOpacity: Double = 0.5 + 0.4 * pulse
        return ZStack {
            Circle()
                .stroke(tint.opacity(running ? 0.10 : 0.16), lineWidth: lineWidth)
                .blur(radius: 10)
            Circle()
                .stroke(Zen.sand.opacity(0.85), lineWidth: lineWidth)
            RingArc(progress: clamped, tint: tint, lineWidth: lineWidth)
                .blur(radius: 12)
                .opacity(glowOpacity)
            RingArc(progress: clamped, tint: tint, lineWidth: lineWidth)
        }
        // Behind the ring and outside its frame, so it never shifts the layout.
        .background { halo(pulse: pulse) }
    }

    private func halo(pulse: Double) -> some View {
        let strength: Double = running ? 0.20 + 0.10 * pulse : 0.12
        let gradient = RadialGradient(
            colors: [tint.opacity(strength), .clear],
            center: .center,
            startRadius: 60,
            endRadius: 200
        )
        return Circle()
            .fill(gradient)
            .frame(width: 380, height: 380)
            .scaleEffect(1 + 0.04 * pulse)
            .allowsHitTesting(false)
    }
}

/// The filled part of the ring: a gradient along the arc, round caps.
private struct RingArc: View, Animatable {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let sweep: Double = max(progress, 0.001) * 360
        let gradient = AngularGradient(
            colors: [tint.opacity(0.55), tint],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(sweep)
        )
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        return Circle()
            .trim(from: 0, to: progress)
            .stroke(gradient, style: style)
            .rotationEffect(.degrees(-90))
            .opacity(progress > 0 ? 1 : 0)
    }
}

struct FocusSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = FocusSettings()
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    minuteStepper(tr("Focus", "Fokus"), value: $settings.focusMinutes, range: 5...90, step: 5)
                    minuteStepper(tr("Short break", "Kurze Pause"), value: $settings.shortBreakMinutes, range: 1...30, step: 1)
                    minuteStepper(tr("Long break", "Lange Pause"), value: $settings.longBreakMinutes, range: 5...60, step: 5)
                    Stepper(value: $settings.roundsUntilLongBreak, in: 2...8) {
                        HStack {
                            Text(tr("Rounds until the long break", "Runden bis zur langen Pause"))
                            Spacer()
                            Text("\(settings.roundsUntilLongBreak)").foregroundStyle(Zen.inkSoft).monospacedDigit()
                        }
                    }
                    Toggle(tr("Carry on automatically after a break", "Nach der Pause automatisch weiter"), isOn: $settings.autoStartFocus)
                } header: {
                    Text(tr("Rhythm", "Rhythmus"))
                } footer: {
                    Text(tr("The classic is 25 minutes of focus, 5 minutes of break and a long break after four rounds.", "Klassisch sind 25 Minuten Fokus, 5 Minuten Pause und nach vier Runden eine lange Pause."))
                }

                Section {
                    Toggle(tr("Strict: no questions during focus", "Streng: keine Fragen im Fokus"), isOn: $settings.strict)
                    Toggle(tr("Allow the web version without Reels", "Web-Version ohne Reels erlauben"), isOn: $settings.allowReelFreeWeb)
                    if BuildFlavor.screenTimeAvailable {
                        focusListRows
                    }
                } header: {
                    Text(tr("What sleeps during focus", "Was im Fokus schläft"))
                } footer: {
                    Text((BuildFlavor.screenTimeAvailable
                          ? tr("Without an own list, a focus round blocks everything from every boundary, including switched-off ones.", "Ohne eigene Liste sperrt eine Fokusrunde alles aus allen Grenzen, auch aus ausgeschalteten.")
                          : tr("Strict focus makes the Shortcuts gate show only the time left.", "Strenger Fokus lässt die Kurzbefehle-Schranke nur die Restzeit zeigen."))
                         + " " + tr("With the web version allowed, tapping Instagram, YouTube, X, LinkedIn or Facebook during focus offers the website in Safari, where Ma Filter hides Reels, Shorts and feeds.",
                                    "Ist die Web-Version erlaubt, bietet ein Tipp auf Instagram, YouTube, X, LinkedIn oder Facebook im Fokus die Website in Safari an. Dort blendet Ma Filter Reels, Shorts und Feeds aus."))
                }
            }
            .tint(Zen.shu)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(tr("Focus", "Fokus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Sichern")) {
                        model.focusSettings = settings
                        model.saveFocusSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $settings.selection)
            .onAppear { settings = model.focusSettings }
        }
    }

    @ViewBuilder
    private var focusListRows: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Text(tr("Own focus list", "Eigene Fokus-Liste"))
                    .foregroundStyle(Zen.ink)
                Spacer()
                Text(ownCount == 0 ? tr("all boundaries", "alle Grenzen") : "\(ownCount)")
                    .foregroundStyle(Zen.inkSoft)
            }
        }
        if ownCount > 0 {
            Button(tr("Use all boundaries again", "Wieder alle Grenzen nehmen")) {
                settings.selection = FamilyActivitySelection()
            }
        }
    }

    private var ownCount: Int {
        settings.selection.applicationTokens.count + settings.selection.categoryTokens.count + settings.selection.webDomainTokens.count
    }

    private func minuteStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(tr("\(value.wrappedValue) min.", "\(value.wrappedValue) Min.")).foregroundStyle(Zen.inkSoft).monospacedDigit()
            }
        }
    }
}
