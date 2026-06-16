import SwiftUI
import Shared

/// Employer "My Jobs": posted jobs, a Post button, and tap → applicants.
struct MyJobsView: View {

    let container: AppContainer
    let employerId: String
    @StateObject private var viewModel: MyJobsViewModel
    @State private var showPost = false

    init(container: AppContainer, employerId: String) {
        self.container = container
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: MyJobsViewModel(jobs: container.jobs, employerId: employerId))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("my_jobs_label"))
                .drawerToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showPost = true } label: { Image(systemName: "plus") }
                    }
                }
                .sheet(isPresented: $showPost) {
                    PostJobView(jobs: container.jobs, employerId: employerId) {
                        Task { await viewModel.load() }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded(let jobs):
            if jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L("ios_no_jobs_posted")).font(.headline)
                    Button(L("post_a_job")) { showPost = true }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(jobs, id: \.id) { job in
                    NavigationLink {
                        ApplicantsView(applications: container.applications, job: job)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.title).font(.headline)
                            Text(job.location).font(.subheadline).foregroundStyle(.secondary)
                            if let count = job.applicationsCount {
                                Text("\(count.intValue) applicant\(count.intValue == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
        }
    }
}
