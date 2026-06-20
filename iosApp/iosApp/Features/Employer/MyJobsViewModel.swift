import Foundation
import Shared

/// Employer's posted jobs (Android MyJobsViewModel parity): load, status
/// classification (active/pending/expired/rejected/paused), filter tabs, search,
/// and delete-with-guard.
@MainActor
final class MyJobsViewModel: ObservableObject {
    enum State { case idle, loading, loaded([Job]), failed(String) }
    enum Filter: String, CaseIterable, Identifiable { case all, active, pending, expired; var id: String { rawValue } }

    @Published private(set) var state: State = .idle
    @Published var filter: Filter = .active
    @Published var query: String = ""
    @Published var actionError: String?
    @Published var cannotDelete = false   // drives the "has applicants" alert

    private let jobs: any JobRepository
    private let employerId: String
    private var all: [Job] = []

    init(jobs: any JobRepository, employerId: String) {
        self.jobs = jobs
        self.employerId = employerId
    }

    func load() async {
        if all.isEmpty { state = .loading }
        do {
            all = try await IosHelpersKt.getEmployerJobsOrThrow(jobs, employerId: employerId)
            state = .loaded(all)
            // Auto-focus Active on first load; fall back to All if none active.
            if filter == .active && counts.active == 0 && counts.total > 0 { filter = .all }
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    // MARK: - Status classification (mirrors Android Job helpers)

    func isExpired(_ job: Job) -> Bool {
        // Past job_date (or past application_deadline) = expired. iOS computes
        // from the strings to avoid passing a kotlinx LocalDateTime from Swift.
        let today = Calendar.current.startOfDay(for: Date())
        if let dl = job.applicationDeadline, let d = ActiveJobBarViewModel.parseISO(String(dl.prefix(10))),
           Calendar.current.startOfDay(for: d) < today { return true }
        if let jd = job.jobDate, let d = ActiveJobBarViewModel.parseISO(String(jd.prefix(10))),
           Calendar.current.startOfDay(for: d) < today { return true }
        return false
    }
    func isPending(_ job: Job) -> Bool { job.isPendingApproval() }
    func isRejected(_ job: Job) -> Bool { job.isRejectedByAdmin() }
    func isActive(_ job: Job) -> Bool {
        job.isActive && !isPending(job) && !isRejected(job) && !isExpired(job)
    }

    /// Human status word for a job (drives the card pill + search).
    func statusLabel(_ job: Job) -> (String, StatusKind) {
        if isRejected(job) { return ("Rejected", .expired) }
        if isExpired(job) { return ("Expired", .expired) }
        if isPending(job) { return ("Pending", .pending) }
        if isActive(job) { return ("Active", .active) }
        return ("Paused", .paused)
    }
    enum StatusKind { case active, pending, expired, paused }

    // MARK: - Counts + filtered list

    var counts: (total: Int, active: Int, pending: Int, expired: Int) {
        (all.count,
         all.filter(isActive).count,
         all.filter { isPending($0) && !isExpired($0) }.count,
         all.filter { isExpired($0) || isRejected($0) }.count)
    }

    var filtered: [Job] {
        let byStatus: [Job]
        switch filter {
        case .all: byStatus = all
        case .active: byStatus = all.filter(isActive)
        case .pending: byStatus = all.filter { isPending($0) && !isExpired($0) }
        case .expired: byStatus = all.filter { isExpired($0) || isRejected($0) }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return byStatus }
        return byStatus.filter { job in
            let hay = [job.title, job.location, job.district, job.state, statusLabel(job).0]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    func delete(_ job: Job) async {
        actionError = nil; cannotDelete = false
        do {
            try await IosHelpersKt.deleteJobOrThrow(jobs, jobId: job.id)
            await load()
        } catch {
            // A Kotlin @Throws surfaces as an NSError whose userInfo carries the
            // original KotlinThrowable under "KotlinException".
            let ns = error as NSError
            if let kt = ns.userInfo["KotlinException"] as? KotlinThrowable,
               IosHelpersKt.isJobHasApplicantsError(error: kt) {
                cannotDelete = true
            } else {
                actionError = ns.localizedDescription
            }
        }
    }
}
