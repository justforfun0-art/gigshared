import Foundation
import Shared

/// Job feed for an employee — scoped to the worker's own district (Android
/// parity: employees only see jobs in their district). Loads the profile to
/// resolve the district, then fetches district-filtered jobs.
@MainActor
final class JobFeedViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case loaded([Job])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// The resolved district (shown in the header, e.g. "Jobs in Amritsar").
    @Published private(set) var district: String?

    private let jobs: any JobRepository
    private let profileRepo: (any ProfileRepository)?
    private let employeeId: String?

    init(jobs: any JobRepository, profile: (any ProfileRepository)? = nil, employeeId: String? = nil) {
        self.jobs = jobs
        self.profileRepo = profile
        self.employeeId = employeeId
    }

    func load() async {
        state = .loading
        do {
            // Resolve the worker's district from their profile (if available).
            var district: String? = nil
            var stateName: String? = nil
            if let profileRepo, let employeeId,
               let profile = try? await IosHelpersKt.getEmployeeProfileOrThrow(profileRepo, userId: employeeId) {
                district = profile.district
                stateName = profile.state
            }
            self.district = district

            let list = try await IosHelpersKt.getJobsForDistrictOrThrow(
                jobs, district: district, state: stateName, page: 1, limit: 20
            )
            self.state = .loaded(list)
        } catch {
            self.state = .failed((error as NSError).localizedDescription)
        }
    }
}
