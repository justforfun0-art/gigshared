import Foundation
import Shared

/// Employee earnings over the shared `PayoutRepository`. Loads the payout page
/// (summary + payouts), then derives the Android-style stats (avg per job, this/
/// last month, monthly chart) client-side from the payout list.
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

    /// One month's bar for the trend chart.
    struct MonthBar: Identifiable {
        let id = UUID()
        let label: String       // "Jun"
        let amount: Double
    }

    enum State {
        case idle, loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var stats = Stats()
    @Published private(set) var months: [MonthBar] = []
    @Published private(set) var payouts: [Payout] = []

    private let payoutsRepo: any PayoutRepository

    init(payouts: any PayoutRepository) {
        self.payoutsRepo = payouts
    }

    func load() async {
        state = .loading
        do {
            let page = try await IosHelpersKt.getHistoryOrThrow(payoutsRepo, status: nil, limit: 100, offset: 0)
            let rows = page.payouts
            payouts = rows.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            stats = Self.computeStats(summary: page.summary, payouts: rows)
            months = Self.computeMonths(rows)
            state = .loaded
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    private static func computeStats(summary: PayoutSummary, payouts: [Payout]) -> Stats {
        var s = Stats()
        s.total = summary.totalAmount
        s.pending = summary.pendingAmount
        s.pendingCount = Int(summary.scheduledCount) + Int(summary.processingCount)
        s.completedCount = Int(summary.successCount)
        s.avgPerJob = s.completedCount > 0 ? s.total / Double(s.completedCount) : 0

        let now = Date()
        let cal = Calendar.current
        let thisMonthKey = monthKey(now)
        let lastMonthKey = monthKey(cal.date(byAdding: .month, value: -1, to: now) ?? now)
        for p in payouts where p.status == .success {
            guard let d = parseDate(p.completedAt ?? p.createdAt) else { continue }
            let k = monthKey(d)
            if k == thisMonthKey { s.thisMonth += p.amount }
            if k == lastMonthKey { s.lastMonth += p.amount }
        }
        return s
    }

    /// Last 6 months of successful-payout totals, oldest → newest.
    private static func computeMonths(_ payouts: [Payout]) -> [MonthBar] {
        let cal = Calendar.current
        let now = Date()
        var bars: [MonthBar] = []
        let monthFmt = DateFormatter(); monthFmt.dateFormat = "MMM"
        for offset in stride(from: 5, through: 0, by: -1) {
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let key = monthKey(monthDate)
            let total = payouts
                .filter { $0.status == .success }
                .filter { parseDate($0.completedAt ?? $0.createdAt).map(monthKey) == key }
                .reduce(0.0) { $0 + $1.amount }
            bars.append(MonthBar(label: monthFmt.string(from: monthDate), amount: total))
        }
        return bars
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
