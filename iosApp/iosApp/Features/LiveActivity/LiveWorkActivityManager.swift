import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts / updates / ends the live work-progress Live Activity as a shift runs
/// (iOS counterpart of Android's WorkShiftLiveService ticking the WORKING
/// notification). Guarded for iOS 16.1+; a no-op below that or when the user has
/// Live Activities disabled. The in-app floating FOB remains the primary
/// surface — this adds the Lock Screen / Dynamic Island presence.
final class LiveWorkActivityManager {
    static let shared = LiveWorkActivityManager()
    private init() {}

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var current: Activity<WorkActivityAttributes>? {
        Activity<WorkActivityAttributes>.activities.first
    }

    /// Ensure an activity exists for this WIP shift (start if none), else update
    /// its content. `earned` is the live earned-so-far.
    func sync(applicationId: String, jobTitle: String, startedAt: Date, hourlyRate: Double, earned: Double) {
        guard #available(iOS 16.1, *),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = WorkActivityAttributes.ContentState(earned: earned, hourlyRate: hourlyRate)

        if let activity = current {
            // Same shift → update; different shift → restart.
            if activity.attributes.applicationId == applicationId {
                Task { await activity.update(using: state) }
                return
            }
            Task { await activity.end(using: state, dismissalPolicy: .immediate) }
        }
        let attributes = WorkActivityAttributes(
            jobTitle: jobTitle, startedAt: startedAt, applicationId: applicationId
        )
        _ = try? Activity.request(attributes: attributes, contentState: state, pushType: nil)
    }

    /// End the activity when the shift is no longer WORK_IN_PROGRESS.
    func end() {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<WorkActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
    }
    #else
    func sync(applicationId: String, jobTitle: String, startedAt: Date, hourlyRate: Double, earned: Double) {}
    func end() {}
    #endif
}
