import Foundation
import Shared

/// Employee earnings — mirrors Android's EarningsViewModel data sources:
///   - DashboardRepository.getEmployeeStats → headline totals (total / pending /
///     this-month / completed jobs)
///   - ApplicationRepository.getEmployeeApplications (COMPLETED + PAYMENT_PENDING)
///     → the transaction list + the monthly chart, amount resolved from
///     paymentAmount → salaryRange.
/// (The payouts table is empty for most users; earnings live on the applications
/// / work sessions, which is why reading payouts alone showed all zeros.)
@MainActor
final class EarningsViewModel: ObservableObject {

    struct Stats {
        var total: Double = 0
        var pending: Double = 0
        var avgPerJob: Double = 0
        var thisMonth: Double = 0
        var lastMonth: Double = 0
        var pendingCount: Int = 0
        var completedCount: Int = 0
    }

    /// A derived earnings transaction (from an application).
    struct Txn: Identifiable {
        let id: String
        let title: String
        let employer: String?
        let amount: Double
        let date: String
        let completed: Bool
    }

    /// Matches Android's EarningsPeriod exactly — All Time, This Month, Last
    /// Month, Last 3 Months. (No "This Week" — it isn't an Android period.)
    enum Period: String, CaseIterable, Identifiable {
        case allTime = "All Time", thisMonth = "This Month"
        case lastMonth = "Last Month", last3Months = "Last 3 Months"
        var id: String { rawValue }

        /// Calendar-boundary membership test (mirrors Android isInPeriod).
        func contains(_ date: Date, now: Date = Date()) -> Bool {
            if self == .allTime { return true }
            let cal = Calendar.current
            let dc = cal.dateComponents([.year, .month], from: date)
            let nc = cal.dateComponents([.year, .month], from: now)
            switch self {
            case .allTime:
                return true
            case .thisMonth:
                return dc.year == nc.year && dc.month == nc.month
            case .lastMonth:
                let lm = cal.date(byAdding: .month, value: -1, to: now) ?? now
                let lc = cal.dateComponents([.year, .month], from: lm)
                return dc.year == lc.year && dc.month == lc.month
            case .last3Months:
                // First day of the month, 2 months ago → covers 3 calendar months.
                guard let twoAgo = cal.date(byAdding: .month, value: -2, to: now),
                      let cutoff = cal.dateInterval(of: .month, for: twoAgo)?.start
                else { return false }
                return date >= cutoff
            }
        }
    }

    @Published var period: Period = .allTime

    struct MonthBar: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
    }

    enum State { case idle, loading, loaded, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var stats = Stats()
    @Published private(set) var months: [MonthBar] = []
    @Published private(set) var transactions: [Txn] = []

    private let dashboard: any DashboardRepository
    private let applications: any ApplicationRepository
    private let employeeId: String

    init(dashboard: any DashboardRepository, applications: any ApplicationRepository, employeeId: String) {
        self.dashboard = dashboard
        self.applications = applications
        self.employeeId = employeeId
    }

    func load() async {
        state = .loading
        do {
            // Headline stats (best-effort; falls back to computed-from-txns).
            let statsRow = try? await IosHelpersKt.getEmployeeStatsOrThrow(dashboard, userId: employeeId)

            // Earning applications → transactions (COMPLETED + PAYMENT_PENDING).
            let apps = try await IosHelpersKt.getEmployeeApplicationsOrThrow(applications, employeeId: employeeId)
            let earning = apps.filter { $0.status == .completed || $0.status == .paymentPending }
            let txns = earning.map { app -> Txn in
                Txn(
                    id: app.id,
                    title: app.job?.title ?? "Job Payment",
                    employer: app.job?.employerProfile?.companyName,
                    amount: Self.resolveAmount(paymentAmount: app.paymentAmount?.doubleValue,
                                               salaryRange: app.job?.salaryRange),
                    date: app.paymentDate ?? app.updatedAt ?? app.createdAt ?? "",
                    completed: app.status == .completed
                )
            }.sorted { $0.date > $1.date }
            transactions = txns

            stats = Self.computeStats(stats: statsRow, txns: txns)
            months = Self.computeMonths(txns)
            state = .loaded
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    // MARK: - Period filtering (calendar-boundary, mirrors Android)

    /// The transactions visible for the selected period (the list is filtered,
    /// not just the hero number).
    var filteredTransactions: [Txn] {
        guard period != .allTime else { return transactions }
        return transactions.filter {
            guard let d = Self.parseDate($0.date) else { return false }
            return period.contains(d)
        }
    }

    /// The hero amount for the selected period = completed earnings within it.
    /// All Time / This Month trust the server stat; the rest sum the filtered
    /// completed transactions (matches Android).
    var periodEarnings: Double {
        switch period {
        case .allTime:
            return stats.total
        case .thisMonth:
            return stats.thisMonth > 0 ? stats.thisMonth : completedSum(filteredTransactions)
        case .lastMonth, .last3Months:
            return completedSum(filteredTransactions)
        }
    }

    private func completedSum(_ txns: [Txn]) -> Double {
        txns.filter { $0.completed }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Derivations

    private static func computeStats(stats: EmployeeDashboardStats?, txns: [Txn]) -> Stats {
        var s = Stats()
        let completed = txns.filter { $0.completed }
        let pending = txns.filter { !$0.completed }
        // Trust the server stats when present; else compute from transactions.
        s.total = stats.map { Double($0.totalEarnings) } ?? completed.reduce(0) { $0 + $1.amount }
        s.pending = stats.map { Double($0.pendingPayments) } ?? pending.reduce(0) { $0 + $1.amount }
        s.thisMonth = stats.map { Double($0.thisMonthEarnings) } ?? 0
        s.completedCount = stats.map { Int($0.completedJobs) } ?? completed.count
        s.pendingCount = pending.count
        s.avgPerJob = s.completedCount > 0 ? (s.total / Double(s.completedCount)).rounded() : 0
        // Last month, computed from transactions.
        if let lmStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()).flatMap({
            Calendar.current.dateInterval(of: .month, for: $0)?.start
        }), let lmEnd = Calendar.current.dateInterval(of: .month, for: Date())?.start {
            s.lastMonth = completed
                .filter {
                    guard let d = parseDate($0.date) else { return false }
                    return d >= lmStart && d < lmEnd
                }
                .reduce(0) { $0 + $1.amount }
        }
        return s
    }

    private static func computeMonths(_ txns: [Txn]) -> [MonthBar] {
        let cal = Calendar.current
        let now = Date()
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        let completed = txns.filter { $0.completed }
        return stride(from: 5, through: 0, by: -1).compactMap { offset in
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let key = monthKey(monthDate)
            let total = completed
                .filter { parseDate($0.date).map(monthKey) == key }
                .reduce(0.0) { $0 + $1.amount }
            return MonthBar(label: fmt.string(from: monthDate), amount: total)
        }
    }

    /// resolveAmount (Android): paymentAmount → parsed salaryRange tail.
    private static func resolveAmount(paymentAmount: Double?, salaryRange: String?) -> Double {
        if let a = paymentAmount, a > 0 { return a }
        if let sr = salaryRange, !sr.isEmpty {
            let cleaned = sr.replacingOccurrences(of: "₹", with: "")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
            let tail = cleaned.split(separator: "-").last.map(String.init) ?? cleaned
            let digits = tail.prefix { $0.isNumber }
            if let v = Double(digits) { return v }
        }
        return 0
    }

    private static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(raw.prefix(10)))
    }
}
