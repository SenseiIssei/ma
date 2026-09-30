import Foundation
import Observation

/// Weight goal, weigh-ins and workouts. Workouts come from a Garmin feed
/// (a URL the person pastes once) or are typed in by hand. Everything the
/// screens show is derived in one `FitnessReport`, so experience points
/// never drift from the data they come from.
@MainActor
@Observable
final class FitnessStore {
    private(set) var goal: FitnessGoal?
    private(set) var weights: [WeightEntry] = []
    /// Newest first.
    private(set) var workouts: [FitnessWorkout] = []
    private(set) var days: [String: FitnessDay] = [:]
    private(set) var settings = FitnessSettings()
    private(set) var report = FitnessReport()

    private(set) var syncing = false
    private(set) var syncError: String?
    /// Set when a level or a badge is new; the tab bar shows the sheet.
    var celebration: FitnessCelebration?

    private enum File {
        static let goal = "fitness-goal.json"
        static let weights = "fitness-weights.json"
        static let workouts = "fitness-workouts.json"
        static let days = "fitness-days.json"
        static let settings = "fitness-settings.json"
    }

    /// The Garmin sync behind the feed runs every five minutes; asking more
    /// often only costs battery.
    private static let minimumInterval: TimeInterval = 5 * 60

    init() {
        goal = MaShared.read(FitnessGoal.self, from: File.goal)
        weights = MaShared.read([WeightEntry].self, from: File.weights) ?? []
        workouts = MaShared.read([FitnessWorkout].self, from: File.workouts) ?? []
        days = MaShared.read([String: FitnessDay].self, from: File.days) ?? [:]
        settings = MaShared.read(FitnessSettings.self, from: File.settings) ?? FitnessSettings()
        rebuild()
    }

    // MARK: Derived

    var hasFeed: Bool { feedURL != nil }

