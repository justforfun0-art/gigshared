import SwiftUI
import Shared

/// Withdrawals (payout history) — port of Android's WithdrawalsScreen. A paged,
/// status-filterable list of the worker's payouts from PayoutRepository.getHistory.
struct WithdrawalsView: View {
    let payouts: any PayoutRepository
    @StateObject private var viewModel: WithdrawalsViewModel
    @Environment(\.dismiss) private var dismiss

    init(payouts: any PayoutRepository) {
        self.payouts = payouts
        _viewModel = StateObject(wrappedValue: WithdrawalsViewModel(payouts: payouts))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterBar
                    content
                }
            }
            .navigationTitle(L("withdrawals_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("close")) { dismiss() } }
            }
            .task { await viewModel.load(reset: true) }
            .refreshable { await viewModel.load(reset: true) }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, L("filter_all"))
                chip(.scheduled, "Scheduled")
                chip(.processing, "Processing")
                chip(.success, "Success")
                chip(.failed, "Failed")
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func chip(_ status: PayoutStatus?, _ label: String) -> some View {
        let selected = viewModel.filter == status
        return Button {
            viewModel.filter = status
            Task { await viewModel.load(reset: true) }
        } label: {
            Text(label).font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : GHTheme.onSurfaceVariant)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(selected ? GHTheme.primary : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading where viewModel.items.isEmpty:
            Spacer(); ProgressView("Loading…"); Spacer()
        case .failed(let msg):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(msg).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        default:
            if viewModel.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "indianrupeesign.circle").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L("withdrawals_empty")).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.items, id: \.id) { PayoutRow(payout: $0) }
                        if viewModel.hasMore {
                            ProgressView().padding()
                                .task { await viewModel.load(reset: false) }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

private struct PayoutRow: View {
    let payout: Payout

    var body: some View {
        GHCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Money.rupees(payout.amount)).font(.headline).foregroundStyle(GHTheme.onBackground)
                        if let title = payout.jobTitle, !title.isEmpty {
                            Text(title).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                        }
                    }
                    Spacer()
                    statusPill
                }
                if let bene = payout.beneficiary {
                    Label(bene.upiId ?? bene.bankName ?? bene.name ?? "—", systemImage: "creditcard")
                        .font(.caption).foregroundStyle(GHTheme.muted).lineLimit(1)
                }
                if let utr = payout.utr, !utr.isEmpty {
                    Text("UTR: \(utr)").font(.caption2.monospaced()).foregroundStyle(GHTheme.muted)
                }
                if payout.status == .failed, let reason = payout.failureReason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(GHTheme.error)
                }
                if let when = payout.completedAt ?? payout.processedAt ?? payout.createdAt {
                    Text(formatJobDate(when) ?? when.prefix10).font(.caption2).foregroundStyle(GHTheme.muted)
                }
            }
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch payout.status {
            case .success: return ("Success", GHTheme.success)
            case .processing, .scheduled: return (payout.status == .processing ? "Processing" : "Scheduled", GHTheme.warning)
            case .failed, .reversed, .cancelled: return (payout.status.name.capitalized, GHTheme.error)
            default: return ("—", GHTheme.muted)
            }
        }()
        return Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private extension String { var prefix10: String { String(prefix(10)) } }
