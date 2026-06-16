import Foundation
import Shared

/// View-model for the employee's "My Applications" list over the shared
/// `ApplicationRepository`. Loads the worker's applications and supports
/// withdrawing a still-active one.
@MainActor
final class MyApplicationsViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case loaded([Application])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var actionError: String?

    private let applications: any ApplicationRepository
    private let userId: String
    private let isEmployer: Bool

    init(applications: any ApplicationRepository, employeeId: String, isEmployer: Bool = false) {
        self.applications = applications
        self.userId = employeeId
        self.isEmployer = isEmployer
    }

    func load() async {
        state = .loading
        do {
            // Employees see their own applications; employers see applicants to
            // their jobs — both render the same history cards + stepper.
            let list = isEmployer
                ? try await IosHelpersKt.getEmployerApplicationsOrThrow(applications, employerId: userId)
                : try await IosHelpersKt.getEmployeeApplicationsOrThrow(applications, employeeId: userId)
            state = .loaded(list)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    /// Only employees can withdraw, and only non-terminal applications.
    func canWithdraw(_ application: Application) -> Bool {
        !isEmployer && !application.status.isTerminal()
    }

    func withdraw(_ application: Application) async {
        actionError = nil
        do {
            _ = try await IosHelpersKt.withdrawApplicationOrThrow(applications, applicationId: application.id)
            await load() // refresh so the row reflects WITHDRAWN
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }
}
