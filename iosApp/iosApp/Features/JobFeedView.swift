import SwiftUI
import Shared

/// Sample SwiftUI screen rendering the shared job feed. Shows the loading /
/// loaded / error states the view-model exposes. This is a thin native UI over
/// the shared data layer — the same Job model the Android app uses.
struct JobFeedView: View {

    @StateObject private var viewModel: JobFeedViewModel
    private let applications: any ApplicationRepository
    private let employeeId: String

    init(jobs: any JobRepository, applications: any ApplicationRepository,
         employeeId: String, profile: (any ProfileRepository)? = nil) {
        _viewModel = StateObject(wrappedValue: JobFeedViewModel(
            jobs: jobs, profile: profile, employeeId: employeeId
        ))
        self.applications = applications
        self.employeeId = employeeId
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(navTitle)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var navTitle: String {
        if let d = viewModel.district, !d.isEmpty { return "Jobs in \(d)" }
        return "Find Jobs"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading jobs…")
        case .loaded(let jobs):
            if jobs.isEmpty {
                emptyState(title: "No jobs", systemImage: "tray", message: "Check back later.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(jobs, id: \.id) { job in
                            NavigationLink {
                                JobDetailView(job: job, applications: applications, employeeId: employeeId)
                            } label: {
                                JobFeedRow(job: job)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                emptyState(title: "Couldn’t load jobs", systemImage: "exclamationmark.triangle", message: message)
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent).tint(GHTheme.primary)
            }
        }
    }

    // iOS-16-compatible placeholder (ContentUnavailableView is iOS 17+).
    private func emptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// A job summary card for the feed list (Android card look).
private struct JobFeedRow: View {
    let job: Job

    var body: some View {
        GHCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(job.title)
                        .font(.headline)
                        .foregroundStyle(GHTheme.onBackground)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(GHTheme.muted)
                }
                if let salary = job.salaryRange, !salary.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "indianrupeesign")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GHTheme.tertiaryVariant)
                        Text(salary)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(GHTheme.tertiaryVariant)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.caption2).foregroundStyle(GHTheme.muted)
                    Text(job.location).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                }
            }
        }
    }
}
