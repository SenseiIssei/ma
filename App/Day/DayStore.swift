import Foundation
import Observation
import SwiftUI

/// Journal, habits and breathing stats. Only the app reads these, but they
/// still live in the App Group so a backup of the container holds everything.
@MainActor
@Observable
final class DayStore {
    private(set) var entries: [String: DayEntry] = [:]
    private(set) var habits: [Habit] = []
    private(set) var breath = BreathStats()
    /// Set once the starter habits were offered, taken or declined.
    private(set) var habitsOffered = false

    private enum File {
        static let journal = "day-journal.json"
        static let habits = "habits.json"
        static let breath = "breath.json"
        static let offered = "habits-offered.json"
    }

    init() {
        entries = MaShared.read([String: DayEntry].self, from: File.journal) ?? [:]
        habits = MaShared.read([Habit].self, from: File.habits) ?? []
        breath = MaShared.read(BreathStats.self, from: File.breath) ?? BreathStats()
        habitsOffered = MaShared.read(Bool.self, from: File.offered) ?? !habits.isEmpty
    }

    var todayKey: String { DayKey.of() }

    // MARK: Journal

    var today: DayEntry { entries[todayKey] ?? DayEntry() }

    var intention: String? {
        let text = today.morning?.intention.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Moods of the last seven days, oldest first, nil where none was logged.
    var weekMoods: [Mood?] {
        (0..<7).reversed().map { entries[DayKey.of(daysBefore: $0)]?.morning?.mood }
    }

    func saveMorning(mood: Mood, intention: String) {
        let text = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = today
        entry.morning = MorningCheckIn(mood: mood, intention: String(text.prefix(120)))
        entries[todayKey] = entry
        persistJournal()
    }

    func saveEvening(_ reflection: EveningReflection) {
        var entry = today
        entry.evening = reflection
        entries[todayKey] = entry
        persistJournal()
    }

    private func persistJournal() {
        if entries.count > 400 {
            for key in entries.keys.sorted().prefix(entries.count - 400) { entries.removeValue(forKey: key) }
        }
        MaShared.write(entries, to: File.journal)
    }

    // MARK: Habits

    var habitsDoneToday: Int { habits.filter { $0.isDone(on: todayKey) }.count }

    var habitProgress: Double {
        guard !habits.isEmpty else { return 0 }
        let sum = habits.reduce(0.0) { $0 + $1.progress(on: todayKey) }
        return sum / Double(habits.count)
    }

    func tap(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].tap(on: todayKey)
        persistHabits()
    }

    func decrement(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].decrement(on: todayKey)
        persistHabits()
    }

    func save(_ habit: Habit) {
        if let index = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[index] = habit
        } else {
            habits.append(habit)
        }
        markOffered()
        persistHabits()
    }

    func delete(at offsets: IndexSet) {
        habits.remove(atOffsets: offsets)
        persistHabits()
    }

    func delete(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        persistHabits()
    }

    func move(from source: IndexSet, to destination: Int) {
        habits.move(fromOffsets: source, toOffset: destination)
        persistHabits()
    }

    func adoptDefaults() {
        let existing = Set(habits.map(\.title))
        habits += Habit.defaults.filter { !existing.contains($0.title) }
        markOffered()
        persistHabits()
    }

    func declineDefaults() {
        markOffered()
    }

    private func markOffered() {
        guard !habitsOffered else { return }
        habitsOffered = true
        MaShared.write(true, to: File.offered)
    }

    private func persistHabits() {
        for index in habits.indices { habits[index].trimLog() }
        MaShared.write(habits, to: File.habits)
    }

    // MARK: Breathing

    var breathSessionsToday: Int { breath.byDay[todayKey] ?? 0 }

    func recordBreath(seconds: Int) {
        breath.record(seconds: seconds, on: todayKey)
        MaShared.write(breath, to: File.breath)
    }
}
