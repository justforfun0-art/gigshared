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
    private let employeeId: String

    init(applications: any ApplicationRepository, employeeId: String) {
        self.applications = applications
        self.employeeId = employeeId
    }

    func load() async {
        state = .loading
        do {
            let list = try await IosHelpersKt.getEmployeeApplicationsOrThrow(applications, employeeId: employeeId)
            state = .loaded(list)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    /// Only non-terminal applications can be withdrawn (mirrors the repo guard).
    func canWithdraw(_ application: Application) -> Bool {
        !application.status.isTerminal()
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
