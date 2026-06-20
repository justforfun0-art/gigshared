import Foundation
import Shared

/// Employer spending analytics, computed client-side from the employer's paid
/// applications (Android SpendingViewModel parity — no dedicated endpoint).
@MainActor
final class SpendingViewModel: ObservableObject {
    struct CategorySpend: Identifiable { let id = UUID(); let category: String; let amount: Double; let count: Int }
    struct RecentPayment: Identifiable { let id: String; let jobTitle: String; let amount: Double; let date: String }

    @Published private(set) var isLoading = true
    @Published private(set) var error: String?
    @Published private(set) var totalSpent = 0.0
    @Published private(set) var thisMonthSpent = 0.0
    @Published private(set) var lastMonthSpent = 0.0
    @Published private(set) var avgPerHire = 0.0
    @Published private(set) var pendingPayments = 0.0
    @Published private(set) var categories: [CategorySpend] = []
    @Published private(set) var recent: [RecentPayment] = []

    private let applications: any ApplicationRepository
    private let employerId: String

    init(applications: any ApplicationRepository, employerId: String) {
        self.applications = applications
        self.employerId = employerId
    }

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let all = try await IosHelpersKt.getEmployerApplicationsOrThrow(applications, employerId: employerId)
            let paid = all.filter { ($0.paymentAmount?.doubleValue ?? 0) > 0 && !( $0.paymentDate ?? "").isEmpty }

            totalSpent = paid.reduce(0) { $0 + ($1.paymentAmount?.doubleValue ?? 0) }
            avgPerHire = paid.isEmpty ? 0 : totalSpent / Double(paid.count)
            pendingPayments = all
                .filter { $0.status == .paymentPending }
                .reduce(0) { $0 + ($1.paymentAmount?.doubleValue ?? 0) }

            let cal = Calendar.current
            let now = Date()
            let thisMonth = cal.dateComponents([.year, .month], from: now)
            let lastMonth = cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: -1, to: now) ?? now)
            func monthOf(_ s: String?) -> DateComponents? {
                guard let d = s.flatMap(ActiveJobBarViewModel.parseISO) else { return nil }
                return cal.dateComponents([.year, .month], from: d)
            }
            thisMonthSpent = paid.filter { monthOf($0.paymentDate) == thisMonth }
                .reduce(0) { $0 + ($1.paymentAmount?.doubleValue ?? 0) }
            lastMonthSpent = paid.filter { monthOf($0.paymentDate) == lastMonth }
                .reduce(0) { $0 + ($1.paymentAmount?.doubleValue ?? 0) }

            categories = Dictionary(grouping: paid) { $0.job?.jobCategory ?? "Other" }
                .map { CategorySpend(category: $0.key,
                                     amount: $0.value.reduce(0) { $0 + ($1.paymentAmount?.doubleValue ?? 0) },
                                     count: $0.value.count) }
                .sorted { $0.amount > $1.amount }

            recent = paid
                .sorted { ($0.paymentDate ?? $0.updatedAt ?? "") > ($1.paymentDate ?? $1.updatedAt ?? "") }
                .prefix(10)
                .map { RecentPayment(id: $0.id, jobTitle: $0.job?.title ?? "Job",
                                     amount: $0.paymentAmount?.doubleValue ?? 0,
                                     date: $0.paymentDate ?? $0.updatedAt ?? "") }
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
