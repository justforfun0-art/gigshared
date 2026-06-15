import SwiftUI
import Shared

/// Employee earnings: a total/pending summary + payout history list.
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
        case .loaded(let summary, let payouts):
            ScrollView {
                VStack(spacing: 16) {
                    summaryHero(summary)
                    if payouts.isEmpty {
                        emptyPayouts
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Payouts").font(.headline).foregroundStyle(GHTheme.onBackground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(payouts, id: \.id) { payout in
                                PayoutRow(payout: payout)
                            }
                        }
                    }
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

    /// Violet hero card with total + pending side by side.
    private func summaryHero(_ summary: PayoutSummary) -> some View {
        HStack(spacing: 0) {
            heroStat("Total earned", amount: summary.totalAmount)
            Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 44)
            heroStat("Pending", amount: summary.pendingAmount)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(GHTheme.heroGradient, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: GHTheme.primary.opacity(0.25), radius: 10, y: 4)
    }

    private func heroStat(_ label: String, amount: Double) -> some View {
        VStack(spacing: 4) {
            Text("₹\(Int(amount))").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyPayouts: some View {
        GHCard {
            HStack {
                Image(systemName: "indianrupeesign.circle").foregroundStyle(GHTheme.muted)
                Text("No payouts yet").foregroundStyle(GHTheme.onSurfaceVariant)
            }
        }
    }
}

private struct PayoutRow: View {
    let payout: Payout
    var body: some View {
        GHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payout.jobTitle ?? "Payout")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GHTheme.onBackground)
                    Text(payout.status.name.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                Spacer()
                Text("₹\(Int(payout.amount))")
                    .font(.headline)
                    .foregroundStyle(GHTheme.tertiaryVariant)
            }
        }
    }
}
