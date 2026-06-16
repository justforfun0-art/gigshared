import SwiftUI
import Shared

/// Employer Payments: 4 headline tiles + a list of payment rows (paid/pending),
/// each pending row offering "Pay now" (creates a Cashfree order and opens the
/// hosted checkout link). Mirrors the web app's PaymentsPage.
struct PaymentsView: View {

    @StateObject private var viewModel: PaymentsViewModel

    init(payments: any PaymentRepository, employerId: String, employerPhone: String, employerName: String) {
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
            content
                .navigationTitle(L("notification_channel_payments"))
                .drawerToolbar()
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
            ScrollView {
                let t = viewModel.totals
                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(title: "Paid", value: "\(t.paidCount)", icon: "checkmark.seal", tint: .green)
                    StatTile(title: "Pending", value: "\(t.pendingCount)", icon: "hourglass", tint: .orange)
                    StatTile(title: "Paid amount", value: rupees(t.paidAmount), icon: "indianrupeesign.circle", tint: .green)
                    StatTile(title: "Pending amount", value: rupees(t.pendingAmount), icon: "indianrupeesign.circle", tint: .orange)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "creditcard").font(.largeTitle).foregroundStyle(.secondary)
                        Text(L("ios_no_payments_yet")).font(.headline)
                        Text(L("ios_payments_appear_here_once_workers_comple"))
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(rows, id: \.applicationId) { row in
                            PaymentRowCard(row: row, viewModel: viewModel)
                        }
                    }
                    .padding()
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func rupees(_ amount: Double) -> String {
        "₹" + String(format: "%.0f", amount)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.jobTitle ?? "Gig").font(.headline)
                Spacer()
                Text(isPaid ? "Paid" : "Pending")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((isPaid ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                    .foregroundStyle(isPaid ? .green : .orange)
            }
            if let worker = row.employeeName {
                Text(worker).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                Text("₹" + String(format: "%.0f", amount)).font(.title3.weight(.semibold))
                Spacer()
                if !isPaid {
                    Button {
                        Task { await viewModel.payNow(row) }
                    } label: {
                        if isBusy { ProgressView() } else { Text(L("status_help_pay_now")) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(value).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// `URL` is `Identifiable` via itself, so it can drive `sheet(item:)`.
extension URL: Identifiable {
    public var id: String { absoluteString }
}
