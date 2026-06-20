import Foundation
import Shared

/// Home dashboard over the shared `DashboardRepository` + `ReferralRepository`.
/// Loads role-appropriate stat tiles (employee vs employer) plus the referral
/// card (shared by both roles). Stats and referral load independently so one
/// failing doesn't blank the other.
@MainActor
final class DashboardViewModel: ObservableObject {

    enum Stats {
        case idle, loading
        case employee(EmployeeDashboardStats)
        case employer(EmployerDashboardStats)
        case failed(String)
    }

    @Published private(set) var stats: Stats = .idle
    @Published private(set) var referral: ReferralInfo?
    /// Employer hiring-health metrics (employer_insights); nil for employees / on failure.
    @Published private(set) var insights: EmployerInsights?
    /// Employer's most recent jobs (for the "Your Recent Jobs" dashboard section).
    @Published private(set) var recentJobs: [Job] = []

    private let dashboard: any DashboardRepository
    private let referralRepo: any ReferralRepository
    private let userId: String
    let isEmployer: Bool

    private let jobs: (any JobRepository)?

    init(dashboard: any DashboardRepository,
         referralRepo: any ReferralRepository,
         jobs: (any JobRepository)? = nil,
         userId: String,
         userType: String?) {
        self.dashboard = dashboard
        self.referralRepo = referralRepo
        self.jobs = jobs
        self.userId = userId
        self.isEmployer = (userType?.lowercased() == "employer")
    }

    func load() async {
        // Load both concurrently; either failing leaves the other intact.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadStats() }
            group.addTask { await self.loadReferral() }
            if self.isEmployer {
                group.addTask { await self.loadInsights() }
                group.addTask { await self.loadRecentJobs() }
            }
        }
    }

    /// Employer hiring-health (best-effort; getEmployerInsightsOrThrow is a
    /// SKIE-relocated instance method like the other Dashboard shims).
    private func loadInsights() async {
        insights = try? await dashboard.getEmployerInsightsOrThrow(employerId: userId)
    }

    /// Employer's recent jobs (newest first), for the dashboard section.
    private func loadRecentJobs() async {
        guard let jobs else { return }
        if let list = try? await IosHelpersKt.getEmployerJobsOrThrow(jobs, employerId: userId) {
            recentJobs = Array(list.prefix(3))
        }
    }

    private func loadStats() async {
        stats = .loading
        do {
            // NB: SKIE relocates these extension shims onto the receiver type
            // (DashboardRepository / ReferralRepository are SKIE-bridged because
            // they declare nested data classes), so they're called as instance
            // methods, not via IosHelpersKt like the other repos' shims.
            if isEmployer {
                let s = try await dashboard.getEmployerStatsOrThrow(employerId: userId)
                stats = .employer(s)
            } else {
                let s = try await dashboard.getEmployeeStatsOrThrow(userId: userId)
                stats = .employee(s)
            }
        } catch is CancellationError {
            // The .task was cancelled (tab switch / view update) — not a real
            // failure. Leave the prior state instead of flashing an error.
        } catch {
            // Kotlin/Native surfaces a cancelled coroutine as an NSError too;
            // ignore that as well so a cancelled load never shows as an error.
            if (error as NSError).isCancellation { return }
            stats = .failed((error as NSError).localizedDescription)
        }
    }

    private func loadReferral() async {
        referral = try? await referralRepo.getReferralInfoOrThrow(userId: userId)
    }
}

extension NSError {
    /// True when this error represents a cancelled task/coroutine — Swift
    /// CancellationError, the Cocoa user-cancelled code, or a Kotlin/Native
    /// JobCancellationException surfaced as an NSError.
    var isCancellation: Bool {
        if domain == NSCocoaErrorDomain && code == NSUserCancelledError { return true }
        let desc = localizedDescription.lowercased()
        return desc.contains("cancellation") || desc.contains("cancelled") || desc.contains("jobcancellation")
    }
}
