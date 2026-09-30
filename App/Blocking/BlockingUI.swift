import FamilyControls
import ManagedSettings
import SwiftUI

// MARK: - Headings

/// Big plain title at the top of a blocking screen, with an optional line
/// under it. Kept here so these screens do not depend on other tabs' titles.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .displayFont(34)
                .foregroundStyle(Zen.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// A numbered instruction: a plain digit in an accent circle, then the text.
struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Zen.shu, in: Circle())
            Text(text)
                .scaledFont(size: 15)
                .foregroundStyle(Zen.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Section header inside a Form: a small accent icon and the title.
struct FormHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Zen.shu)
                .accessibilityHidden(true)
            Text(title)
        }
    }
}

/// A card that is a button: icon, title, one line, chevron.
struct LinkCard: View {
    let icon: String
    var tint: Color = Zen.shu
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Zen.ink)
                Text(subtitle)
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Zen.inkFaint)
                .accessibilityHidden(true)
        }
        .zenCard()
    }
}

enum BlockingFormat {
    /// "1 h 20 min." or "25 min.", rounded up so it never reads zero while
    /// something is still running.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tr("\(minutes) min.", "\(minutes) Min.") }
        if rest == 0 { return tr("\(hours) h", "\(hours) Std.") }
        return tr("\(hours) h \(rest) min.", "\(hours) Std. \(rest) Min.")
    }

    /// Countdown clock, with hours once they matter.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Lockdown

/// "Lock everything now". Idle it offers the durations; running it shows
/// the time left and the one hard way out.
struct LockdownCard: View {
    @Environment(AppModel.self) private var model
    @State private var option: LockdownOption = .oneHour
    @State private var confirm = false

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        Group {
            if let until = model.lockdownUntil {
                running(until: until)
            } else {
                idle
            }
        }
        .zenCard()
    }

    /// How many items a lockdown would cover right now.
    private var coverage: Int {
        let probe = LockdownState(startedAt: Date(), until: Date())
        return ShieldEngine.lockdownSelection(probe, settings: model.focusSettings, rules: model.rules).count
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: "lock.fill", tint: Zen.shu, filled: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Lock everything now", "Jetzt alles sperren"))
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Zen.ink)
                    Text(BuildFlavor.screenTimeAvailable
                         ? tr("Every app from your boundaries and the focus list. No questions, no way through.", "Alle Apps aus deinen Grenzen und der Fokus-Liste. Keine Fragen, kein Ausweg.")
                         : tr("The Shortcuts gate lets nothing through. No questions, no pass.", "Die Kurzbefehle-Schranke lässt nichts durch. Keine Fragen, keine Freigabe."))
                        .scaledFont(size: 14)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(LockdownOption.allCases) { choice in
                    Chip(title: shortTitle(choice), selected: option == choice) { option = choice }
                }
            }
            if BuildFlavor.screenTimeAvailable && coverage == 0 {
                Text(tr("Nothing to lock yet. Add apps to a boundary first.", "Noch nichts zum Sperren da. Leg zuerst Apps in eine Grenze."))
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.kin)
            }
            Button(buttonTitle) { confirm = true }
                .buttonStyle(.primary)
                .disabled(BuildFlavor.screenTimeAvailable && coverage == 0)
                .opacity(BuildFlavor.screenTimeAvailable && coverage == 0 ? 0.4 : 1)
        }
        .confirmationDialog(confirmTitle, isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("Lock now", "Jetzt sperren"), role: .destructive) {
                Haptics.success()
                model.startLockdown(minutes: option.minutes())
            }
        } message: {
            Text(tr("Until then nothing opens, and boundaries cannot be switched off. Ending early costs \(LockdownState.answersToEnd) right answers.", "Bis dahin öffnet sich nichts, und Grenzen lassen sich nicht ausschalten. Früher aufhören kostet \(LockdownState.answersToEnd) richtige Antworten."))
        }
    }

    private func running(until: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let started = SharedStore.lockdown?.startedAt ?? context.date
            let total = max(1, until.timeIntervalSince(started))
            let left = max(0, until.timeIntervalSince(context.date))
            let progress = 1 - left / total
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        ProgressRing(progress: progress, lineWidth: 8, tint: Zen.shu)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Zen.shu)
                    }
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Locked until \(BlockingFormat.time(until))", "Gesperrt bis \(BlockingFormat.time(until))"))
                            .displayFont(20)
                            .foregroundStyle(Zen.ink)
                        Text(left > 0 ? tr("\(BlockingFormat.duration(left)) left", "Noch \(BlockingFormat.duration(left))") : tr("Time is up", "Die Zeit ist um"))
                            .scaledFont(size: 15, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(Zen.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                Text(tr("Nothing opens until then, and boundaries stay on.", "Bis dahin öffnet sich nichts, und die Grenzen bleiben an."))
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if left > 0 {
                    Button(tr("End early with \(LockdownState.answersToEnd) answers", "Mit \(LockdownState.answersToEnd) Antworten früher beenden")) {
                        model.endLockdown()
                    }
                    .buttonStyle(.quiet)
                } else {
                    Button(tr("Lift the lockdown", "Sperre aufheben")) {
                        Haptics.success()
                        model.endLockdown()
                    }
                    .buttonStyle(.primary)
                }
            }
        }
    }

    private func shortTitle(_ choice: LockdownOption) -> String {
        switch choice {
        case .halfHour: tr("30 min.", "30 Min.")
        case .oneHour: tr("1 h", "1 Std.")
        case .twoHours: tr("2 h", "2 Std.")
        case .fourHours: tr("4 h", "4 Std.")
        case .untilMorning: tr("Until morning", "Bis morgen")
        }
    }

    private var buttonTitle: String {
        option == .untilMorning
            ? tr("Lock until tomorrow morning", "Bis morgen früh sperren")
            : tr("Lock for \(option.title)", "Für \(option.title) sperren")
    }

    private var confirmTitle: String {
        let end = Date().addingTimeInterval(TimeInterval(option.minutes() * 60))
        return tr("Lock everything until \(BlockingFormat.time(end))?", "Alles bis \(BlockingFormat.time(end)) sperren?")
    }
}

