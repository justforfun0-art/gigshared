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
                    EarningsHero(amount: viewModel.periodEarnings,
                                 periodLabel: viewModel.period.rawValue,
                                 total: viewModel.stats.total,
                                 completedJobs: viewModel.stats.completedCount)
                    shareBanner
                    periodChips
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

    // MARK: - Share banner + period chips

    private var shareBanner: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(GHTheme.hex(0xA7F3D0))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "square.and.arrow.up").foregroundStyle(GHTheme.hex(0x065F46)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Share your win").font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.hex(0x065F46))
                Text("Tell friends you’re earning on GigHour")
                    .font(.caption).foregroundStyle(GHTheme.hex(0x047857))
            }
            Spacer()
            ShareLink(item: "I’ve earned ₹\(Int(viewModel.stats.total)) on GigHour! 🎉") {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(GHTheme.hex(0x065F46))
            }
        }
        .padding(14)
        .background(GHTheme.hex(0xD1FAE5), in: RoundedRectangle(cornerRadius: 14))
    }

    private var periodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EarningsViewModel.Period.allCases) { p in
                    let selected = viewModel.period == p
                    Text(p.rawValue)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .white : GHTheme.onSurfaceVariant)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(selected ? GHTheme.primary : Color(.systemBackground), in: Capsule())
                        .overlay(Capsule().stroke(selected ? .clear : GHTheme.outline, lineWidth: 1))
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { viewModel.period = p } }
                }
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

/// The prominent earnings hero: period label, a big animated green amount, a
/// divider, then a Total Earned + Completed jobs row (Android's EarningsHero).
private struct EarningsHero: View {
    let amount: Double
    let periodLabel: String
    let total: Double
    let completedJobs: Int

    private let green = GHTheme.hex(0x047857)
    @State private var shown: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(periodLabel).font(.title3).foregroundStyle(GHTheme.onSurfaceVariant)
            HStack(alignment: .top, spacing: 0) {
                Text("₹").font(.system(size: 36, weight: .bold)).foregroundStyle(green).padding(.top, 12)
                Text(shown.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 56, weight: .bold)).foregroundStyle(green)
                    .contentTransition(.numericText())
            }
            Divider().padding(.vertical, 12)
            HStack {
                heroStat("₹\(Int(total))", "Total Earned")
                Rectangle().fill(GHTheme.outline).frame(width: 1, height: 40)
                heroStat("\(completedJobs)", "Completed Jobs")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GHTheme.hex(0xF5F3FF), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { animate() }
        .onChange(of: amount) { _ in animate() }
    }

    private func animate() {
        shown = 0
        withAnimation(.easeOut(duration: 0.8)) { shown = amount }
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(GHTheme.onBackground)
            Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }
}

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
