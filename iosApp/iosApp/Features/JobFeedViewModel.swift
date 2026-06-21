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
    /// Free-text search over the loaded jobs (title/location/skills).
    @Published var query: String = ""

    private let jobs: any JobRepository
    private let profileRepo: (any ProfileRepository)?
    private let employeeId: String?
    private let matchRepo: (any MatchRepository)?
    /// Semantic match score per jobId (0..100), from the embedding matcher (#4).
    @Published private(set) var matchScores: [String: Int] = [:]

    init(jobs: any JobRepository, profile: (any ProfileRepository)? = nil,
         employeeId: String? = nil, match: (any MatchRepository)? = nil) {
        self.jobs = jobs
        self.profileRepo = profile
        self.employeeId = employeeId
        self.matchRepo = match
    }

    /// The match % for a job, if the embedding matcher returned one.
    func matchScore(_ jobId: String) -> Int? { matchScores[jobId] }

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

            var list = try await IosHelpersKt.getJobsForDistrictOrThrow(
                jobs, district: district, state: stateName, page: 1, limit: 20
            )
            // Smart-feed: reorder by the rank_jobs RPC (best-first). Unranked
            // jobs keep their original order at the end. Android parity; the
            // ranking is invisible (no badge), purely the sort. Best-effort.
            if let employeeId,
               let rankedIds = try? await IosHelpersKt.rankJobsForWorkerOrThrow(jobs, workerId: employeeId, limit: 100),
               !rankedIds.isEmpty {
                let rankIndex = Dictionary(uniqueKeysWithValues: rankedIds.enumerated().map { ($1, $0) })
                list = list.enumerated().sorted { a, b in
                    let ra = rankIndex[a.element.id] ?? Int.max
                    let rb = rankIndex[b.element.id] ?? Int.max
                    if ra != rb { return ra < rb }
                    return a.offset < b.offset   // stable for unranked
                }.map(\.element)
            }
            self.state = .loaded(list)

            // Semantic match scores (#4) — best-effort overlay; the feed already
            // rendered, so a failure or empty result just hides the badge.
            if let matchRepo {
                matchScores = (try? await IosHelpersKt.matchScoresOrThrow(
                    matchRepo, state: stateName, district: district, limit: 50)) as? [String: Int] ?? [:]
            }
        } catch {
            self.state = .failed((error as NSError).localizedDescription)
        }
    }

    /// Client-side filter over the loaded list (title / location / district / skills).
    func filtered(_ list: [Job]) -> [Job] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { job in
            job.title.lowercased().contains(q)
            || job.location.lowercased().contains(q)
            || (job.district?.lowercased().contains(q) ?? false)
            || job.skillsRequired.contains { $0.lowercased().contains(q) }
        }
    }
}
