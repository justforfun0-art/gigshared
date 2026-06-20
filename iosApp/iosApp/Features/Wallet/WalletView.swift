import SwiftUI
import Shared

/// Wallet — port of Android's WalletScreen. A green balance hero (withdrawable /
/// pending), total + this-month tiles, an editable UPI id, and a link to the
/// Withdrawals history.
struct WalletView: View {
    let dashboard: any DashboardRepository
    let profileRepo: any ProfileRepository
    let payouts: any PayoutRepository
    let userId: String

    @StateObject private var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showWithdrawals = false

    init(dashboard: any DashboardRepository, profileRepo: any ProfileRepository,
         payouts: any PayoutRepository, userId: String) {
        self.dashboard = dashboard
        self.profileRepo = profileRepo
        self.payouts = payouts
        self.userId = userId
        _viewModel = StateObject(wrappedValue: WalletViewModel(
            dashboard: dashboard, profileRepo: profileRepo, userId: userId
        ))
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
                            balanceHero
                            tiles
                            upiCard
                            withdrawalsButton
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(L("wallet_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("close")) { dismiss() } } }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $showWithdrawals) { WithdrawalsView(payouts: payouts) }
        }
    }

    private var balanceHero: some View {
        VStack(spacing: 6) {
            Text(L("wallet_pending_balance").uppercased())
                .font(.caption2.weight(.bold)).kerning(0.6).foregroundStyle(.white.opacity(0.85))
            Text(Money.rupees(viewModel.pending))
                .font(.system(size: 36, weight: .heavy)).foregroundStyle(.white)
            Text(L("wallet_pending_hint")).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
    }

    private var tiles: some View {
        HStack(spacing: 12) {
            tile(L("total_earned"), Money.rupees(viewModel.totalEarnings), "indianrupeesign.circle.fill", GHTheme.tertiaryVariant)
            tile(L("this_month_label"), Money.rupees(viewModel.thisMonth), "calendar", GHTheme.primary)
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

    private var upiCard: some View {
        GHCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("wallet_upi_label"), systemImage: "qrcode").font(.headline)
                TextField("name@bank", text: $viewModel.upiId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                if viewModel.saveSuccess {
                    Label(L("wallet_upi_saved"), systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(GHTheme.success)
                }
                if let err = viewModel.error {
                    Text(err).font(.caption).foregroundStyle(GHTheme.error)
                }
                Button {
                    Task { await viewModel.saveUpi() }
                } label: {
                    HStack {
                        if viewModel.isSaving { ProgressView().tint(.white) }
                        Text(L("save")).font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(GHTheme.primary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSaving || viewModel.upiId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var withdrawalsButton: some View {
        Button { showWithdrawals = true } label: {
            HStack {
                Label(L("withdrawals_title"), systemImage: "list.bullet.rectangle")
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(GHTheme.onBackground).padding()
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(GHTheme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
