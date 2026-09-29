import Foundation

// Wire types for the Friends backend. They mirror the server's JSON exactly;
// anything the server adds later is ignored by Codable, anything it drops
// falls back to a default, so an older app keeps working.

struct FriendProfile: Codable, Equatable {
    var id: String
    var nickname: String
    var avatar: String
}

/// The six numbers a member publishes for one day. Nothing else leaves the phone.
struct FriendDay: Codable, Equatable, Hashable {
    var date: String
    var streakDays: Int
    var focusMinutes: Int
    var pomodoros: Int
    var resisted: Int
    var correctAnswers: Int
    var habitsDone: Int
}

struct DayUpload: Encodable {
    var streakDays: Int
    var focusMinutes: Int
    var pomodoros: Int
    var resisted: Int
    var correctAnswers: Int
    var habitsDone: Int
}

struct CircleSummary: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var inviteCode: String
    var isCreator: Bool
    var memberCount: Int
    var maxMembers: Int
    var challengeKind: String?
}

struct CircleMember: Codable, Identifiable, Equatable {
    var id: String
    var nickname: String
    var avatar: String
    var isCreator: Bool
    var isMe: Bool
    var days: [FriendDay]

    /// The member's numbers for a local day key, if they published any.
    func day(_ key: String) -> FriendDay? { days.first { $0.date == key } }

    /// Newest published streak, so a quiet day does not hide it.
    var streak: Int { days.max { $0.date < $1.date }?.streakDays ?? 0 }
}

struct ChallengeMemberValue: Codable, Equatable {
    var memberId: String
    var value: Int
}

struct ChallengeProgress: Codable, Equatable {
    var kind: String
    var title: String
    var metric: String
    var mode: String
    var target: Int
    var goal: Int
    var total: Int
    var progress: Double
    var completed: Bool
    var weekStart: String
    var weekEnd: String
    var members: [ChallengeMemberValue]
}

struct CircleDetail: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var inviteCode: String
    var isCreator: Bool
    var memberCount: Int
    var maxMembers: Int
    var challengeKind: String?
    var members: [CircleMember]
    var challenge: ChallengeProgress?

    var summary: CircleSummary {
        CircleSummary(id: id, name: name, inviteCode: inviteCode, isCreator: isCreator,
                      memberCount: memberCount, maxMembers: maxMembers, challengeKind: challengeKind)
    }
}

struct CircleList: Decodable {
    var circles: [CircleSummary]
}

// MARK: - Fixed lists (must match server/src)

/// The avatars the server accepts. Same order as `AVATARS` in members.js.
enum FriendAvatar {
    static let all: [String] = [
        "leaf", "moon.stars", "sun.max", "flame", "drop", "mountain.2",
        "tree", "cloud", "sparkles", "bird", "fish", "tortoise",
        "hare", "cat", "dog", "pawprint", "star", "heart",
        "bolt", "snowflake", "wind", "book", "music.note", "cup.and.saucer",
    ]

    static let fallback = "leaf"

    /// Guards against a symbol name this app version does not know.
    static func symbol(_ name: String) -> String {
        all.contains(name) ? name : fallback
    }
}

/// The weekly challenges a creator can pick. Same kinds as challenges.js;
/// the server only knows English titles, so the app brings its own.
struct ChallengeKind: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let detail: String

    static let all: [ChallengeKind] = [
        ChallengeKind(id: "focus-rounds-each", icon: "timer",
                      title: tr("5 focus rounds each", "5 Fokusrunden für alle"),
                      detail: tr("Everyone finishes five pomodoros this week.", "Alle schaffen diese Woche fünf Pomodoros.")),
        ChallengeKind(id: "focus-minutes-together", icon: "hourglass",
                      title: tr("600 focus minutes together", "600 Fokusminuten zusammen"),
                      detail: tr("The circle pools its focus time.", "Der Kreis legt seine Fokuszeit zusammen.")),
        ChallengeKind(id: "resist-together", icon: "hand.raised",
                      title: tr("Resist 20 impulses together", "Zusammen 20 Impulsen widerstehen"),
                      detail: tr("Every time someone lets an app be, it counts.", "Jedes Mal, wenn jemand eine App ruhen lässt, zählt es.")),
        ChallengeKind(id: "cards-together", icon: "rectangle.stack",
                      title: tr("Learn 100 cards together", "Zusammen 100 Karten lernen"),
                      detail: tr("Right answers of the whole circle.", "Richtige Antworten des ganzen Kreises.")),
        ChallengeKind(id: "cards-each", icon: "checkmark.seal",
                      title: tr("30 right answers each", "30 richtige Antworten für alle"),
                      detail: tr("Everyone answers thirty cards right.", "Alle beantworten dreißig Karten richtig.")),
        ChallengeKind(id: "habits-each", icon: "leaf",
                      title: tr("10 habits done each", "10 Gewohnheiten für alle"),
                      detail: tr("Everyone ticks off ten habits this week.", "Alle haken diese Woche zehn Gewohnheiten ab.")),
    ]

    static func find(_ id: String?) -> ChallengeKind? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

enum FriendLimits {
    static let nickname = 24
    static let circleName = 40
    static let codeLength = 8
    static let codeAlphabet = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    /// Uppercases, drops spaces and dashes, and keeps only valid code letters.
    static func cleanCode(_ raw: String) -> String {
        String(raw.uppercased().filter { codeAlphabet.contains($0) }.prefix(codeLength))
    }
}

/// Opt-in state kept in the App Group. The Keychain holds the credentials;
/// this only remembers whether sharing is on and what was last uploaded.
struct FriendsSettings: Codable {
    var enabled = false
    /// Cached so the screen shows the right name offline.
    var profile: FriendProfile?
    var lastUpload: DayUploadRecord?

    static let fileName = "friends.json"
}

/// What was last sent, so an unchanged day is not uploaded again.
struct DayUploadRecord: Codable, Equatable {
    var date: String
    var streakDays: Int
    var focusMinutes: Int
    var pomodoros: Int
    var resisted: Int
    var correctAnswers: Int
    var habitsDone: Int
}
