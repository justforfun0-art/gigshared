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

    private let dashboard: any DashboardRepository
    private let referralRepo: any ReferralRepository
    private let userId: String
    let isEmployer: Bool

    init(dashboard: any DashboardRepository,
         referralRepo: any ReferralRepository,
         userId: String,
         userType: String?) {
        self.dashboard = dashboard
        self.referralRepo = referralRepo
        self.userId = userId
        self.isEmployer = (userType?.lowercased() == "employer")
    }

    func load() async {
        // Load both concurrently; either failing leaves the other intact.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadStats() }
            group.addTask { await self.loadReferral() }
        }
    }

    private func loadStats() async {
        stats = .loading
        do {
            if isEmployer {
                let s = try await IosHelpersKt.getEmployerStatsOrThrow(dashboard, employerId: userId)
                stats = .employer(s)
            } else {
                let s = try await IosHelpersKt.getEmployeeStatsOrThrow(dashboard, userId: userId)
                stats = .employee(s)
            }
        } catch {
            stats = .failed((error as NSError).localizedDescription)
        }
    }

    private func loadReferral() async {
        referral = try? await IosHelpersKt.getReferralInfoOrThrow(referralRepo, userId: userId)
    }
}
