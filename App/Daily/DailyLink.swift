import SwiftUI

// The link between Ma and the `daily` command on senseiissei.dev. Ma shows a
// short one-time code; typed into the website terminal as `daily link CODE`
// it lets that browser record finished lessons, which come back here as
// experience. The Friends identity carries the connection; creating it does
// not switch sharing on.

struct DailyLinkCode: Decodable, Equatable {
    var code: String
    var expiresAt: String
}

struct DailyProgressDTO: Decodable {
    struct Entry: Decodable {
        var dayKey: String
        var unitId: String
        var status: String
        var xpAwarded: Int
        var streakAfter: Int
    }

    var streak: Int
    var bonusToday: Int
    var totalXp: Int
    var doneCount: Int
    var today: Entry?
    var entries: [Entry]

    var records: [LessonRecord] {
        entries.map { LessonRecord(dayKey: $0.dayKey, unitId: $0.unitId, status: $0.status,
                                   xpAwarded: $0.xpAwarded, streakAfter: $0.streakAfter) }
    }
}

/// Summary for the card and the companion, derived from the lessons.
struct LessonSummary: Equatable {
    var doneCount = 0
    var totalXp = 0
    var streak = 0
    var doneToday = false

    init(_ lessons: [LessonRecord], today: String = FitnessDate.key(Date())) {
        let done: [LessonRecord] = lessons.filter(\.isDone)
        doneCount = done.count
        totalXp = done.reduce(0) { $0 + $1.xpAwarded }
        doneToday = done.contains { $0.dayKey == today }
        // The last recorded streak still counts while at most one day is empty.
        if let last = lessons.max(by: { $0.dayKey < $1.dayKey }),
           let lastDate = FitnessDate.date(last.dayKey), let todayDate = FitnessDate.date(today) {
            let gap: Int = Calendar.current.dateComponents([.day], from: lastDate, to: todayDate).day ?? 0
            streak = gap <= 2 ? last.streakAfter : 0
        }
    }
}

/// Card in the fitness goal: what the website lessons brought, and the
/// door to linking a browser.
struct DailyLessonsCard: View {
    @Environment(FitnessStore.self) private var fitness
    @State private var linking = false

    var body: some View {
        let summary = LessonSummary(fitness.lessons)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "chevron.left.forwardslash.chevron.right", title: tr("Programming lessons", "Programmier-Lektionen"))
            Text(tr("Type daily in the terminal on senseiissei.dev: one C++ lesson a day, solved by hand. Every finished lesson counts as XP here.",
                    "Tipp daily ins Terminal auf senseiissei.dev: jeden Tag eine C++-Lektion, von Hand gelöst. Jede erledigte Lektion zählt hier als XP."))
                .scaledFont(size: 14)
                .foregroundStyle(Zen.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if summary.doneCount > 0 {
                HStack(spacing: 12) {
                    StatTile(icon: "checkmark.circle.fill", value: "\(summary.doneCount)",
                             label: tr("Lessons", "Lektionen"), tint: Zen.matcha)
                    StatTile(icon: "flame.fill", value: "\(summary.streak)",
                             label: tr("Day streak", "Tage Serie"), tint: Zen.kin)
                    StatTile(icon: "sparkles", value: FitnessFormat.number(summary.totalXp),
                             label: "XP", tint: Zen.shu)
                }
                Label(summary.doneToday ? tr("Today's lesson is done.", "Die Lektion von heute ist erledigt.")
                                        : tr("Today's lesson is still open.", "Die Lektion von heute ist noch offen."),
                      systemImage: summary.doneToday ? "checkmark.seal.fill" : "clock")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(summary.doneToday ? Zen.matcha : Zen.kin)
            }
            Button(tr("Link senseiissei.dev", "Mit senseiissei.dev verbinden")) { linking = true }
                .buttonStyle(.quiet)
        }
        .zenCard()
        .sheet(isPresented: $linking) {
            DailyLinkSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

/// The sheet around the link view, for the fitness card.
struct DailyLinkSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DailyLinkView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Done", "Fertig")) { dismiss() }
                    }
                }
        }
    }
}

/// Shows the one-time code, big enough to type from across the desk.
struct DailyLinkView: View {
    @Environment(FriendsStore.self) private var friends
    @State private var code: DailyLinkCode?
    @State private var failed: String?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 20) {
                Text(tr("Open senseiissei.dev, open the terminal and type:",
                        "Öffne senseiissei.dev, öffne das Terminal und tippe:"))
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.inkSoft)
                    .multilineTextAlignment(.center)
                if let code {
                    Text("daily link \(code.code)")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(Zen.ink)
                        .textSelection(.enabled)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 22)
                        .background(Zen.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(tr("The code works once and for ten minutes.", "Der Code gilt einmal und zehn Minuten lang."))
                        .scaledFont(size: 13)
                        .foregroundStyle(Zen.inkFaint)
                } else if loading {
                    ProgressView()
                } else if let failed {
                    Label(failed, systemImage: "exclamationmark.triangle")
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(Zen.negative)
                        .multilineTextAlignment(.center)
                }
                Button(code == nil ? tr("Get a code", "Code holen") : tr("New code", "Neuer Code")) {
                    Task { await load() }
                }
                .buttonStyle(.primary)
                .disabled(loading)
                Text(tr("Ma creates an anonymous id on its server for this. Sharing with friends stays off.",
                        "Ma legt dafür eine anonyme ID auf seinem Server an. Das Teilen mit Freunden bleibt aus."))
                    .scaledFont(size: 12)
                    .foregroundStyle(Zen.inkFaint)
                    .multilineTextAlignment(.center)
            }
        .padding(Zen.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
        .navigationTitle(tr("Link the website", "Website verbinden"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        failed = nil
        defer { loading = false }
        if let fresh = await friends.dailyLinkCode() {
            code = fresh
            Haptics.success()
        } else {
            failed = friends.errorMessage ?? tr("Ma's server is not reachable right now.", "Mas Server ist gerade nicht erreichbar.")
        }
    }
}
