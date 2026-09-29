import FamilyControls
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var lesson: QuizSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    garden
                    stats
                    if !model.grants.isEmpty { openNow }
                    boundaries
                    actions
                    weekStrip
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 40)
            }
            .background(WashiBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Zen.ink)
                    }
                    .accessibilityLabel(tr("Settings", "Einstellungen"))
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(item: $lesson) { session in
                LessonScreen(session: session) { lesson = nil }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(KanjiDate.today())
                .font(.kanji(15, bold: true))
                .foregroundStyle(Zen.shu)
                .tracking(3)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Loc.locale)))
                .font(.mincho(32, weight: .semibold))
                .foregroundStyle(Zen.ink)
            Text(ZenLines.today(ZenLines.home))
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var garden: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZenGarden(stones: model.today.pomodoros, pebbles: model.today.resisted, mossDays: min(model.decks.currentStreak, 8))
                .frame(height: 200)
                .overlay(alignment: .topTrailing) {
                    if model.decks.currentStreak > 0 {
                        HStack(spacing: 6) {
                            Hanko(text: "連", size: 28)
                            Text(tr("\(model.decks.currentStreak) \(model.decks.currentStreak == 1 ? "day" : "days")", "\(model.decks.currentStreak) \(model.decks.currentStreak == 1 ? "Tag" : "Tage")"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Zen.ink)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                    }
                }
            Text(tr("Every stone a focus round, every pebble a moment you resisted. Moss grows with your learning streak.", "Jeder Stein eine Fokusrunde, jeder Kiesel ein Moment, in dem du widerstanden hast. Moos wächst mit deiner Lernserie."))
                .font(.system(size: 13))
                .foregroundStyle(Zen.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatStone(kanji: "抗", value: "\(model.today.resisted)", label: tr("resisted", "widerstanden"))
            StatStone(kanji: "学", value: "\(model.today.correct)", label: tr("answers right", "Fragen richtig"))
            StatStone(kanji: "集", value: "\(model.today.focusMinutes)", label: tr("min. focus", "Min. Fokus"))
            StatStone(kanji: "守", value: "\(model.today.shieldsSeen)", label: tr("stopped", "aufgehalten"))
        }
        .zenCard()
    }

    private var openNow: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kanji: "開", title: tr("Open right now", "Gerade offen"))
            VStack(spacing: 10) {
                ForEach(model.grants) { grant in
                    GrantRow(grant: grant) { model.revoke(grant) }
                }
            }
            .zenCard()
        }
    }

    private var boundaries: some View {
        let active = model.rules.filter { model.isShielding($0) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kanji: "結", title: tr("Boundaries", "Grenzen")) {
                Button(tr("All", "Alle")) { model.tab = .rules }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Zen.shu)
            }
            HStack(spacing: 14) {
                EnsoView(progress: model.rules.isEmpty ? 0.05 : Double(active.count) / Double(max(1, model.rules.count)), lineWidth: 6, color: Zen.ink)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    if model.authorization != .approved {
                        Text(tr("Screen Time not allowed", "Bildschirmzeit nicht erlaubt"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Zen.shu)
                        Text(BuildFlavor.screenTimeAvailable
                             ? tr("Without this permission Ma cannot block anything.", "Ohne diese Erlaubnis kann Ma nichts sperren.")
                             : BuildFlavor.previewNote)
                            .font(.system(size: 14))
                            .foregroundStyle(Zen.inkSoft)
                    } else if model.rules.isEmpty {
                        Text(tr("No boundary yet", "Noch keine Grenze"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Zen.ink)
                        Text(tr("Under Boundaries, choose what pulls at you too often.", "Leg unter Grenzen fest, was dich zu oft zieht."))
                            .font(.system(size: 14))
                            .foregroundStyle(Zen.inkSoft)
                    } else {
                        Text(tr("\(active.count) of \(model.rules.count) on watch", "\(active.count) von \(model.rules.count) wachen gerade"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Zen.ink)
                        Text(active.isEmpty ? tr("Everything is open right now.", "Gerade ist alles offen.") : active.map(\.name).joined(separator: ", "))
                            .font(.system(size: 14))
                            .foregroundStyle(Zen.inkSoft)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .zenCard()
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kanji: "道", title: tr("Now", "Jetzt"))
            HStack(spacing: 12) {
                ActionTile(kanji: "集", title: tr("Focus", "Fokus"), subtitle: model.focus == nil ? tr("\(model.focusSettings.focusMinutes) minutes", "\(model.focusSettings.focusMinutes) Minuten") : tr("running", "läuft")) {
                    if model.focus == nil { model.startFocus() }
                    model.tab = .focus
                }
                ActionTile(kanji: "学", title: tr("Lesson", "Lektion"), subtitle: tr("8 exercises", "8 Übungen")) {
                    lesson = QuizSession(mode: .lesson(count: 8), store: model.decks)
                }
            }
        }
    }

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(kanji: "週", title: tr("This week", "Diese Woche"))
            HStack(alignment: .bottom, spacing: 10) {
                let peak = max(1, model.week.map { $0.resisted + $0.correct }.max() ?? 1)
                ForEach(Array(model.week.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 6) {
                        let value = day.resisted + day.correct
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(index == model.week.count - 1 ? Zen.shu : Zen.ink.opacity(0.75))
                            .frame(height: max(4, 70 * CGFloat(value) / CGFloat(peak)))
                        Text(weekdayLetter(offset: model.week.count - 1 - index))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Zen.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            .zenCard()
            Text(tr("Bars: impulses resisted plus right answers per day.", "Balken: widerstandene Impulse plus richtige Antworten pro Tag."))
                .font(.system(size: 12))
                .foregroundStyle(Zen.inkFaint)
        }
    }

    private func weekdayLetter(offset: Int) -> String {
        let date = Date().addingTimeInterval(Double(-offset) * 86_400)
        return RuleSchedule.dayName(Calendar.current.component(.weekday, from: date))
    }
}

struct ActionTile: View {
    let kanji: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Hanko(text: kanji, size: 38, color: Zen.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.mincho(20, weight: .semibold)).foregroundStyle(Zen.ink)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Zen.inkSoft)
                }
            }
            .zenCard()
        }
        .buttonStyle(.plain)
    }
}

