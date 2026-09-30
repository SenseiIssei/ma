import SwiftUI

/// Ma on the wrist: today's rings, a breathing session and the focus timer.
/// The iPhone stays in charge of everything that blocks apps.
@main
struct MaWatchApp: App {
    @State private var session = WatchSession.shared

    init() {
        // Activate before the first view so a context the phone sent while
        // the watch app was closed is read on launch, not on first draw.
        WatchSession.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environment(session)
            .tint(Night.shu)
        }
    }
}
