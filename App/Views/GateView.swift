import FamilyControls
import SwiftUI

/// The pause between impulse and app: breathe, answer, then decide.
///
/// Deciding is the point. After the questions, "leave it" is offered as
/// prominently as "open", and choosing it is celebrated, not punished.
struct GateView: View {
    @Environment(AppModel.self) private var model
    let reason: GateReason

    private enum Stage { case breathe, quiz, decide, open, blocked }

    @State private var stage: Stage = .breathe
    @State private var session: QuizSession?
    @State private var inhale = false
    @State private var breaths = 0
    @State private var minutes = 5
    @State private var openUntil: Date?
    /// Read once when the gate opens, so the rules cannot shift under the
    /// person while they answer.
    @State private var policy = UnlockPolicy()
    /// End of the waiting period some boundaries ask for.
    @State private var waitUntil: Date?
    /// Ending a lockdown was asked for, but no topic is switched on.
    @State private var noQuestions = false

    private var pending: PendingUnlock? {
        if case .unlock(let pending) = reason { return pending }
        return nil
    }

    private var shortcutApp: GuardedApp? {
        if case .shortcut(let raw) = reason { return GuardedApp(rawValue: raw) ?? .any }
        return nil
    }

    private var isEndLockdown: Bool {
        if case .endLockdown = reason { return true }
        return false
    }

    /// Both ways in lead to the same decision: open for a while, or let it be.
    private var isUnlock: Bool { pending != nil || shortcutApp != nil }

