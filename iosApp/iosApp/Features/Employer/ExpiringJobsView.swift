import SwiftUI
import Shared

/// Expiring Jobs — port of Android's ExpiringJobsScreen. The employer's jobs
/// whose application deadline is within 7 days (or already past), so they can
/// extend/act before losing applicants. Computed client-side from getEmployerJobs.
struct ExpiringJobsView: View {
    let jobs: any JobRepository
    let employerId: String
    @StateObject private var viewModel: ExpiringJobsViewModel
    @Environment(\.dismiss) private var dismiss

    init(jobs: any JobRepository, employerId: String) {
        self.jobs = jobs
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: ExpiringJobsViewModel(jobs: jobs, employerId: employerId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(L("expiring_jobs_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("close")) { dismiss() } } }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading…")
        } else if let err = viewModel.error {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(err).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding()
        } else if viewModel.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(GHTheme.success)
                Text(L("expiring_jobs_empty")).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.items) { row($0) }
                }.padding()
            }
        }
    }

    private func row(_ e: ExpiringJobsViewModel.ExpiringJob) -> some View {
        GHCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.headline).lineLimit(1)
                        Text(e.location).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                    }
                    Spacer()
                    deadlinePill(e)
                }
                HStack(spacing: 14) {
                    Label(L("applicants_label", e.applicants), systemImage: "person.2")
                        .font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                }
            }
        }
    }

    private func deadlinePill(_ e: ExpiringJobsViewModel.ExpiringJob) -> some View {
        let (text, color): (String, Color) = e.isExpired
            ? (L("expiring_jobs_expired"), GHTheme.error)
            : (e.daysRemaining <= 0 ? L("expiring_jobs_today")
               : L("expiring_jobs_in_days", Int(e.daysRemaining)),
               e.daysRemaining <= 2 ? GHTheme.warning : GHTheme.tertiaryVariant)
        return Text(text).font(.caption2.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

@MainActor
final class ExpiringJobsViewModel: ObservableObject {
    struct ExpiringJob: Identifiable {
        let id: String; let title: String; let location: String
        let daysRemaining: Int; let isExpired: Bool; let applicants: Int
    }

    @Published private(set) var isLoading = true
    @Published private(set) var error: String?
    @Published private(set) var items: [ExpiringJob] = []

    private let jobs: any JobRepository
    private let employerId: String
    init(jobs: any JobRepository, employerId: String) { self.jobs = jobs; self.employerId = employerId }

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let all = try await IosHelpersKt.getEmployerJobsOrThrow(jobs, employerId: employerId)
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            items = all.compactMap { job -> ExpiringJob? in
                guard let dl = job.applicationDeadline,
                      let d = ActiveJobBarViewModel.parseISO(String(dl.prefix(10))) else { return nil }
                let deadline = cal.startOfDay(for: d)
                let days = cal.dateComponents([.day], from: today, to: deadline).day ?? 0
                let expired = deadline < today
                // Within 7 days or already expired.
                guard expired || days <= 7 else { return nil }
                return ExpiringJob(id: job.id, title: job.title,
                                   location: job.district ?? job.location,
                                   daysRemaining: days, isExpired: expired,
                                   applicants: Int(job.applicationsCount ?? 0))
            }.sorted { $0.daysRemaining < $1.daysRemaining }
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}
