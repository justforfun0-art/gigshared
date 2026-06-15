import SwiftUI
import Shared

/// Employee earnings — port of Android's EarningsScreen: two big stat cards
/// (Total / Pending), three mini stat cards (Avg per job / Last month / Pending
/// count), a monthly-earnings bar chart, and the transaction list.
struct EarningsView: View {

    @StateObject private var viewModel: EarningsViewModel

    init(payouts: any PayoutRepository) {
        _viewModel = StateObject(wrappedValue: EarningsViewModel(payouts: payouts))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle("Earnings")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded:
            ScrollView {
                VStack(spacing: 16) {
                    bigStats
                    miniStats
                    if viewModel.months.contains(where: { $0.amount > 0 }) {
                        chartCard
                    }
                    transactionsSection
                }
                .padding()
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent).tint(GHTheme.primary)
            }
        }
    }

    // MARK: - Stat cards

    private var bigStats: some View {
        HStack(spacing: 12) {
            BigStatCard(value: rupees(viewModel.stats.total), label: "All time",
                        icon: "wallet.pass.fill",
                        accent: GHTheme.primary, tint: GHTheme.hex(0xEDE9FE))
            BigStatCard(value: rupees(viewModel.stats.pending), label: "Pending",
                        icon: "clock.fill",
                        accent: GHTheme.warning, tint: GHTheme.hex(0xFEF3C7))
        }
    }

    private var miniStats: some View {
        HStack(spacing: 12) {
            MiniStatCard(value: rupees(viewModel.stats.avgPerJob), label: "Avg / job",
                         icon: "chart.line.uptrend.xyaxis",
                         accent: GHTheme.primary, tint: GHTheme.hex(0xEDE9FE))
            MiniStatCard(value: rupees(viewModel.stats.lastMonth), label: "Last month",
                         icon: "calendar",
                         accent: GHTheme.info, tint: GHTheme.hex(0xDBEAFE))
            MiniStatCard(value: "\(viewModel.stats.pendingCount)", label: "Pending",
                         icon: "clock", showRupee: false,
                         accent: GHTheme.warning, tint: GHTheme.hex(0xFEF3C7))
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earnings trend").font(.headline).foregroundStyle(GHTheme.onBackground)
            MonthlyBarChart(months: viewModel.months)
                .frame(height: 160)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transactions").font(.headline).foregroundStyle(GHTheme.onBackground)
                .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.payouts.isEmpty {
                GHCard {
                    HStack {
                        Image(systemName: "indianrupeesign.circle").foregroundStyle(GHTheme.muted)
                        Text("No transactions yet").foregroundStyle(GHTheme.onSurfaceVariant)
                    }
                }
            } else {
                ForEach(viewModel.payouts, id: \.id) { TransactionCard(payout: $0) }
            }
        }
    }

    private func rupees(_ amount: Double) -> String {
        "₹" + amount.formatted(.number.precision(.fractionLength(0)))
    }
}

// MARK: - Components

private struct BigStatCard: View {
    let value: String; let label: String; let icon: String
    let accent: Color; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.6))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: icon).foregroundStyle(accent))
            Text(value).font(.title2.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MiniStatCard: View {
    let value: String; let label: String; let icon: String
    var showRupee: Bool = true
    let accent: Color; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(accent)
            Text(value).font(.headline).foregroundStyle(GHTheme.onBackground)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A simple vertical bar chart for the monthly trend.
private struct MonthlyBarChart: View {
    let months: [EarningsViewModel.MonthBar]
    private var maxAmount: Double { max(months.map(\.amount).max() ?? 1, 1) }

    var body: some View {
        GeometryReader { geo in
            let barW = (geo.size.width / CGFloat(max(months.count, 1))) * 0.5
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(months) { m in
                    VStack(spacing: 6) {
                        Text(m.amount > 0 ? "₹\(Int(m.amount))" : "")
                            .font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [GHTheme.primaryLight, GHTheme.primary],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: barW,
                                   height: max(4, CGFloat(m.amount / maxAmount) * (geo.size.height - 44)))
                        Text(m.label).font(.caption2).foregroundStyle(GHTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct TransactionCard: View {
    let payout: Payout
    private var isPending: Bool { payout.status != .success }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill((isPending ? GHTheme.warning : GHTheme.tertiary).opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: isPending ? "clock.fill" : "checkmark")
                    .foregroundStyle(isPending ? GHTheme.warning : GHTheme.tertiaryVariant))
            VStack(alignment: .leading, spacing: 2) {
                Text(payout.jobTitle ?? "Payout")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                Text(payout.status.name.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            Spacer()
            Text("₹\(Int(payout.amount))")
                .font(.headline)
                .foregroundStyle(isPending ? GHTheme.warning : GHTheme.tertiaryVariant)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GHTheme.hex(0xF3F4F6), lineWidth: 1))
    }
}
