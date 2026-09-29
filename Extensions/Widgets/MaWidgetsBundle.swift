import SwiftUI
import WidgetKit

/// Entry point of the MaWidgets extension: Home Screen and Lock Screen
/// widgets plus the focus Live Activity.
@main
struct MaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FocusWidget()
        LockScreenWidget()
        FocusLiveActivity()
    }
}