struct GrantRow: View {
    let grant: UnlockGrant
    let revoke: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let token = grant.applications.first {
                Label(token).labelStyle(.iconOnly).frame(width: 32, height: 32)
            } else if let web = grant.webDomains.first {
                Label(web).labelStyle(.iconOnly).frame(width: 32, height: 32)
            } else {
                Image(systemName: "square.grid.2x2").frame(width: 32, height: 32).foregroundStyle(Zen.inkSoft)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let token = grant.applications.first {
                    Label(token).labelStyle(.titleOnly).font(.system(size: 16, weight: .semibold))
                } else {
                    Text(tr("Unlock", "Freigabe")).font(.system(size: 16, weight: .semibold))
                }
                Text(tr("open until \(grant.expiresAt.formatted(date: .omitted, time: .shortened))", "offen bis \(grant.expiresAt.formatted(date: .omitted, time: .shortened))"))
                    .font(.system(size: 13))
                    .foregroundStyle(Zen.inkSoft)
            }
            Spacer()
            Button(tr("Lock", "Sperren"), action: revoke)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Zen.shu)
        }
    }
}

/// Today's date in kanji numerals, the way a calendar in Kyoto would print it.
enum KanjiDate {
    private static let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    static func number(_ n: Int) -> String {
        guard n > 0 else { return "〇" }
        let tens = n / 10, ones = n % 10
        var out = ""
        if tens > 1 { out += digits[tens] }
        if tens >= 1 { out += "十" }
        out += digits[ones]
        return out
    }

    static func today() -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        return "\(number(c.month ?? 1))月\(number(c.day ?? 1))日"
    }
}
