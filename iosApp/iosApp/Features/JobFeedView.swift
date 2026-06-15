import SwiftUI
import Shared

/// Sample SwiftUI screen rendering the shared job feed. Shows the loading /
/// loaded / error states the view-model exposes. This is a thin native UI over
/// the shared data layer — the same Job model the Android app uses.
struct JobFeedView: View {

    @StateObject private var viewModel: JobFeedViewModel
    private let applications: any ApplicationRepository
    private let employeeId: String

    init(jobs: any JobRepository, applications: any ApplicationRepository, employeeId: String) {
        _viewModel = StateObject(wrappedValue: JobFeedViewModel(jobs: jobs))
        self.applications = applications
        self.employeeId = employeeId
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Find Jobs")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
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
                List(jobs, id: \.id) { job in
                    NavigationLink {
                        JobDetailView(job: job, applications: applications, employeeId: employeeId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.title).font(.headline)
                            Text(job.location).font(.subheadline).foregroundStyle(.secondary)
                            if let salary = job.salaryRange {
                                Text(salary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                emptyState(title: "Couldn’t load jobs", systemImage: "exclamationmark.triangle", message: message)
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
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
