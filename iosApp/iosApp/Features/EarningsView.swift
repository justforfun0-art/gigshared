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
            content
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
            List {
                Section {
                    HStack {
                        stat("Total", amount: summary.totalAmount, color: .green)
                        Divider()
                        stat("Pending", amount: summary.pendingAmount, color: .orange)
                    }
                }
                Section("Payouts") {
                    if payouts.isEmpty {
                        Text("No payouts yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(payouts, id: \.id) { payout in
                            PayoutRow(payout: payout)
                        }
                    }
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button("Retry") { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func stat(_ label: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("₹\(Int(amount))").font(.title3.bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PayoutRow: View {
    let payout: Payout
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(payout.jobTitle ?? "Payout").font(.subheadline.weight(.medium))
                Text(payout.status.name.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("₹\(Int(payout.amount))").font(.subheadline.bold())
        }
    }
}
