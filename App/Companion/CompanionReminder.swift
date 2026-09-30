import AVFoundation
import Foundation
import UIKit
import UserNotifications

/// A morning greeting from the companion: their portrait, today's quest,
/// and their own recorded morning line as the notification sound.
///
/// The content is written fresh every time the app comes to the front, so
/// the quest in it is the one that fits the latest numbers. It repeats
/// daily, so a morning without opening Ma still gets the last greeting.
enum CompanionReminder {
    static let id = "ma.companion.morning"
    static let route = "companion"

    private static let onKey = "ma.companion.reminder"
    private static let minuteKey = "ma.companion.reminderMinute"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: onKey)
    }

    /// Minutes after midnight, 8:00 by default.
    static var minute: Int {
        get { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 8 * 60 }
        set { UserDefaults.standard.set(min(23 * 60 + 59, max(0, newValue)), forKey: minuteKey) }
    }

    /// Asks for permission when switching on; returns whether it is on.
    @MainActor
    @discardableResult
    static func set(_ on: Bool, snapshot: CompanionSnapshot) async -> Bool {
        guard on else {
            UserDefaults.standard.set(false, forKey: onKey)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            return false
        }
        let granted: Bool = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: onKey)
        if granted { schedule(snapshot) }
        return granted
    }

    @MainActor
    static func refresh(_ snapshot: CompanionSnapshot) {
        guard isOn, CompanionID.hasChosen else { return }
        schedule(snapshot)
    }

    @MainActor
    private static func schedule(_ snapshot: CompanionSnapshot) {
        let who: CompanionID = CompanionID.current
        // A new variant each day the app is opened.
        let seed: Int = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let line: VoiceLine? = VoiceLibrary.line(who, .morning, seed: seed)

        let content = UNMutableNotificationContent()
        content.title = line.map { "\(who.name): \($0.subtitle)" } ?? who.name
        if let quest = CompanionScript.dailyQuest(snapshot) {
            content.body = "\(quest.title): \(quest.detail) · +\(quest.reward) XP"
        } else {
            content.body = CompanionScript.statusSentence(snapshot)
        }
        content.sound = line.flatMap(sound(for:)) ?? .default
        content.interruptionLevel = .active
        content.userInfo = [Notifier.routeKey: route]
        if let attachment = portrait(who) {
            content.attachments = [attachment]
        }

        var when = DateComponents()
        when.hour = minute / 60
        when.minute = minute % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Notification sounds must be uncompressed and live in Library/Sounds,
    /// so the AAC clip is decoded into a CAF there once.
    private static func sound(for line: VoiceLine) -> UNNotificationSound? {
        guard let source = Bundle.main.url(forResource: line.file, withExtension: "m4a"),
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let folder: URL = library.appendingPathComponent("Sounds", isDirectory: true)
        let name: String = "\(line.file).caf"
        let target: URL = folder.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: target.path) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let input = try AVAudioFile(forReading: source)
                let format: AVAudioFormat = input.processingFormat
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)) else { return nil }
                try input.read(into: buffer)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ]
                let output = try AVAudioFile(forWriting: target, settings: settings,
                                             commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                try output.write(from: buffer)
            } catch {
                try? FileManager.default.removeItem(at: target)
                return nil
            }
        }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }

    /// The system moves attachments into its own store, so each schedule
    /// hands over a fresh copy of the portrait.
    @MainActor
    private static func portrait(_ who: CompanionID) -> UNNotificationAttachment? {
        guard let image = UIImage(named: who.image(.cheer)) ?? UIImage(named: who.image(.neutral)),
              let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("companion-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "portrait", url: url, options: nil)
    }
}
