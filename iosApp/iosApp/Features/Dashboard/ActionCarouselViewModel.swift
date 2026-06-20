import Foundation
import Shared

/// Loads the worker's *in-flight* applications — the ones that need attention
/// or are mid-lifecycle (SELECTED → PAYMENT_PENDING) — for the Home dashboard's
/// action-card carousel. Mirrors the Android dashboard's ActionCardCarousel,
/// which surfaces these front-and-center instead of making the worker dig into
/// the History/My-Applications list.
@MainActor
final class ActionCarouselViewModel: ObservableObject {

    /// The statuses that warrant an action card, in the order they should sort
    /// (most-urgent / latest-stage first), matching the web/Android dashboards.
    private static let order: [ApplicationStatus] = [
        .selected,            // new offer — accept it
        .otpRequested,        // employer shared OTP — start now
        .accepted,            // ready to start
        .workInProgress,      // working — complete it
        .completionPending,   // read code to employer
        .paymentPending       // waiting on payment
    ]

    @Published private(set) var items: [Application] = []
    @Published private(set) var isLoading = false
    @Published var actionError: String?
    @Published private(set) var busyId: String?
    /// WORK_IN_PROGRESS work-start timestamps, keyed by application id, fetched
    /// from each work session so the WIP card can run a live timer (the iOS
    /// Application model doesn't carry work_started_at).
    @Published private(set) var startTimes: [String: String] = [:]

    private let applications: any ApplicationRepository
    private let employeeId: String

    init(applications: any ApplicationRepository, employeeId: String) {
        self.applications = applications
        self.employeeId = employeeId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Server-filtered to the in-flight dashboard statuses (with a REST
            // fallback inside the repo), so the carousel doesn't pull the
            // worker's entire application history just to discard most of it.
            let all = try await IosHelpersKt.getActiveEmployeeApplicationsOrThrow(
                applications, employeeId: employeeId
            )
            items = all
                .filter { Self.order.contains($0.status) }
                .sorted { lhs, rhs in
                    let l = Self.order.firstIndex(of: lhs.status) ?? Int.max
                    let r = Self.order.firstIndex(of: rhs.status) ?? Int.max
                    if l != r { return l < r }
                    // Same stage → most-recently-updated first.
                    return (lhs.updatedAt ?? lhs.appliedAt ?? "") > (rhs.updatedAt ?? rhs.appliedAt ?? "")
                }
            await loadStartTimes()
        } catch {
            // Soft-fail: the carousel just stays hidden. The stats section below
            // surfaces its own load errors, so we don't double-report here.
            items = []
        }
    }

    /// Pull work-start timestamps for the WIP cards (best-effort).
    private func loadStartTimes() async {
        for app in items where app.status == .workInProgress {
            if let session = try? await IosHelpersKt.getWorkSessionOrThrow(applications, applicationId: app.id),
               let start = session.workStartTime {
                startTimes[app.id] = start
            }
        }
    }

    /// SELECTED → accept the offer (Android "accept"). Refreshes on success.
    func accept(_ app: Application) async {
        await run(app.id) {
            _ = try await IosHelpersKt.acceptSelectionOrThrow(self.applications, applicationId: app.id)
        }
        await load()
    }

    /// ACCEPTED → "Start Work": the worker generates the start OTP, which moves
    /// the application to OTP_REQUESTED (Android's requestStartWorkOtp). Returns
    /// the generated code so the UI can show the enter-OTP step next.
    @discardableResult
    func requestStartOtp(_ app: Application) async -> String? {
        var generated: String?
        await run(app.id) {
            generated = try await IosHelpersKt.generateStartOtpOrThrow(self.applications, applicationId: app.id)
        }
        await load()
        return generated
    }

    /// OTP_REQUESTED → submit the start OTP (Android "enter_otp" dialog).
    func submitStartOtp(_ app: Application, otp: String) async {
        let code = otp.trimmingCharacters(in: .whitespaces)
        guard code.count >= 4 else { actionError = "Enter the OTP from your employer"; return }
        await run(app.id) {
            _ = try await IosHelpersKt.verifyStartOtpOrThrow(self.applications, applicationId: app.id, otp: code)
        }
        await load()
    }

    /// COMPLETION_PENDING → read/generate the completion code (Android "show_code").
    /// Returns the code to show inline.
    func completionCode(_ app: Application) async -> String? {
        // Prefer the existing session code; generate if absent.
        if let session = try? await IosHelpersKt.getWorkSessionOrThrow(applications, applicationId: app.id),
           let code = session.completionOtp, !code.isEmpty {
            return code
        }
        return try? await IosHelpersKt.generateCompletionOtpOrThrow(applications, applicationId: app.id)
    }

    /// Regenerate an expired/used completion code (Android "New Code").
    func regenerateCompletionCode(_ app: Application) async -> String? {
        return try? await IosHelpersKt.regenerateCompletionOtpOrThrow(applications, applicationId: app.id)
    }

    private func run(_ id: String, _ op: @escaping () async throws -> Void) async {
        busyId = id; actionError = nil
        defer { busyId = nil }
        do { try await op() }
        catch { actionError = (error as NSError).localizedDescription }
    }
}
