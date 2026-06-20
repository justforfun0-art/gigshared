import Foundation
import Shared

/// Backs the in-app floating "live job progress" bar (iOS counterpart of
/// Android's LiveJobProgressNotification WORKING card). Finds the worker's
/// single WORK_IN_PROGRESS application and resolves its work-start time + hourly
/// rate so the bar can show a live timer + earned-so-far. Polls on a light
/// cadence so it appears/disappears as the worker starts/finishes a shift.
@MainActor
final class ActiveJobBarViewModel: ObservableObject {

    struct ActiveJob: Equatable {
        let applicationId: String
        let title: String
        let startedAt: Date
        let hourlyRate: Double   // ₹/hr; 0 when unknown (bar hides earnings)
    }

    @Published private(set) var job: ActiveJob?

    private let applications: any ApplicationRepository
    private let employeeId: String

    init(applications: any ApplicationRepository, employeeId: String) {
        self.applications = applications
        self.employeeId = employeeId
    }

    func refresh() async {
        do {
            let all = try await IosHelpersKt.getActiveEmployeeApplicationsOrThrow(
                applications, employeeId: employeeId
            )
            guard let wip = all.first(where: { $0.status == .workInProgress }) else {
                job = nil
                LiveWorkActivityManager.shared.end()   // shift over → end Live Activity
                return
            }
            let session = try? await IosHelpersKt.getWorkSessionOrThrow(applications, applicationId: wip.id)
            guard let startStr = session?.workStartTime, let started = Self.parseISO(startStr) else {
                job = nil
                LiveWorkActivityManager.shared.end()
                return
            }
            let rate = session?.hourlyRateUsed?.doubleValue
                ?? Self.rateFromSalary(wip.job?.salaryRange) ?? 0
            let resolved = ActiveJob(
                applicationId: wip.id,
                title: wip.job?.title ?? "Current job",
                startedAt: started,
                hourlyRate: rate
            )
            job = resolved
            // Start/update the Lock Screen / Dynamic Island Live Activity.
            let earned = rate * (max(Date().timeIntervalSince(started), 0) / 3600.0)
            LiveWorkActivityManager.shared.sync(
                applicationId: resolved.applicationId, jobTitle: resolved.title,
                startedAt: resolved.startedAt, hourlyRate: rate, earned: earned
            )
        } catch {
            // Soft-fail: bar just stays hidden.
            job = nil
        }
    }

    /// Leading number in a free-text salary_range ("₹250/hour", "300") → rate.
    private static func rateFromSalary(_ s: String?) -> Double? {
        guard let s else { return nil }
        let digits = s.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    static func parseISO(_ raw: String) -> Date? {
        // Postgres returns "2026-06-18 16:24:01.720963+00" — space separator,
        // microseconds, "+00" offset. Normalize the space → 'T' and the trailing
        // "+00"/"-05" → "+00:00", then try ISO8601 (with/without fractional) and
        // a couple of explicit DateFormatter patterns as fallbacks.
        var s = raw.replacingOccurrences(of: " ", with: "T")
        // Expand a 3-char trailing offset like "+00" to "+00:00".
        if s.count >= 3 {
            let tail = s.suffix(3)
            if (tail.first == "+" || tail.first == "-"),
               tail.dropFirst().allSatisfy({ $0.isNumber }) {
                s += ":00"
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}
