import Foundation
import os
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Subsystem logger so on-device Live Activity behaviour is visible in Console
/// (filter by subsystem "com.gighour.liveactivity"). Diagnoses why the Dynamic
/// Island may not appear: disabled by user, unsupported OS, or a request error.
private let laLog = Logger(subsystem: "com.gighour.liveactivity", category: "WIP")

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
        guard #available(iOS 16.1, *) else {
            laLog.error("sync skipped: iOS < 16.1 (Live Activities unavailable)")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Most common reason the Dynamic Island never appears on a real device.
            laLog.error("sync skipped: Live Activities DISABLED (Settings → GigHour → Live Activities, or system-wide)")
            return
        }
        let state = WorkActivityAttributes.ContentState(earned: earned, hourlyRate: hourlyRate)

        if let activity = current {
            // Same shift → update; different shift → restart.
            if activity.attributes.applicationId == applicationId {
                laLog.info("update existing activity \(activity.id, privacy: .public) for app \(applicationId, privacy: .public)")
                Task { await activity.update(using: state) }
                return
            }
            laLog.info("ending stale activity (different shift) before starting new one")
            Task { await activity.end(using: state, dismissalPolicy: .immediate) }
        }
        let attributes = WorkActivityAttributes(
            jobTitle: jobTitle, startedAt: startedAt, applicationId: applicationId
        )
        do {
            let activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            laLog.info("STARTED Live Activity \(activity.id, privacy: .public) for \"\(jobTitle, privacy: .public)\"")
        } catch {
            laLog.error("Activity.request FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// End the activity when the shift is no longer WORK_IN_PROGRESS.
    func end() {
        guard #available(iOS 16.1, *) else { return }
        let activities = Activity<WorkActivityAttributes>.activities
        if !activities.isEmpty {
            laLog.info("ending \(activities.count, privacy: .public) Live Activity(ies) (shift no longer WIP)")
        }
        for activity in activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
    }
    #else
    func sync(applicationId: String, jobTitle: String, startedAt: Date, hourlyRate: Double, earned: Double) {}
    func end() {}
    #endif
}