    private var needed: Int {
        switch reason {
        case .unlock, .shortcut: return policy.questions
        case .endLockdown: return LockdownState.answersToEnd
        case .disableRule, .stopFocus, .practice: return 3
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                topBar
                switch stage {
                case .breathe: breathe
                case .quiz: quiz
                case .decide: decide
                case .open: opened
                case .blocked: blocked
                }
            }
        }
        .onAppear(perform: prepare)
    }

    private func prepare() {
        if let pending {
            policy = model.policy(for: pending)
        } else if let app = shortcutApp {
            policy = model.shortcutPolicy()
            if policy.lockdownUntil == nil, !policy.focusLocked || SharedStore.focusSettings.allowReelFreeWeb {
                policy.reelFreeWeb = ReelFreeWeb.url(forAppName: app == .any ? nil : app.displayName)
            }
        }
        minutes = policy.minutes
        if isUnlock && !policy.allowed {
            stage = .blocked
            return
        }
        if isEndLockdown && !model.isLockedDown {
            // Ran out while the gate was on its way: nothing left to earn.
            model.endLockdown()
            model.gate = nil
            return
        }
        if isUnlock && policy.waitSeconds > 0 {
            waitUntil = Date().addingTimeInterval(TimeInterval(policy.waitSeconds))
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Zen.inkSoft)
                    .frame(width: 40, height: 40)
                    .background(Zen.sand, in: Circle())
            }
            .accessibilityLabel(tr("Close", "Schließen"))
            if stage != .quiz && stage != .blocked {
                InkProgress(value: stageProgress)
                    .frame(maxWidth: 160)
            }
            Spacer()
        }
        .padding(.horizontal, Zen.gutter)
        .padding(.top, 8)
    }

    private var stageProgress: Double {
        switch stage {
        case .breathe: 0.15
        case .quiz: 0.5
        case .decide: 0.85
        case .open, .blocked: 1
        }
    }

    // MARK: Stages

    private var subject: some View {
        Group {
            if let token = pending?.application {
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 16, weight: .semibold))
            } else if let web = pending?.webDomain {
                Label(web)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 16, weight: .semibold))
            } else if let app = shortcutApp, app != .any {
                Text(app.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Zen.ink)
            } else {
                Text(subjectText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Zen.ink)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Zen.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Zen.line))
    }

    private var subjectText: String {
        switch reason {
        case .unlock(let pending): return pending.displayName ?? tr("A category", "Eine Kategorie")
        case .disableRule(let id):
            let name = model.rules.first { $0.id == id }?.name ?? ""
            return tr("Switch off \(name)", "\(name) ausschalten")
        case .stopFocus: return tr("End focus round", "Fokusrunde abbrechen")
        case .practice: return tr("Practice", "Übung")
        case .shortcut: return tr("Your app", "Deine App")
        case .endLockdown: return tr("End the lockdown early", "Sperre früher beenden")
        }
    }

    private var breathe: some View {
        VStack(spacing: 26) {
            Spacer()
            subject
            BreathingEnso(inhale: inhale, tint: Zen.shu)
                .frame(width: 220, height: 220)
            VStack(spacing: 8) {
                Text(breaths % 2 == 0 ? tr("Breathe in", "Atme ein") : tr("Breathe out", "Atme aus"))
                    .font(.display(28, weight: .semibold))
                    .foregroundStyle(Zen.ink)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.6), value: breaths)
                Text(breatheLine)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                if noQuestions {
                    Text(tr("Switch on at least one topic under Learn. Without questions the lockdown stays.", "Schalte unter Lernen mindestens ein Thema ein. Ohne Fragen bleibt die Sperre."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Zen.negative)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                breatheButtons(now: context.date)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .task {
            withAnimation(.easeInOut(duration: 4)) { inhale = true }
            while !Task.isCancelled && stage == .breathe {
                try? await Task.sleep(for: .seconds(4))
                breaths += 1
                withAnimation(.easeInOut(duration: 4)) { inhale.toggle() }
            }
        }
    }

    private var breatheLine: String {
        if isEndLockdown {
            return tr("You chose this lockdown for a reason. \(needed) right answers end it early.", "Du hast diese Sperre aus einem Grund gewählt. \(needed) richtige Antworten beenden sie früher.")
        }
        if isUnlock && policy.rising && policy.unlocksToday > 0 {
            return tr("Unlock number \(policy.unlocksToday + 1) today, so \(needed) questions this time.", "Freigabe Nummer \(policy.unlocksToday + 1) heute, darum diesmal \(needed) Fragen.")
        }
        return tr("For one breath, want nothing.", "Einen Atemzug lang nichts wollen.")
    }

    private func breatheButtons(now: Date) -> some View {
        let waitLeft = max(0, (waitUntil ?? now).timeIntervalSince(now))
        let ready = breaths >= 2 && waitLeft <= 0
        let title: String
        if waitLeft > 0 {
            let seconds = Int(waitLeft.rounded(.up))
            title = tr("Questions in \(seconds) s", "Fragen in \(seconds) s")
        } else {
            title = needed == 1 ? tr("To the question", "Zur Frage") : tr("To the \(needed) questions", "Zu den \(needed) Fragen")
        }
        return VStack(spacing: 12) {
            Button(title) { startQuiz() }
                .buttonStyle(.primary)
                .monospacedDigit()
                .opacity(ready ? 1 : 0.35)
                .disabled(!ready)
            if isUnlock {
                reelFreeButton
                Button(tr("I'll let it be", "Ich lass es gut sein")) { resist() }
                    .buttonStyle(.quiet)
            } else if isEndLockdown {
                Button(tr("Keep the lockdown", "Sperre behalten")) { close() }
                    .buttonStyle(.quiet)
            }
        }
    }

    private var quiz: some View {
        Group {
            if let session {
                QuizView(session: session) {
                    finishQuiz()
                }
            }
        }
    }

    private var decide: some View {
        VStack(spacing: 22) {
            Spacer()
            IconBadge(systemName: "hand.raised.fill", tint: Zen.shu, size: 64)
            Text(tr("You have earned it.\nDo you still want it?", "Du hast es dir verdient.\nWillst du es noch?"))
                .font(.display(28))
                .foregroundStyle(Zen.ink)
                .multilineTextAlignment(.center)
            subject
            if let session, !session.exercises.isEmpty {
                Text(tr("\(session.correct) right, \(session.wrong) missed", "\(session.correct) richtig, \(session.wrong) daneben"))
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            }
            if let note = budgetNote {
                Text(note)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Zen.kin)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            HStack(spacing: 8) {
                ForEach(minuteOptions, id: \.self) { value in
                    Chip(title: tr("\(value) min.", "\(value) Min."), selected: minutes == value) { minutes = value }
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Button(tr("Open for \(minutes) min.", "\(minutes) Min. öffnen")) { unlock() }
                    .buttonStyle(.primary)
                Button(tr("I'll leave it", "Ich lass es")) { resist() }
                    .buttonStyle(.matcha)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, Zen.gutter)
    }

    /// What this unlock does to the rest of the day, said before it happens.
    private var budgetNote: String? {
        var parts: [String] = []
        if let left = policy.unlocksLeft {
            let after = max(0, left - 1)
            parts.append(after == 0
                ? tr("This is your last unlock today.", "Das ist deine letzte Freigabe heute.")
                : tr("After this, \(after) \(after == 1 ? "unlock" : "unlocks") left today.", "Danach \(after == 1 ? "bleibt noch eine Freigabe" : "bleiben noch \(after) Freigaben") für heute."))
        }
        if policy.rising && policy.unlocksLeft != 1 {
            let next = min(BlockRule.maxQuestions, policy.questions + 1)
            parts.append(tr("The next one costs \(next) questions.", "Die nächste kostet \(next) Fragen."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var minuteOptions: [Int] {
        let base = policy.minutes
        return Array(Set([max(1, base / 2), base].filter { $0 > 0 })).sorted()
    }

    private var opened: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                ProgressRing(progress: 1, lineWidth: 12, tint: Zen.matcha)
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Zen.matcha)
            }
            .frame(width: 150, height: 150)
            Text(tr("Open until \(openUntil.map(BlockingFormat.time) ?? "")", "Offen bis \(openUntil.map(BlockingFormat.time) ?? "")"))
                .font(.display(26))
                .foregroundStyle(Zen.ink)
            Text(tr("After that the boundary closes again by itself. Just switch to the app now.", "Danach schließt sich die Grenze von selbst wieder. Wechsle jetzt einfach zur App."))
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            VStack(spacing: 12) {
                if let app = shortcutApp {
                    if let url = app.url {
                        Button(tr("Go to \(app.displayName)", "Zu \(app.displayName)")) {
                            UIApplication.shared.open(url)
                            close()
                        }
                        .buttonStyle(.ink)
                    } else {
                        appPicker
                    }
                } else if let name = pending?.displayName {
                    Button(tr("Go to \(name)", "Zu \(name)")) {
                        model.open(appNamed: name)
                        close()
                    }
                    .buttonStyle(.ink)
                }
                Button(tr("Close", "Schließen"), action: close)
                    .buttonStyle(.quiet)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    /// When one automation covers several apps, Ma does not know which one
    /// was opened. Offer the usual suspects instead.
    private var appPicker: some View {
        VStack(spacing: 10) {
            Text(tr("Back to", "Zurück zu"))
                .font(.system(size: 14))
                .foregroundStyle(Zen.inkSoft)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(GuardedApp.allCases.filter { $0 != .any }, id: \.self) { app in
                    Chip(title: app.displayName, selected: false) {
                        if let url = app.url { UIApplication.shared.open(url) }
                        close()
                    }
                }
            }
        }
    }

    // MARK: Blocked

    private var blocked: some View {
        VStack(spacing: 22) {
            Spacer()
            if let until = policy.lockdownUntil {
                lockdownClock(until: until)
            } else {
                Illustration(name: "IllustrationBlock", height: 170)
                    .padding(.horizontal, 40)
            }
            Text(blockedTitle)
                .font(.display(28))
                .foregroundStyle(Zen.ink)
                .multilineTextAlignment(.center)
            Text(blockedText)
                .font(.system(size: 16))
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            VStack(spacing: 12) {
                reelFreeButton
                Button(tr("Back to calm", "Zurück zur Ruhe")) { resist() }
                    .buttonStyle(.ink)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    /// During a lockdown the gate shows only this: how long is left.
    private func lockdownClock(until: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let started = SharedStore.lockdown?.startedAt ?? context.date
            let total = max(1, until.timeIntervalSince(started))
            let left = max(0, until.timeIntervalSince(context.date))
            ZStack {
                ProgressRing(progress: 1 - left / total, lineWidth: 12, tint: Zen.shu)
                VStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Zen.shu)
                    Text(BlockingFormat.clock(left))
                        .font(.display(30, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Zen.ink)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .frame(width: 200, height: 200)
        }
    }

    private var blockedTitle: String {
        if let until = policy.lockdownUntil {
            return tr("Locked until \(BlockingFormat.time(until))", "Gesperrt bis \(BlockingFormat.time(until))")
        }
        if policy.focusLocked { return tr("Focus is on", "Fokus läuft") }
        if policy.budgetSpent { return tr("No unlocks left today", "Keine Freigaben mehr für heute") }
        return tr("No way through", "Kein Ausweg")
    }

    private var blockedText: String {
        if policy.isLockdown {
            return tr("Nothing opens until then, not even with questions.", "Bis dahin öffnet sich nichts, auch nicht mit Fragen.")
        }
        if policy.focusLocked {
            return tr("During a focus round Ma opens nothing. The round ends by itself, and then everything is back.", "Während einer Fokusrunde öffnet Ma nichts. Die Runde endet von selbst, und dann ist alles wieder da.")
        }
        if policy.budgetSpent {
            let limit = policy.dailyLimit ?? 0
            return tr("You gave yourself \(limit) \(limit == 1 ? "unlock" : "unlocks") a day here, and they are used up. Tomorrow it opens again.", "Du hast dir hier \(limit) \(limit == 1 ? "Freigabe" : "Freigaben") am Tag gegeben, und die sind aufgebraucht. Morgen geht es wieder.")
        }
        return tr("You set this boundary with no way through. If you want to change that, you can under Boundaries.", "Diese Grenze hast du ohne Ausweg gesetzt. Wenn du das ändern willst, geht das unter Grenzen.")
    }

    // MARK: Flow

    private func startQuiz() {
        let session = QuizSession(mode: .gate(required: needed), store: model.decks)
        // No topics means no questions. Everywhere else that simply lets the
        // person through; a lockdown must not end for free that way.
        if isEndLockdown && session.exercises.isEmpty {
            noQuestions = true
            return
        }
        self.session = session
        withAnimation(.easeInOut) {
            stage = session.finished ? .decide : .quiz
        }
        if session.finished { finishQuiz() }
    }

    private func finishQuiz() {
        model.reload()
        switch reason {
        case .unlock, .shortcut:
            withAnimation(.easeInOut) { stage = .decide }
        case .disableRule, .stopFocus, .practice, .endLockdown:
            Haptics.success()
            model.gatePassed(reason)
            model.gate = nil
        }
    }

    private func unlock() {
        Haptics.success()
        openUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        if let pending {
            if model.grant(pending, minutes: minutes) {
                withAnimation(.easeInOut) { stage = .open }
            } else {
                // The day's budget or a lockdown closed the door meanwhile.
                policy = model.policy(for: pending)
                withAnimation(.easeInOut) { stage = .blocked }
            }
        } else if let app = shortcutApp {
            // With a known app, go straight back to it. Otherwise show the
            // open screen with the app picker.
            if app.url != nil {
                model.openShortcutPass(minutes: minutes, app: app)
                model.gate = nil
            } else {
                model.openShortcutPass(minutes: minutes, app: .any)
                withAnimation(.easeInOut) { stage = .open }
            }
        }
    }

    /// The website without Reels, in Safari. No questions: choosing the
    /// calmer version is the point.
    @ViewBuilder
    private var reelFreeButton: some View {
        if let url = policy.reelFreeWeb, policy.lockdownUntil == nil {
            Button {
                Haptics.success()
                model.openReelFree(url)
                model.gate = nil
            } label: {
                Label(tr("Open without Reels", "Ohne Reels öffnen"), systemImage: "safari")
            }
            .buttonStyle(.primary)
        }
    }

    private func resist() {
        Haptics.success()
        if let pending {
            model.resist(pending)
        } else if shortcutApp != nil {
            model.resistShortcut()
        }
        model.gate = nil
    }

    private func close() {
        if pending != nil && stage != .open {
            model.dismissPending()
        } else if shortcutApp != nil && stage != .open {
            model.dismissShortcut()
        }
        model.gate = nil
    }
}