    var feedURL: URL? {
        let text: String = settings.feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    var today: FitnessDay? { days[FitnessDate.key(Date())] }

    /// The newest daily totals the feed reported, with their day.
    var latestDay: (key: String, day: FitnessDay)? {
        guard let key = days.keys.max(), let day = days[key] else { return nil }
        return (key, day)
    }

    func rate(_ kind: ActivityKind) -> Double {
        FitnessMath.kcalPerMinute(kind, weightKg: report.currentKg ?? goal?.startKg ?? 75, history: workouts)
    }

    func hasOwnRate(_ kind: ActivityKind) -> Bool {
        FitnessMath.hasOwnRate(kind, history: workouts)
    }

    /// What the four weeks before today looked like, for a new goal.
    var currentBaseline: Double {
        FitnessMath.baseline(workouts, before: Date())
    }

    private func rebuild() {
        report = FitnessReport.make(goal: goal, workouts: workouts, days: days, weights: weights)
    }

    // MARK: Goal

    func startGoal(currentKg: Double, goalKg: Double, heightCm: Double?, kgPerWeek: Double,
                   favorites: [ActivityKind], baseline: Double) {
        let today: String = FitnessDate.key(Date())
        goal = FitnessGoal(startKg: currentKg, goalKg: goalKg, heightCm: heightCm,
                           kgPerWeek: FitnessMath.clampPace(kgPerWeek),
                           startDate: today, baselineWeeklyKcal: max(0, baseline),
                           favorites: favorites)
        upsertWeight(WeightEntry(date: today, kg: currentKg))
        MaShared.write(goal, to: File.goal)
        rebuild()
        checkCelebration()
    }

    /// Changes pace, target or favourites without starting over; the start
    /// weight and date stay, so progress keeps its meaning.
    func updateGoal(goalKg: Double, heightCm: Double?, kgPerWeek: Double,
                    favorites: [ActivityKind], baseline: Double) {
        guard var goal else { return }
        goal.goalKg = goalKg
        goal.heightCm = heightCm
        goal.kgPerWeek = FitnessMath.clampPace(kgPerWeek)
        goal.favorites = favorites
        goal.baselineWeeklyKcal = max(0, baseline)
        self.goal = goal
        MaShared.write(goal, to: File.goal)
        rebuild()
    }

    func endGoal() {
        goal = nil
        MaShared.write(goal, to: File.goal)
        rebuild()
    }

    // MARK: Weight

    func logWeight(_ kg: Double, on date: Date = Date()) {
        guard kg >= 25, kg <= 400 else { return }
        upsertWeight(WeightEntry(date: FitnessDate.key(date), kg: (kg * 10).rounded() / 10))
        rebuild()
        checkCelebration()
    }

    func removeWeight(_ entry: WeightEntry) {
        weights.removeAll { $0.date == entry.date }
        MaShared.write(weights, to: File.weights)
        rebuild()
    }

    private func upsertWeight(_ entry: WeightEntry) {
        weights.removeAll { $0.date == entry.date }
        weights.append(entry)
        weights.sort { $0.date < $1.date }
        MaShared.write(weights, to: File.weights)
    }

    // MARK: Workouts

    func addManual(kind: ActivityKind, minutes: Int, calories: Int?, km: Double?, date: Date) {
        guard minutes > 0 else { return }
        let kcal: Int = calories ?? Int((Double(minutes) * rate(kind)).rounded())
        let workout = FitnessWorkout(id: "manual-\(UUID().uuidString)", kind: kind, name: kind.title,
                                     date: FitnessDate.key(date), minutes: minutes, km: km,
                                     calories: max(0, kcal), averageHeartRate: nil, source: .manual)
        workouts.append(workout)
        persistWorkouts()
        checkCelebration()
    }

    /// Manual ones are gone for good; Garmin ones stay hidden so the next
    /// sync does not bring them back.
    func remove(_ workout: FitnessWorkout) {
        workouts.removeAll { $0.id == workout.id }
        if workout.source == .garmin {
            settings.hiddenWorkouts.insert(workout.id)
            persistSettings()
        }
        persistWorkouts()
    }

    private func persistWorkouts() {
        workouts.sort { ($0.date, $0.id) > ($1.date, $1.id) }
        // Five years of sessions is more than any screen here looks at.
        if workouts.count > 2000 { workouts.removeLast(workouts.count - 2000) }
        MaShared.write(workouts, to: File.workouts)
        rebuild()
    }

    // MARK: Garmin feed

    func setFeedURL(_ text: String) {
        settings.feedURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.lastSync = nil
        syncError = nil
        persistSettings()
    }

    /// Fetches the feed unless it was fetched a moment ago. Called when the
    /// app comes to the front and from pull to refresh (`force`).
    func refresh(force: Bool = false) async {
        guard let url = feedURL, !syncing else { return }
        if !force, let last = settings.lastSync, Date().timeIntervalSince(last) < Self.minimumInterval { return }
        syncing = true
        defer { syncing = false }
        do {
            let feed: GarminFeed = try await Self.fetch(url)
            apply(feed)
            settings.lastSync = Date()
            syncError = nil
            persistSettings()
            checkCelebration()
        } catch {
            syncError = Self.describe(error)
        }
    }

    /// For the "Test" button: how many workouts the URL returns.
    static func probe(_ text: String) async -> Result<Int, FeedError> {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return .failure(.badURL) }
        do {
            let feed: GarminFeed = try await fetch(url)
            return .success(feed.workouts?.count ?? 0)
        } catch let error as FeedError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    enum FeedError: Error, Equatable {
        case badURL, network, status(Int), format

        var message: String {
            switch self {
            case .badURL: tr("That is not an https address.", "Das ist keine https-Adresse.")
            case .network: tr("The feed could not be reached.", "Der Feed war nicht erreichbar.")
            case .status(let code): tr("The server answered \(code).", "Der Server antwortete mit \(code).")
            case .format: tr("The answer is not a Garmin snapshot.", "Die Antwort ist kein Garmin-Schnappschuss.")
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static func fetch(_ url: URL) async throws -> GarminFeed {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw FeedError.network
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.status(http.statusCode)
        }
        guard let feed = try? JSONDecoder().decode(GarminFeed.self, from: data),
              feed.latest != nil || feed.workouts != nil else { throw FeedError.format }
        return feed
    }

    private static func describe(_ error: Error) -> String {
        (error as? FeedError)?.message ?? FeedError.network.message
    }

    private func apply(_ feed: GarminFeed) {
        var byID: [String: FitnessWorkout] = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for incoming in feed.workouts ?? [] {
            let record: FitnessWorkout = incoming.record
            guard !settings.hiddenWorkouts.contains(record.id), !record.date.isEmpty else { continue }
            byID[record.id] = record
        }
        workouts = Array(byID.values)

        for totals in (feed.activity ?? []) + [feed.latest].compactMap({ $0 }) {
            let key = String(totals.date.prefix(10))
            guard key.count == 10 else { continue }
            days[key] = totals.day
        }
        if days.count > 800 {
            for key in days.keys.sorted().prefix(days.count - 800) { days.removeValue(forKey: key) }
        }
        MaShared.write(days, to: File.days)
        persistWorkouts()
    }

    private func persistSettings() {
        MaShared.write(settings, to: File.settings)
    }

    // MARK: Celebrations

    /// A new level or badge since the last look. The first time data
    /// arrives, the starting level is greeted too.
    func checkCelebration() {
        let level: Int = report.progress.level
        let earned: Set<String> = Set(report.badges.filter(\.earned).map(\.id))
        let newBadges: [FitnessBadge] = report.badges.filter { $0.earned && !settings.seenBadges.contains($0.id) }
        let hasData: Bool = report.xp > 0
        guard hasData, level > settings.seenLevel || !newBadges.isEmpty else { return }
        celebration = FitnessCelebration(level: level,
                                         levelUp: level > settings.seenLevel,
                                         first: settings.seenLevel == 0,
                                         badges: newBadges)
        settings.seenLevel = max(settings.seenLevel, level)
        settings.seenBadges.formUnion(earned)
        persistSettings()
    }
}

struct FitnessCelebration: Identifiable, Equatable {
    let level: Int
    let levelUp: Bool
    /// The very first greeting, when history from the watch already counts.
    let first: Bool
    let badges: [FitnessBadge]

    var id: String { "\(level)-\(badges.map(\.id).joined(separator: ","))" }
}
