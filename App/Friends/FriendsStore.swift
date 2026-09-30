import Foundation
import Observation

/// State for "Friends without a feed". Owns the identity (Keychain), the
/// opt-in switch (App Group) and the circles as last seen on the server.
/// Nothing is uploaded unless `isEnabled` is true.
@MainActor
@Observable
final class FriendsStore {
    private(set) var settings: FriendsSettings
    private(set) var profile: FriendProfile?
    private(set) var circles: [CircleSummary] = []
    private(set) var details: [String: CircleDetail] = [:]
    private(set) var isLoading = false
    private(set) var lastSync: Date?
    var errorMessage: String?

    private var credentials: FriendCredentials?
    private var api: FriendsAPI

    init(baseURL: URL = FriendsAPI.defaultBaseURL) {
        let saved = MaShared.read(FriendsSettings.self, from: FriendsSettings.fileName) ?? FriendsSettings()
        let creds = FriendsKeychain.load()
        settings = saved
        credentials = creds
        profile = saved.profile
        api = FriendsAPI(baseURL: baseURL, credentials: creds)
    }

    /// Sharing is on and this device has an identity on the server.
    var isEnabled: Bool { settings.enabled && credentials != nil && profile != nil }

    /// True once the device registered, even while sharing is switched off.
    var hasIdentity: Bool { credentials != nil && profile != nil }

    var myId: String? { credentials?.memberId }

    // MARK: Opt in and out

    /// Switches Friends on. The first time, this creates the identity: a random
    /// id and secret, saved to the Keychain before the network call so a lost
    /// response can be recovered on the next try.
    func enable(nickname: String, avatar: String) async -> Bool {
        let nickname = Self.cleanNickname(nickname)
        guard !nickname.isEmpty else {
            errorMessage = tr("Please choose a nickname.", "Bitte wähle einen Spitznamen.")
            return false
        }
        return await run {
            if self.hasIdentity {
                self.profile = try await self.api.updateProfile(nickname: nickname, avatar: avatar)
            } else {
                let creds = try self.credentialsForSignup()
                do {
                    self.profile = try await self.api.register(creds, nickname: nickname, avatar: avatar)
                } catch FriendsError.conflict {
                    // The id is taken, most likely by our own earlier attempt
                    // whose answer got lost. If the secret works, it is ours.
                    self.profile = try await self.api.me()
                }
            }
            self.settings.enabled = true
            self.persist()
            await self.refreshCircles()
        }
    }

    /// Stops uploading. Circles and identity stay, so switching back on is instant.
    func disable() {
        settings.enabled = false
        persist()
    }

    /// DELETE /me, then forget the identity on this device. Afterwards there is
    /// nothing about this member left, neither on the server nor here.
    func deleteAllData() async -> Bool {
        await run {
            if self.credentials != nil {
                do {
                    try await self.api.deleteMe()
                } catch FriendsError.unauthorized {
                    // Already gone on the server; still clean up locally.
                }
            }
            self.forgetLocally()
        }
    }

    // MARK: Profile

    func updateProfile(nickname: String, avatar: String) async -> Bool {
        let nickname = Self.cleanNickname(nickname)
        guard !nickname.isEmpty else {
            errorMessage = tr("Please choose a nickname.", "Bitte wähle einen Spitznamen.")
            return false
        }
        return await run {
            self.profile = try await self.api.updateProfile(nickname: nickname, avatar: avatar)
            self.persist()
            // Names inside loaded circles are stale now.
            self.details = [:]
        }
    }

    // MARK: Circles

    func refreshCircles() async {
        guard hasIdentity else { return }
        await run {
            self.circles = try await self.api.circles()
            let ids = Set(self.circles.map(\.id))
            self.details = self.details.filter { ids.contains($0.key) }
            self.lastSync = Date()
        }
    }

    func loadCircle(_ id: String) async {
        await run {
            do {
                let detail = try await self.api.circle(id)
                self.store(detail)
            } catch FriendsError.notFound {
                // Removed by the creator, or the circle is gone.
                self.drop(id)
                throw FriendsError.notFound(tr("You are no longer in this circle.", "Du bist nicht mehr in diesem Kreis."))
            }
        }
    }

