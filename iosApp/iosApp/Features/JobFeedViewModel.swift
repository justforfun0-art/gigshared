import Foundation
import Shared

/// Sample view-model over the shared `JobRepository`. Demonstrates the standard
/// bridging pattern: call a Kotlin `suspend fun` from a Swift async context, and
/// unwrap the Kotlin `Result<T>` the repos return.
@MainActor
final class JobFeedViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case loaded([Job])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let jobs: any JobRepository

    init(jobs: any JobRepository) {
        self.jobs = jobs
    }

    func load(filter: JobFilter? = nil) async {
        state = .loading
        do {
            // getJobsOrThrow (IosHelpers.kt) unwraps Kotlin Result into a plain
            // throwing suspend → Swift gets `[Job]` directly or an error thrown.
            // (Kotlin `Result<T>` itself boxes opaquely over ObjC; SKIE would
            //  generate typed wrappers if you'd rather call getJobs directly.)
            let list = try await JobFeedViewModel.fetch(jobs, filter)
            state = .loaded(list)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    private static func fetch(_ jobs: any JobRepository, _ filter: JobFilter?) async throws -> [Job] {
        try await IosHelpersKt.getJobsOrThrow(jobs, filter: filter, page: 1, limit: 20)
    }
}
