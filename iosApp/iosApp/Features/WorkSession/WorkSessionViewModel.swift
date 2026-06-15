import Foundation
import Shared

/// Drives the worker's side of the work-session OTP loop for one application
/// (mirrors the web app's employee application page):
///
///  - SELECTED               → worker accepts the offer (`acceptSelection`) → ACCEPTED.
///  - ACCEPTED / OTP_REQUESTED → worker types the **start OTP** the employer
///    generated (`verifyStartOtp`) → WORK_IN_PROGRESS.
///  - WORK_IN_PROGRESS       → worker taps **Complete work**, which *generates*
///    the completion code (`generateCompletionOtp`) → COMPLETION_PENDING.
///  - COMPLETION_PENDING     → worker reads the completion code to the employer
///    (who types it back to finish). Worker may **regenerate** it if it expired.
///
/// The screen reloads the application after each action so the rendered stage
/// follows the server's status.
@MainActor
final class WorkSessionViewModel: ObservableObject {

    @Published private(set) var application: Application
    @Published var otpInput: String = ""
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    /// The completion code the worker generated (shown so they can read it to
    /// the employer), present once COMPLETION_PENDING.
    @Published private(set) var completionCode: String?

    private let applications: any ApplicationRepository

    init(applications: any ApplicationRepository, application: Application) {
        self.applications = applications
        self.application = application
    }

    var status: ApplicationStatus { application.status }

    var needsAccept: Bool { status == .selected }
    /// Worker owes the start-OTP entry.
    var needsStartOtp: Bool { status == .accepted || status == .otpRequested }
    /// Work is underway; worker can finish it (generates the completion code).
    var isWorking: Bool { status == .workInProgress }
    /// Completion code generated; worker reads it to the employer.
    var awaitingCompletionVerify: Bool { status == .completionPending }

    func refresh() async {
        do {
            if let updated = try await IosHelpersKt.getApplicationByIdOrThrow(applications, applicationId: application.id) {
                application = updated
            }
            await loadCompletionCode()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func accept() async {
        await run {
            self.application = try await IosHelpersKt.acceptSelectionOrThrow(self.applications, applicationId: self.application.id)
        }
    }

    func submitStartOtp() async {
        let code = otpInput.trimmingCharacters(in: .whitespaces)
        guard code.count >= 4 else { errorMessage = "Enter the OTP from your employer"; return }
        await run {
            self.application = try await IosHelpersKt.verifyStartOtpOrThrow(self.applications, applicationId: self.application.id, otp: code)
            self.otpInput = ""
        }
    }

    /// Finish the gig: generates the completion code and moves to COMPLETION_PENDING.
    func completeWork() async {
        await run {
            self.completionCode = try await IosHelpersKt.generateCompletionOtpOrThrow(self.applications, applicationId: self.application.id)
            await self.reloadApplication()
        }
    }

    /// Regenerate an expired completion code (status stays COMPLETION_PENDING).
    func regenerateCompletionCode() async {
        await run {
            self.completionCode = try await IosHelpersKt.regenerateCompletionOtpOrThrow(self.applications, applicationId: self.application.id)
        }
    }

    /// When already COMPLETION_PENDING (e.g. re-opened the screen), pull the
    /// existing completion code from the work session so the worker can re-read it.
    private func loadCompletionCode() async {
        guard awaitingCompletionVerify, completionCode == nil else { return }
        let session = try? await IosHelpersKt.getWorkSessionOrThrow(applications, applicationId: application.id)
        completionCode = session?.completionOtp
    }

    private func reloadApplication() async {
        if let updated = try? await IosHelpersKt.getApplicationByIdOrThrow(applications, applicationId: application.id) {
            application = updated
        }
    }

    private func run(_ op: @escaping () async throws -> Void) async {
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await op() }
        catch { errorMessage = (error as NSError).localizedDescription }
    }
}