// MARK: - Unlocks

/// One open unlock with a button to close it early.
struct OpenGrantRow: View {
    let grant: UnlockGrant
    let revoke: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let token = grant.applications.first {
                Label(token).labelStyle(.iconOnly).frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            } else {
                IconBadge(systemName: "lock.open.fill", tint: Zen.matcha, size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let token = grant.applications.first {
                    Label(token).labelStyle(.titleOnly).scaledFont(size: 16, weight: .semibold)
                } else if let web = grant.webDomains.first {
                    Label(web).labelStyle(.titleOnly).scaledFont(size: 16, weight: .semibold)
                } else {
                    Text(tr("Unlock", "Freigabe")).scaledFont(size: 16, weight: .semibold)
                }
                Text(tr("open until \(BlockingFormat.time(grant.expiresAt))", "offen bis \(BlockingFormat.time(grant.expiresAt))"))
                    .scaledFont(size: 13)
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer()
            Button(tr("Lock", "Sperren"), action: revoke)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Zen.shu)
        }
    }
}

// MARK: - Templates

/// First step of a new boundary: pick a starting point, then the apps.
struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let isFirst: Bool
    let choose: (BlockRule) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Start from a template. You pick the apps next, and can change everything later.", "Fang mit einer Vorlage an. Die Apps wählst du gleich danach, ändern kannst du alles später."))
                        .scaledFont(size: 15)
                        .foregroundStyle(Zen.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    ForEach(RuleTemplate.allCases) { template in
                        Button {
                            Haptics.tap()
                            choose(template.makeRule())
                        } label: {
                            templateRow(template)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        Haptics.tap()
                        var rule = BlockRule()
                        rule.name = isFirst ? tr("Social media", "Soziale Medien") : tr("New boundary", "Neue Grenze")
                        choose(rule)
                    } label: {
                        Label(tr("Start empty", "Leer beginnen"), systemImage: "plus")
                    }
                    .buttonStyle(.quiet)
                    .padding(.top, 4)
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 30)
            }
            .background(AppBackground())
            .navigationTitle(tr("New boundary", "Neue Grenze"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Abbrechen")) { dismiss() }
                }
            }
        }
    }

    private func templateRow(_ template: RuleTemplate) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: template.icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Zen.ink)
                Text(template.summary)
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Zen.shu)
                Text(template.blurb)
                    .scaledFont(size: 14)
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Zen.inkFaint)
                .accessibilityHidden(true)
        }
        .zenCard()
    }
}