    func createCircle(name: String) async -> CircleDetail? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var created: CircleDetail?
        _ = await run {
            let detail = try await self.api.createCircle(name: String(name.prefix(FriendLimits.circleName)))
            self.store(detail)
            created = detail
        }
        return created
    }

    func join(code raw: String) async -> CircleDetail? {
        let code = FriendLimits.cleanCode(raw)
        guard code.count == FriendLimits.codeLength else {
            errorMessage = tr("An invite code has 8 characters.", "Ein Einladungscode hat 8 Zeichen.")
            return nil
        }
        var joined: CircleDetail?
        _ = await run {
            do {
                let detail = try await self.api.join(code: code)
                self.store(detail)
                joined = detail
            } catch FriendsError.notFound {
                throw FriendsError.notFound(tr("No circle has this code. Check it, or ask for a new one.",
                                               "Kein Kreis hat diesen Code. Prüf ihn oder frag nach einem neuen."))
            } catch FriendsError.conflict {
                throw FriendsError.conflict(tr("This circle is full, or you are already in 10 circles.",
                                               "Dieser Kreis ist voll, oder du bist schon in 10 Kreisen."))
            }
        }
        return joined
    }

    func leave(_ id: String) async -> Bool {
        await run {
            try await self.api.leave(id)
            self.drop(id)
        }
    }

    func rotateCode(_ id: String) async {
        await run {
            let summary = try await self.api.rotateCode(id)
            self.replaceSummary(summary)
            if var detail = self.details[id] {
                detail.inviteCode = summary.inviteCode
                self.details[id] = detail
            }
        }
    }

    func remove(_ memberId: String, from circleId: String) async {
        await run {
            try await self.api.removeMember(memberId, from: circleId)
            let detail = try await self.api.circle(circleId)
            self.store(detail)
        }
    }

    func setChallenge(_ kind: String?, for circleId: String) async {
        await run {
            let detail = try await self.api.setChallenge(kind, for: circleId)
            self.store(detail)
        }
    }

    // MARK: Daily numbers

    /// Publishes today's numbers from the App Group. Streak and habits live in
    /// the app's own stores, so the caller passes them in. Does nothing unless
    /// sharing is on, and skips the network when nothing changed.
    func syncToday(streak: Int, habitsDone: Int) async {
        guard isEnabled else { return }
        let todayKey = SharedStore.dayKey()
        let yesterdayKey = SharedStore.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        // The first sync of a new day also sends yesterday's final numbers:
        // whatever happened after the last upload would otherwise be lost.
        if let last = settings.lastUpload, last.date == yesterdayKey,
           let day = SharedStore.stats[yesterdayKey] {
            let closing = Self.record(date: yesterdayKey, day: day, streak: last.streakDays, habitsDone: last.habitsDone)
            if closing != last { _ = await upload(closing) }
        }

        let record = Self.record(date: todayKey, day: SharedStore.today(), streak: streak, habitsDone: habitsDone)
        if record != settings.lastUpload { _ = await upload(record) }
    }

    private func upload(_ record: DayUploadRecord) async -> Bool {
        let body = DayUpload(streakDays: record.streakDays, focusMinutes: record.focusMinutes,
                             pomodoros: record.pomodoros, resisted: record.resisted,
                             correctAnswers: record.correctAnswers, habitsDone: record.habitsDone)
        do {
            try await api.publish(body, date: record.date)
            settings.lastUpload = record
            persist()
            return true
        } catch FriendsError.unauthorized {
            forgetLocally()
            return false
        } catch {
            // Quiet on purpose: this runs on every app activation, and the
            // next activation simply tries again.
            return false
        }
    }

    private static func record(date: String, day: DayStats, streak: Int, habitsDone: Int) -> DayUploadRecord {
        // Clamped to the server's bounds so an odd local value never makes
        // the whole upload fail.
        DayUploadRecord(date: date,
                        streakDays: clamp(streak, 36_500),
                        focusMinutes: clamp(day.focusMinutes, 1_440),
                        pomodoros: clamp(day.pomodoros, 100),
                        resisted: clamp(day.resisted, 10_000),
                        correctAnswers: clamp(day.correct, 10_000),
                        habitsDone: clamp(habitsDone, 1_000))
    }

    private static func clamp(_ value: Int, _ max: Int) -> Int { Swift.min(Swift.max(0, value), max) }

    // MARK: Helpers

    nonisolated static func cleanNickname(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(FriendLimits.nickname))
    }

    private func credentialsForSignup() throws -> FriendCredentials {
        if let credentials { return credentials }
        guard let fresh = FriendCredentials.generate(), FriendsKeychain.save(fresh) else {
            throw FriendsError.invalid(tr("Could not store the key on this device.",
                                          "Der Schlüssel konnte auf diesem Gerät nicht gespeichert werden."))
        }
        credentials = fresh
        api.credentials = fresh
        return fresh
    }

    private func store(_ detail: CircleDetail) {
        details[detail.id] = detail
        replaceSummary(detail.summary)
    }

    private func replaceSummary(_ summary: CircleSummary) {
        if let index = circles.firstIndex(where: { $0.id == summary.id }) {
            circles[index] = summary
        } else {
            circles.append(summary)
        }
    }

    private func drop(_ id: String) {
        circles.removeAll { $0.id == id }
        details[id] = nil
    }

    /// Forgets identity and state on this device only.
    private func forgetLocally() {
        FriendsKeychain.delete()
        credentials = nil
        api.credentials = nil
        profile = nil
        circles = []
        details = [:]
        lastSync = nil
        settings = FriendsSettings()
        persist()
    }

    private func persist() {
        settings.profile = profile
        MaShared.write(settings, to: FriendsSettings.fileName)
    }

    /// Runs one server action with a busy flag and a readable error. Returns
    /// whether it succeeded.
    @discardableResult
    private func run(_ work: () async throws -> Void) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await work()
            return true
        } catch FriendsError.unauthorized {
            forgetLocally()
            errorMessage = FriendsError.unauthorized.errorDescription
            return false
        } catch let error as FriendsError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = FriendsError.server.errorDescription
            return false
        }
    }
}
