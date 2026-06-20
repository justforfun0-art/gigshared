import Foundation
import Shared

/// Employer payments over the shared `PaymentRepository`. Loads every payment
/// row for the employer from the `employer_payment_summary` view (one query),
/// derives the 4 headline tiles, and wires order-create + verify.
///
/// The actual Cashfree checkout is a native per-platform SDK and is out of
/// scope here; `payNow` creates the order and hands back the hosted payment
/// link (opened in Safari), and `verify` polls order status afterward — the
/// portable half of the flow.
@MainActor
final class PaymentsViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded([EmployerPaymentSummary])
        case failed(String)
    }

    struct Totals {
        var paidCount = 0
        var pendingCount = 0
        var paidAmount = 0.0
        var pendingAmount = 0.0
        var thisMonthPaid = 0.0
        var totalCount = 0
    }

    enum Filter: String, CaseIterable, Identifiable { case all = "All", pending = "Pending", completed = "Completed"; var id: String { rawValue } }

    @Published private(set) var state: State = .idle
    @Published var filter: Filter = .all
    @Published var actionError: String?
    /// A hosted Cashfree payment link to open after `payNow` succeeds.
    @Published var paymentLink: URL?
    @Published private(set) var busyRowId: String?

    private let payments: any PaymentRepository
    private let employerId: String
    /// The employer's own phone (the payer) — the server validates it as exactly
    /// 10 digits, and the payment-summary view doesn't carry it, so it comes
    /// from the session.
    private let employerPhone: String
    private let employerName: String

    init(payments: any PaymentRepository, employerId: String, employerPhone: String, employerName: String) {
        self.payments = payments
        self.employerId = employerId
        self.employerPhone = employerPhone
        self.employerName = employerName
    }

    func load() async {
        state = .loading
        do {
            let rows = try await IosHelpersKt.getEmployerPaymentSummaryOrThrow(payments, employerId: employerId)
            state = .loaded(rows)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    /// Paid = application COMPLETED; everything else with a work session pending.
    var totals: Totals {
        guard case let .loaded(rows) = state else { return Totals() }
        var t = Totals()
        t.totalCount = rows.count
        let cal = Calendar.current
        let thisMonth = cal.dateComponents([.year, .month], from: Date())
        for row in rows {
            let amount = row.paymentAmount?.doubleValue
                ?? row.totalWagesCalculated?.doubleValue ?? 0
            if Self.isPaid(row) {
                t.paidCount += 1
                t.paidAmount += amount
                if let d = (row.paymentDate ?? row.completedAt).flatMap(ActiveJobBarViewModel.parseISO),
                   cal.dateComponents([.year, .month], from: d) == thisMonth {
                    t.thisMonthPaid += amount
                }
            } else {
                t.pendingCount += 1
                t.pendingAmount += amount
            }
        }
        return t
    }

    /// Rows filtered by the All / Pending / Completed chip.
    func filtered(_ rows: [EmployerPaymentSummary]) -> [EmployerPaymentSummary] {
        switch filter {
        case .all: return rows
        case .pending: return rows.filter { !Self.isPaid($0) }
        case .completed: return rows.filter { Self.isPaid($0) }
        }
    }

    static func isPaid(_ row: EmployerPaymentSummary) -> Bool {
        row.applicationStatus?.uppercased() == "COMPLETED"
    }

    /// Create a Cashfree order for a pending row and surface the hosted link.
    func payNow(_ row: EmployerPaymentSummary) async {
        guard let employeeId = row.employeeId else {
            actionError = "Missing worker for this payment."
            return
        }
        let amount = row.paymentAmount?.doubleValue
            ?? row.totalWagesCalculated?.doubleValue ?? 0
        guard amount > 0 else { actionError = "Nothing to pay on this row yet."; return }

        busyRowId = row.applicationId
        actionError = nil
        defer { busyRowId = nil }
        do {
            let order = try await IosHelpersKt.createOrderOrThrow(
                payments,
                applicationId: row.applicationId,
                amount: amount,
                employerId: employerId,
                employeeId: employeeId,
                customerName: employerName,
                customerPhone: employerPhone,
                customerEmail: nil
            )
            paymentLink = URL(string: order.paymentLink)
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    /// Poll order status after returning from checkout; refresh on success.
    func verify(orderId: String) async {
        actionError = nil
        do {
            let result = try await IosHelpersKt.verifyPaymentOrThrow(payments, orderId: orderId)
            if result.success {
                await load()
            } else {
                actionError = "Payment not completed yet (\(result.orderStatus ?? "pending"))."
            }
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }
}
