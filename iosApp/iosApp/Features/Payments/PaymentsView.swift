import SwiftUI
import Shared

/// Employer Payments: 4 headline tiles + a list of payment rows (paid/pending),
/// each pending row offering "Pay now" (creates a Cashfree order and opens the
/// hosted checkout link). Mirrors the web app's PaymentsPage.
struct PaymentsView: View {

    @StateObject private var viewModel: PaymentsViewModel
    private let payments: any PaymentRepository
    private let employerId: String

    init(payments: any PaymentRepository, employerId: String, employerPhone: String, employerName: String) {
        self.payments = payments
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: PaymentsViewModel(
            payments: payments,
            employerId: employerId,
            employerPhone: employerPhone,
            employerName: employerName
        ))
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
                .navigationTitle(L("notification_channel_payments"))
                .drawerToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            PaymentHistoryView(payments: payments, employerId: employerId)
                        } label: { Image(systemName: "clock.arrow.circlepath") }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .alert("Payment error", isPresented: errorBinding) {
                    Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
                } message: { Text(viewModel.actionError ?? "") }
                .sheet(item: $viewModel.paymentLink) { link in
                    SafariSheet(url: link)
                }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded(let rows):
            let filteredRows = viewModel.filtered(rows)
            ScrollView {
                VStack(spacing: 16) {
                    summaryHero
                    filterChips

                    if rows.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "creditcard").font(.largeTitle).foregroundStyle(.secondary)
                            Text(L("ios_no_payments_yet")).font(.headline)
                            Text(L("ios_payments_appear_here_once_workers_comple"))
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 40)
                    } else if filteredRows.isEmpty {
                        Text(L("ios_no_payments_in_filter"))
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 30)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredRows, id: \.applicationId) { row in
                                PaymentRowCard(row: row, viewModel: viewModel)
                            }
                        }
                    }
                }
                .padding()
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    // Android "Payment Summary" green-gradient hero with a 2×2 tile grid.
    private var summaryHero: some View {
        let t = viewModel.totals
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "indianrupeesign.circle.fill").font(.title3)
                Text(L("payment_summary")).font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 12) {
                summaryTile(L("payment_total_paid"), Money.rupees(t.paidAmount, decimals: 0), .white)
                summaryTile(L("status_pending"), Money.rupees(t.pendingAmount, decimals: 0), GHTheme.hex(0xFDE68A))
                summaryTile(L("payment_this_month"), Money.rupees(t.thisMonthPaid, decimals: 0), .white)
                summaryTile(L("payment_total_txns"), "\(t.totalCount)", .white)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [GHTheme.hex(0x059669), GHTheme.hex(0x047857)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private func summaryTile(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(PaymentsViewModel.Filter.allCases) { f in
                let selected = viewModel.filter == f
                Button { viewModel.filter = f } label: {
                    Text(filterLabel(f))
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(selected ? GHTheme.tertiary : Color(.secondarySystemBackground), in: Capsule())
                        .foregroundStyle(selected ? .white : GHTheme.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func filterLabel(_ f: PaymentsViewModel.Filter) -> String {
        switch f {
        case .all: return L("filter_all")
        case .pending: return L("status_pending")
        case .completed: return L("status_completed")
        }
    }
}

private struct PaymentRowCard: View {
    let row: EmployerPaymentSummary
    @ObservedObject var viewModel: PaymentsViewModel

    private var isPaid: Bool { PaymentsViewModel.isPaid(row) }
    private var amount: Double {
        row.paymentAmount?.doubleValue ?? row.totalWagesCalculated?.doubleValue ?? 0
    }
    private var isBusy: Bool { viewModel.busyRowId == row.applicationId }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 44, height: 44)
                .overlay(Text(String((row.employeeName ?? row.jobTitle ?? "?").prefix(1)).uppercased())
                    .font(.headline.weight(.bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.jobTitle ?? "Gig").font(.subheadline.weight(.semibold))
                        .foregroundStyle(GHTheme.onBackground).lineLimit(1)
                    Spacer()
                    Text(isPaid ? L("status_completed") : L("status_pending"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((isPaid ? GHTheme.success : GHTheme.warning).opacity(0.14), in: Capsule())
                        .foregroundStyle(isPaid ? GHTheme.success : GHTheme.warning)
                }
                if let worker = row.employeeName {
                    Label(worker, systemImage: "person")
                        .font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.rupees(amount, decimals: 0))
                        .font(.title3.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                    Spacer()
                    if !isPaid {
                        Button {
                            Task { await viewModel.payNow(row) }
                        } label: {
                            if isBusy { ProgressView() } else { Text(L("status_help_pay_now")) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GHTheme.tertiary)
                        .controlSize(.small)
                        .disabled(isBusy)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }
}

/// `URL` is `Identifiable` via itself, so it can drive `sheet(item:)`.
extension URL: Identifiable {
    public var id: String { absoluteString }
}
