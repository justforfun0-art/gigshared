import SwiftUI
import Shared

/// Employer Spending analytics — port of Android's SpendingScreen. Total-spend
/// hero, this/last-month + avg-per-hire + pending tiles, spending-by-category
/// bars, and a recent-payments list.
struct SpendingView: View {
    let applications: any ApplicationRepository
    let employerId: String
    @StateObject private var viewModel: SpendingViewModel
    @Environment(\.dismiss) private var dismiss

    init(applications: any ApplicationRepository, employerId: String) {
        self.applications = applications
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: SpendingViewModel(applications: applications, employerId: employerId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                if viewModel.isLoading {
                    ProgressView("Loading…")
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            totalHero
                            tiles
                            if !viewModel.categories.isEmpty { categoryCard }
                            if !viewModel.recent.isEmpty { recentCard }
                            if let err = viewModel.error {
                                Text(err).font(.caption).foregroundStyle(GHTheme.error)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(L("spending"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("close")) { dismiss() } } }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var totalHero: some View {
        VStack(spacing: 6) {
            Text(L("total_spending_label").uppercased())
                .font(.caption2.weight(.bold)).kerning(0.6).foregroundStyle(.white.opacity(0.85))
            Text(Money.rupees(viewModel.totalSpent, decimals: 0))
                .font(.system(size: 34, weight: .heavy)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    private var tiles: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 12) {
            tile(L("this_month_label"), Money.rupees(viewModel.thisMonthSpent, decimals: 0), "calendar", GHTheme.primary)
            tile(L("last_month_label"), Money.rupees(viewModel.lastMonthSpent, decimals: 0), "calendar.badge.clock", GHTheme.hex(0x6B7280))
            tile(L("spending_avg_per_hire"), Money.rupees(viewModel.avgPerHire, decimals: 0), "person.fill", GHTheme.tertiaryVariant)
            tile(L("wallet_pending_balance"), Money.rupees(viewModel.pendingPayments, decimals: 0), "hourglass", GHTheme.warning)
        }
    }

    private func tile(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var categoryCard: some View {
        let maxAmount = viewModel.categories.map(\.amount).max() ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("spending_by_category")).font(.headline)
            ForEach(viewModel.categories) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.category.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline).lineLimit(1)
                        Spacer()
                        Text("\(Money.rupees(c.amount, decimals: 0)) · \(c.count)")
                            .font(.caption.weight(.semibold)).foregroundStyle(GHTheme.onSurfaceVariant)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(GHTheme.outline.opacity(0.4)).frame(height: 6)
                            Capsule().fill(GHTheme.tertiaryVariant)
                                .frame(width: geo.size.width * (c.amount / maxAmount), height: 6)
                        }
                    }.frame(height: 6)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GHTheme.outline, lineWidth: 1))
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("spending_recent_payments")).font(.headline)
            ForEach(viewModel.recent) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.jobTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(formatJobDate(p.date) ?? String(p.date.prefix(10)))
                            .font(.caption2).foregroundStyle(GHTheme.muted)
                    }
                    Spacer()
                    Text(Money.rupees(p.amount, decimals: 0))
                        .font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.tertiaryVariant)
                }
                if p.id != viewModel.recent.last?.id { Divider() }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GHTheme.outline, lineWidth: 1))
    }
}
