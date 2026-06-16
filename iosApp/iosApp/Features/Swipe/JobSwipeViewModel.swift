import Foundation
import Shared

/// Drives the Tinder-style job-swipe deck (port of Android's JobSwipeViewModel).
/// Loads the relevance-ranked deck via getJobsForSwipe; swipe-right applies to
/// the top job, swipe-left just discards it. The top card is always
/// `jobs.first`; both gestures pop it off the front.
@MainActor
final class JobSwipeViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// The live deck — front (`first`) is the top card.
    @Published private(set) var jobs: [Job] = []
    /// The job currently being applied to (swipe-right in flight); blocks input.
    @Published private(set) var applyingJobId: String?
    /// A transient chip shown after each swipe: ("Applied"/"Skipped", isApply).
    @Published var lastAction: (text: String, isApply: Bool)?
    @Published var actionError: String?

    private let jobs_repo: any JobRepository
    private let applications: any ApplicationRepository
    private let employeeId: String
    private let profileRepo: (any ProfileRepository)?

    init(jobs: any JobRepository, applications: any ApplicationRepository,
         employeeId: String, profile: (any ProfileRepository)? = nil) {
        self.jobs_repo = jobs
        self.applications = applications
        self.employeeId = employeeId
        self.profileRepo = profile
    }

    var topJob: Job? { jobs.first }
    var isEmpty: Bool { jobs.isEmpty }

    func load() async {
        state = .loading
        do {
            // Scope the deck to the worker's district (Android parity).
            var district: String? = nil
            var stateName: String? = nil
            if let profileRepo,
               let profile = try? await IosHelpersKt.getEmployeeProfileOrThrow(profileRepo, userId: employeeId) {
                district = profile.district
                stateName = profile.state
            }
            let deck = try await IosHelpersKt.getJobsForSwipeOrThrow(
                jobs_repo, userId: employeeId, district: district, state: stateName
            )
            jobs = deck
            state = .loaded
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    /// Swipe right → apply to the top job, then pop it off the deck.
    func swipeRight() {
        guard applyingJobId == nil, let job = jobs.first else { return }
        applyingJobId = job.id
        flashChip(text: "Applied", isApply: true)
        Task {
            defer { applyingJobId = nil }
            do {
                _ = try await IosHelpersKt.applyToJobOrThrow(applications, jobId: job.id, employeeId: employeeId)
            } catch {
                actionError = (error as NSError).localizedDescription
            }
            pop(job.id)
        }
    }

    /// Swipe left → discard the top job (no application).
    func swipeLeft() {
        guard applyingJobId == nil, let job = jobs.first else { return }
        flashChip(text: "Skipped", isApply: false)
        pop(job.id)
    }

    private func pop(_ id: String) {
        jobs.removeAll { $0.id == id }
    }

    private func flashChip(text: String, isApply: Bool) {
        lastAction = (text, isApply)
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if lastAction?.text == text { lastAction = nil }
        }
    }
}
