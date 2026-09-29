import FamilyControls
import SwiftUI

/// Pomodoro, drawn as an ensō that paints itself over the length of a round.
struct FocusView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    header
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ring(at: context.date)
                    }
                    .frame(width: 290, height: 290)
                    controls
                    footnote
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(WashiBackground())
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

    private var header: some View {
        VStack(spacing: 10) {
            Text(phase?.kanji ?? "静")
                .font(.kanji(40, bold: true))
                .foregroundStyle(phase == .focus ? Zen.shu : (phase == nil ? Zen.ink : Zen.matcha))
            Text(phase?.title ?? tr("Ready when you are", "Bereit, wenn du es bist"))
                .font(.mincho(26, weight: .semibold))
                .foregroundStyle(Zen.ink)
            roundStones
        }
        .frame(maxWidth: .infinity)
    }

    private var roundStones: some View {
        let total = max(1, model.focusSettings.roundsUntilLongBreak)
        let finished: Int = {
            guard let focus = model.focus else { return FocusEngine.upcomingRound - 1 }
            return focus.phase == .focus ? focus.round - 1 : focus.round
        }()
        return HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { index in
                Ellipse()
                    .fill(index < finished ? Zen.stone : Zen.line)
                    .frame(width: 16, height: 12)
            }
        }
        .accessibilityLabel(tr("\(finished) of \(total) rounds", "\(finished) von \(total) Runden"))
    }

    private func ring(at date: Date) -> some View {
        let focus = model.focus
        let duration = focus?.duration ?? TimeInterval(model.focusSettings.focusMinutes * 60)
        let elapsed = focus.map { max(0, date.timeIntervalSince($0.startedAt)) } ?? 0
        let remaining = max(0, duration - elapsed)
        let progress = focus == nil ? 0 : min(1, elapsed / max(1, duration))
        let color: Color = focus?.phase == .focus ? Zen.ink : Zen.matcha

        return ZStack {
            EnsoView(progress: 1, lineWidth: 18, color: Zen.ink.opacity(0.06))
            EnsoView(progress: progress, lineWidth: 18, color: color)
            VStack(spacing: 6) {
                Text(Self.clock(remaining))
                    .font(.mincho(54, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Zen.ink)
                    .contentTransition(.numericText(countsDown: true))
                if let focus {
                    Text(tr("until \(focus.endsAt.formatted(date: .omitted, time: .shortened))", "bis \(focus.endsAt.formatted(date: .omitted, time: .shortened))"))
                        .font(.system(size: 14))
                        .foregroundStyle(Zen.inkSoft)
                } else {
                    Text("\(model.focusSettings.focusMinutes) · \(model.focusSettings.shortBreakMinutes) · \(model.focusSettings.longBreakMinutes)")
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
                .buttonStyle(.shu)
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
                Text(count == 0
                     ? tr("Focus blocks nothing yet. Draw a boundary or pick your own focus list.", "Im Fokus ist noch nichts gesperrt. Leg eine Grenze an oder wähle eine eigene Fokus-Liste.")
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

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
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
                } header: {
                    Text(tr("What sleeps during focus", "Was im Fokus schläft"))
                } footer: {
                    Text(tr("Without an own list, a focus round blocks everything from every boundary, including switched-off ones.", "Ohne eigene Liste sperrt eine Fokusrunde alles aus allen Grenzen, auch aus ausgeschalteten."))
                }
            }
            .tint(Zen.shu)
            .scrollContentBackground(.hidden)
            .background(WashiBackground())
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
