import SwiftUI
import Shared

/// Employer payment history — port of Android's PaymentHistoryScreen. An emerald
/// "Total Paid" summary hero over a list of completed payments (worker, job,
/// date, amount, last-8 of the transaction id). Reuses the employer payment
/// summary shim; shows only COMPLETED rows.
struct PaymentHistoryView: View {
    let payments: any PaymentRepository
    let employerId: String

    @StateObject private var viewModel: PaymentHistoryViewModel
    private var accent: Color { GHTheme.hex(0x059669) }

    init(payments: any PaymentRepository, employerId: String) {
        self.payments = payments
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: PaymentHistoryViewModel(payments: payments, employerId: employerId))
    }

    var body: some View {
        ZStack {
            GHTheme.pageGradient.ignoresSafeArea()
            content
        }
        .navigationTitle(L("payment_history"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.paid.isEmpty {
            ProgressView()
        } else if viewModel.paid.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "creditcard").font(.largeTitle).foregroundStyle(.secondary)
                Text(L("ios_no_payments_yet")).font(.headline)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    summaryHero
                    Text(L("all_payments_label")).font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(viewModel.paid, id: \.applicationId) { row in
                        PaymentHistoryRow(row: row, accent: accent)
                    }
                }
                .padding(16)
            }
        }
    }

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                Text(L("total_paid_label")).font(.headline).foregroundStyle(.white)
            }
            Text(Money.rupees(viewModel.totalPaid, decimals: 0))
                .font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            Text("\(viewModel.paid.count) payments").font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [GHTheme.hex(0x059669), GHTheme.hex(0x047857)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct PaymentHistoryRow: View {
    let row: EmployerPaymentSummary
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 48)
                .overlay(Text(String((row.employeeName ?? "W").prefix(2)).uppercased())
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.employeeName ?? "Worker").font(.subheadline.weight(.medium))
                    .foregroundStyle(GHTheme.onBackground).lineLimit(1)
                Text(row.jobTitle ?? "Job").font(.caption).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                HStack(spacing: 8) {
                    if let d = row.paymentDate { Text(String(d.prefix(10))).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant) }
                    Text(L("status_paid")).font(.caption2.weight(.semibold))
                        .foregroundStyle(GHTheme.hex(0x065F46))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(GHTheme.hex(0xD1FAE5), in: Capsule())
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.rupees(row.paymentAmount?.doubleValue ?? 0, decimals: 0))
                    .font(.subheadline.weight(.bold)).foregroundStyle(accent)
                if let txn = row.paymentTransactionId, txn.count > 0 {
                    Text("#\(String(txn.suffix(8)))").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
                }
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }
}

@MainActor
final class PaymentHistoryViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var paid: [EmployerPaymentSummary] = []

    private let payments: any PaymentRepository
    private let employerId: String

    init(payments: any PaymentRepository, employerId: String) {
        self.payments = payments
        self.employerId = employerId
    }

    var totalPaid: Double { paid.reduce(0) { $0 + ($1.paymentAmount?.doubleValue ?? 0) } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let rows = (try? await IosHelpersKt.getEmployerPaymentSummaryOrThrow(payments, employerId: employerId)) ?? []
        // History = completed payments only, newest first.
        paid = rows.filter { $0.applicationStatus?.uppercased() == "COMPLETED" }
            .sorted { ($0.paymentDate ?? "") > ($1.paymentDate ?? "") }
    }
}
