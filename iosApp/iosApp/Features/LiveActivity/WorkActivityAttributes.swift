import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Shared ActivityKit attributes for the live work-progress Live Activity
/// (Lock Screen + Dynamic Island) — the iOS equivalent of Android's
/// LiveJobProgressNotification WORKING tracker. Included in BOTH the app target
/// (to start/update/end the activity) and the widget-extension target (to render
/// it). `ContentState` is the mutable part pushed on each tick.
@available(iOS 16.1, *)
struct WorkActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Seconds elapsed at the moment of this update (the widget shows a live
        /// timer relative to `startedAt`, but we also carry elapsed for the
        /// compact/minimal presentations that can't host a relative timer).
        var earned: Double         // ₹ earned-so-far at update time
        var hourlyRate: Double
    }

    /// Static for the life of the activity.
    var jobTitle: String
    var startedAt: Date
    var applicationId: String
}
