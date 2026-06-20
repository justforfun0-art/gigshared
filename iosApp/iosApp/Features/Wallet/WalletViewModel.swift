import Foundation
import Shared

/// Wallet — UPI management + headline balances (Android WalletViewModel). Reads
/// the profile (for UPI) + dashboard stats (total / this-month / pending), and
/// saves an edited UPI back to the profile.
@MainActor
final class WalletViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var totalEarnings: Double = 0
    @Published private(set) var thisMonth: Double = 0
    @Published private(set) var pending: Double = 0
    @Published var upiId: String = ""
    @Published var isSaving = false
    @Published var saveSuccess = false
    @Published var error: String?

    private let dashboard: any DashboardRepository
    private let profileRepo: any ProfileRepository
    private let userId: String
    private var profile: EmployeeProfile?

    init(dashboard: any DashboardRepository, profileRepo: any ProfileRepository, userId: String) {
        self.dashboard = dashboard
        self.profileRepo = profileRepo
        self.userId = userId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let p = try? await IosHelpersKt.getEmployeeProfileOrThrow(profileRepo, userId: userId) {
            profile = p
            if upiId.isEmpty { upiId = p.upiId ?? "" }
        }
        if let s = try? await dashboard.getEmployeeStatsOrThrow(userId: userId) {
            totalEarnings = Double(s.totalEarnings)
            thisMonth = Double(s.thisMonthEarnings)
            pending = Double(s.pendingPayments)
        }
    }

    func saveUpi() async {
        guard let profile else { return }
        isSaving = true; error = nil; saveSuccess = false
        defer { isSaving = false }
        do {
            let saved = try await IosHelpersKt.setUpiIdOrThrow(profileRepo, existing: profile, upiId: upiId)
            self.profile = saved
            saveSuccess = true
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
