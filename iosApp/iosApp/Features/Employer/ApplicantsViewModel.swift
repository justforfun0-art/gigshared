import Foundation
import Shared

/// Applicants for one job (employer view) + the hire/reject + work-OTP actions.
///
/// Work-session OTP loop, employer side (mirrors the web app):
///  - ACCEPTED            → generate the **start OTP**, read it to the worker.
///  - WORK_IN_PROGRESS    → the worker does the work and generates a completion
///    code; the employer waits.
///  - COMPLETION_PENDING  → the worker reads the completion code out; the
///    employer **types it in** here (`verifyCompletionOtp`) to finish the gig.
@MainActor
final class ApplicantsViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded([Application])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var actionError: String?
    /// A start OTP to show the employer after generate (they read it to the worker).
    @Published var presentedOtp: String?
    /// The application whose completion code the employer is currently typing in
    /// (drives the completion-entry sheet); nil when no sheet is shown.
    @Published var verifyingCompletion: Application?
    @Published var completionInput: String = ""
    @Published private(set) var isVerifying = false

    private let applications: any ApplicationRepository
    let jobId: String

    init(applications: any ApplicationRepository, jobId: String) {
        self.applications = applications
        self.jobId = jobId
    }

    func load() async {
        state = .loading
        do {
            let list = try await IosHelpersKt.getApplicationsForJobOrThrow(applications, jobId: jobId)
            state = .loaded(list)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    func select(_ app: Application) async { await run { _ = try await IosHelpersKt.selectApplicantOrThrow(self.applications, applicationId: app.id) } }
    func reject(_ app: Application) async { await run { _ = try await IosHelpersKt.rejectApplicantOrThrow(self.applications, applicationId: app.id, reason: nil) } }

    func generateStartOtp(_ app: Application) async {
        await runOtp { try await IosHelpersKt.generateStartOtpOrThrow(self.applications, applicationId: app.id) }
    }

    /// Open the completion-code entry sheet for an application in COMPLETION_PENDING.
    func beginCompletionVerify(_ app: Application) {
        completionInput = ""
        actionError = nil
        verifyingCompletion = app
    }

    /// Submit the completion code the worker read out. On success the gig moves
    /// to PAYMENT_PENDING / COMPLETED and the list refreshes.
    func submitCompletionCode() async {
        guard let app = verifyingCompletion else { return }
        let code = completionInput.trimmingCharacters(in: .whitespaces)
        guard code.count == 6 else { actionError = "Enter the 6-digit code the worker gave you"; return }
        isVerifying = true; actionError = nil
        defer { isVerifying = false }
        do {
            _ = try await IosHelpersKt.verifyCompletionOtpOrThrow(self.applications, applicationId: app.id, otp: code)
            verifyingCompletion = nil
            completionInput = ""
            await load()
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private func run(_ op: () async throws -> Void) async {
        actionError = nil
        do { try await op(); await load() }
        catch { actionError = (error as NSError).localizedDescription }
    }

    private func runOtp(_ op: () async throws -> String) async {
        actionError = nil
        do { presentedOtp = try await op(); await load() }
        catch { actionError = (error as NSError).localizedDescription }
    }
}
