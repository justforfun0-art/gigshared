import SwiftUI
import Shared

/// Employer "My Jobs" — port of Android's MyJobsScreen. Stat tiles that double
/// as filters (Total / Active / Pending / Expired), a search bar, rich job cards
/// with status pills, a Post button, swipe-to-delete (guarded against jobs with
/// applicants), and tap → applicants.
struct MyJobsView: View {
    let container: AppContainer
    let employerId: String
    @StateObject private var viewModel: MyJobsViewModel
    @State private var showPost = false
    @State private var editingJob: Job?

    init(container: AppContainer, employerId: String) {
        self.container = container
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: MyJobsViewModel(jobs: container.jobs, employerId: employerId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(L("nav_my_jobs"))
            .drawerToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPost = true } label: { Image(systemName: "plus") }
                }
            }
            .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L("my_jobs_search"))
            .sheet(isPresented: $showPost) {
                PostJobView(jobs: container.jobs, employerId: employerId,
                            jobExtract: container.jobExtract) { Task { await viewModel.load() } }
            }
            .sheet(item: $editingJob) { job in
                EditJobView(jobs: container.jobs, job: job) { Task { await viewModel.load() } }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert(L("cannot_delete_job_title"), isPresented: $viewModel.cannotDelete) {
                Button(L("ok"), role: .cancel) { }
            } message: { Text(L("cannot_delete_job_msg")) }
            .alert("Couldn’t delete", isPresented: deleteErrorBinding) {
                Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent).tint(GHTheme.tertiary)
            }
        case .loaded:
            VStack(spacing: 0) {
                statTiles
                jobList
            }
        }
    }

    // Stat tiles double as filters (Android StatTilesRow).
    private var statTiles: some View {
        let c = viewModel.counts
        return HStack(spacing: 10) {
            tile(.all, "\(c.total)", L("status_total"), GHTheme.hex(0x2563EB))
            tile(.active, "\(c.active)", L("status_active"), GHTheme.success)
            tile(.pending, "\(c.pending)", L("status_pending"), GHTheme.warning)
            tile(.expired, "\(c.expired)", L("status_expired"), GHTheme.muted)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private func tile(_ f: MyJobsViewModel.Filter, _ value: String, _ label: String, _ tint: Color) -> some View {
        let selected = viewModel.filter == f
        return Button { viewModel.filter = f } label: {
            VStack(spacing: 2) {
                Text(value).font(.title3.weight(.heavy)).foregroundStyle(tint)
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(tint.opacity(selected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? tint : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var jobList: some View {
        let jobs = viewModel.filtered
        if jobs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                Text(viewModel.query.isEmpty ? L("ios_no_jobs_posted") : L("ios_no_jobs_match"))
                    .font(.subheadline).foregroundStyle(.secondary)
                if viewModel.query.isEmpty {
                    Button(L("post_a_job")) { showPost = true }.buttonStyle(.borderedProminent).tint(GHTheme.tertiary)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(jobs, id: \.id) { job in
                    NavigationLink {
                        EmployerJobDetailView(jobs: container.jobs,
                                              applications: container.applications, job: job,
                                              profileRepo: container.profile)
                    } label: {
                        MyJobRow(job: job, status: viewModel.statusLabel(job))
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) { Task { await viewModel.delete(job) } } label: {
                            Label(L("delete"), systemImage: "trash")
                        }
                        Button { editingJob = job } label: {
                            Label(L("edit"), systemImage: "pencil")
                        }.tint(GHTheme.tertiary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

/// One job row (Android JobCard) — emerald avatar initial, title, status pill,
/// location/pay chips, applicants count.
private struct MyJobRow: View {
    let job: Job
    let status: (String, MyJobsViewModel.StatusKind)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 44, height: 44)
                .overlay(Text(String(job.title.prefix(1)).uppercased()).font(.headline.weight(.bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.title).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                    Spacer()
                    pill
                }
                HStack(spacing: 10) {
                    if let loc = job.district ?? Optional(job.location), !loc.isEmpty {
                        Label(loc, systemImage: "mappin").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                    }
                    if let pay = job.salaryRange, !pay.isEmpty {
                        Label(pay, systemImage: "indianrupeesign").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                    }
                    if let n = job.applicationsCount?.intValue, n > 0 {
                        Label("\(n)", systemImage: "person.2").font(.caption2).foregroundStyle(GHTheme.hex(0x2563EB))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private var pill: some View {
        let color: Color = {
            switch status.1 {
            case .active: return GHTheme.success
            case .pending: return GHTheme.warning
            case .expired, .paused: return GHTheme.muted
            }
        }()
        return Text(status.0).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
