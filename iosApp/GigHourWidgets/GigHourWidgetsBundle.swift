import WidgetKit
import SwiftUI

/// Widget extension bundle. Hosts the live work-progress Live Activity (Lock
/// Screen + Dynamic Island). The main app starts/updates/ends it via
/// LiveWorkActivityManager; this target only renders it.
@main
struct GigHourWidgetsBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            WorkLiveActivity()
        }
    }
}
