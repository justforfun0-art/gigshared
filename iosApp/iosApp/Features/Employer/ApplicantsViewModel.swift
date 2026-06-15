import Foundation
import Shared

/// Applicants for one job (employer view) + the hire/reject + work-OTP actions.
@MainActor
final class ApplicantsViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded([Application])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var actionError: String?
    /// An OTP to show the employer after generate (start or completion).
    @Published var presentedOtp: String?

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
    func generateCompletionOtp(_ app: Application) async {
        await runOtp { try await IosHelpersKt.generateCompletionOtpOrThrow(self.applications, applicationId: app.id) }
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
