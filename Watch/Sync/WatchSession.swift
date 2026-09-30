import Foundation
import Observation
import WatchConnectivity

/// The watch end of WatchConnectivity. Holds the newest snapshot from the
/// iPhone, keeps a copy on disk so the face is never empty offline, and
/// passes start and stop taps on to the phone.
@MainActor
@Observable
final class WatchSession {
    static let shared = WatchSession()
    static let storageKey = "ma.watch.snapshot"
    /// How long a tap shows as "waiting for the iPhone" before we give up
    /// on hearing back and show the plain state again.
    static let pendingTimeout: TimeInterval = 20

    private(set) var snapshot: WatchSnapshot?
    private(set) var reachable = false
    private(set) var activated = false
    /// The command that was sent and has not shown up in a snapshot yet.
    private(set) var pending: WatchCommand?
    /// True when the last tap could not be delivered live and waits in the
    /// queue until the phone is back.
    private(set) var queued = false

    @ObservationIgnored private let link = WatchLink()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pendingToken = 0
    /// A tap made before the session finished activating; sent right after.
    @ObservationIgnored private var deferred: [String: Any]?

    init() {
        snapshot = Self.loadStored()
    }

    /// Activates the session once. Safe to call from every onAppear.
    func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true
        let session = WCSession.default
        session.delegate = link
        session.activate()
    }

    // MARK: Commands

    func send(_ command: WatchCommand) {
        let message: [String: Any] = command.message(at: Date())
        setPending(command)
        queued = false

        let session = WCSession.default
        guard session.activationState == .activated else {
            enqueue(message, on: session)
            return
        }
        guard session.isReachable else {
            enqueue(message, on: session)
            return
        }
        session.sendMessage(message, replyHandler: { reply in
            let fresh: WatchSnapshot? = WatchSnapshot.from(reply)
            Task { @MainActor in WatchSession.shared.received(fresh) }
        }, errorHandler: { _ in
            // Did not get through live (phone locked away, Bluetooth gap):
            // queue it so it lands once the phone is back.
            Task { @MainActor in WatchSession.shared.enqueue(message, on: WCSession.default) }
        })
    }

    /// The fallback: a queued transfer that survives until the phone shows
    /// up. Older queued taps go first, so start then stop never both land.
    private func enqueue(_ message: [String: Any], on session: WCSession) {
        queued = true
        guard session.activationState == .activated else {
            deferred = message
            return
        }
        for transfer in session.outstandingUserInfoTransfers where transfer.userInfo[WatchCommand.commandKey] != nil {
            transfer.cancel()
        }
        session.transferUserInfo(message)
    }

    private func setPending(_ command: WatchCommand) {
        pending = command
        pendingToken += 1
        let token: Int = pendingToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.pendingTimeout * 1_000_000_000))
            // Only clear the tap this timer belongs to, not a newer one.
            guard self.pendingToken == token else { return }
            self.pending = nil
        }
    }

    // MARK: From the link

    func didActivate(reachable: Bool, context: WatchSnapshot?) {
        activated = true
        self.reachable = reachable
        received(context)
        if let message = deferred {
            deferred = nil
            enqueue(message, on: WCSession.default)
        }
    }

    func reachabilityChanged(_ reachable: Bool) {
        self.reachable = reachable
        if reachable { queued = false }
    }

    /// A new snapshot from the context or a command reply.
    func received(_ fresh: WatchSnapshot?) {
        guard let fresh else { return }
        if fresh != snapshot {
            snapshot = fresh
            Self.store(fresh)
        }
        if let pending, pending.isSatisfied(by: fresh, at: Date()) {
            self.pending = nil
            queued = false
        }
    }

    // MARK: Storage

    private static func loadStored() -> WatchSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return WatchSnapshot.decoded(from: data)
    }

    private static func store(_ snapshot: WatchSnapshot) {
        guard let data = snapshot.encoded() else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// The delegate WCSession calls on its own queue. Kept apart from the
/// main-actor WatchSession so the protocol's nonisolated methods never
/// touch main-actor state directly; every call hops over first.
final class WatchLink: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable: Bool = session.isReachable
        let context: WatchSnapshot? = WatchSnapshot.from(session.receivedApplicationContext)
        Task { @MainActor in
            WatchSession.shared.didActivate(reachable: reachable, context: context)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context: WatchSnapshot? = WatchSnapshot.from(applicationContext)
        Task { @MainActor in WatchSession.shared.received(context) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable: Bool = session.isReachable
        Task { @MainActor in WatchSession.shared.reachabilityChanged(reachable) }
    }
}
