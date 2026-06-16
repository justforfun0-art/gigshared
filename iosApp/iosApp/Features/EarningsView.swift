import SwiftUI
import Shared

/// Employee earnings — port of Android's EarningsScreen: two big stat cards
/// (Total / Pending), three mini stat cards (Avg per job / Last month / Pending
/// count), a monthly-earnings bar chart, and the transaction list.
struct EarningsView: View {

    @StateObject private var viewModel: EarningsViewModel
    @State private var selectedTxn: EarningsViewModel.Txn?

    init(dashboard: any DashboardRepository, applications: any ApplicationRepository, employeeId: String) {
        _viewModel = StateObject(wrappedValue: EarningsViewModel(
            dashboard: dashboard, applications: applications, employeeId: employeeId
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle("Earnings")
            .drawerToolbar()
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $selectedTxn) { txn in
                TransactionDetailSheet(txn: txn)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
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
            let txns = viewModel.filteredTransactions
            if txns.isEmpty {
                GHCard {
                    HStack {
                        Image(systemName: "indianrupeesign.circle").foregroundStyle(GHTheme.muted)
                        Text("No transactions in this period").foregroundStyle(GHTheme.onSurfaceVariant)
                    }
                }
            } else {
                ForEach(txns) { txn in
                    TransactionCard(txn: txn)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTxn = txn }
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(periodLabel).font(.title3).foregroundStyle(GHTheme.onSurfaceVariant)
            HStack(alignment: .top, spacing: 0) {
                Text("₹").font(.system(size: 36, weight: .bold)).foregroundStyle(green).padding(.top, 12)
                // Show the exact period amount (no count-up animation — that made
                // the number look "different" mid-animation). A numeric content
                // transition gives a clean swap when the period changes.
                Text(amount.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 56, weight: .bold)).foregroundStyle(green)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: amount)
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
    let txn: EarningsViewModel.Txn
    private var isPending: Bool { !txn.completed }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill((isPending ? GHTheme.warning : GHTheme.tertiary).opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: isPending ? "clock.fill" : "checkmark")
                    .foregroundStyle(isPending ? GHTheme.warning : GHTheme.tertiaryVariant))
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.title)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                Text(isPending ? "Payment pending" : "Completed")
                    .font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            Spacer()
            Text("₹\(Int(txn.amount))")
                .font(.headline)
                .foregroundStyle(isPending ? GHTheme.warning : GHTheme.tertiaryVariant)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GHTheme.hex(0xF3F4F6), lineWidth: 1))
    }
}

/// Half-sheet transaction detail (port of Android's TransactionDetailsSheet):
/// title, a big colored amount, a status pill, then Job / Employer / Date rows.
private struct TransactionDetailSheet: View {
    let txn: EarningsViewModel.Txn
    @Environment(\.dismiss) private var dismiss

    private var pending: Bool { !txn.completed }
    private var amountColor: Color { pending ? GHTheme.warning : GHTheme.tertiary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transaction Details")
                .font(.title2.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                .padding(.top, 8)

            Text("+₹\(Int(txn.amount))")
                .font(.system(size: 36, weight: .bold)).foregroundStyle(amountColor)
                .padding(.top, 20)

            // Status pill.
            Text(pending ? "Payment Pending" : "Completed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pending ? GHTheme.hex(0xB45309) : GHTheme.hex(0x065F46))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(pending ? GHTheme.hex(0xFEF3C7) : GHTheme.hex(0xD1FAE5), in: Capsule())
                .padding(.top, 6)

            VStack(spacing: 0) {
                detailRow("Job", txn.title)
                if let employer = txn.employer, !employer.isEmpty {
                    Divider()
                    detailRow("Employer", employer)
                }
                Divider()
                detailRow("Date", formattedDate)
            }
            .padding(.top, 24)

            Spacer()
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    private var formattedDate: String {
        guard !txn.date.isEmpty else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: txn.date) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: txn.date)
        }()
        guard let date else { return String(txn.date.prefix(10)) }
        let out = DateFormatter(); out.dateFormat = "d MMM yyyy, h:mm a"
        return out.string(from: date)
    }
}
