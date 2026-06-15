import Foundation
import Shared

/// Employer's posted jobs over the shared `JobRepository`.
@MainActor
final class MyJobsViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded([Job])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let jobs: any JobRepository
    private let employerId: String

    init(jobs: any JobRepository, employerId: String) {
        self.jobs = jobs
        self.employerId = employerId
    }

    func load() async {
        state = .loading
        do {
            let list = try await IosHelpersKt.getEmployerJobsOrThrow(jobs, employerId: employerId)
            state = .loaded(list)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }
}
