import SwiftUI
import Shared

/// Employee job search — port of Android's JobSearchScreen. A debounced search
/// bar, popular-search chips when empty, and violet-accented result cards that
/// open the job detail. Uses the new searchJobs shim.
struct JobSearchView: View {
    let jobs: any JobRepository
    let applications: any ApplicationRepository
    let employeeId: String

    @StateObject private var viewModel: JobSearchViewModel
    @State private var query = ""

    private let popular = ["Cleaning", "Cooking", "Driver", "Security", "Helper", "Delivery"]
    private var accent: Color { GHTheme.hex(0x7C3AED) }

    init(jobs: any JobRepository, applications: any ApplicationRepository, employeeId: String) {
        self.jobs = jobs
        self.applications = applications
        self.employeeId = employeeId
        _viewModel = StateObject(wrappedValue: JobSearchViewModel(jobs: jobs))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    content
                }
            }
            .navigationTitle(L("search_jobs"))
            .navigationBarTitleDisplayMode(.inline)
            .drawerToolbar()
            // Debounced search driven by `query`.
            .onChange(of: query) { _ in viewModel.scheduleSearch(query) }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(query.isEmpty ? GHTheme.hex(0x9CA3AF) : accent)
            TextField(L("search_jobs"), text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(GHTheme.hex(0x9CA3AF)) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(query.isEmpty ? GHTheme.outline : accent, lineWidth: 1))
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyPrompt
        } else if viewModel.results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                Text(L("ios_no_jobs_match")).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("\(viewModel.results.count) jobs found")
                        .font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                    ForEach(viewModel.results, id: \.id) { job in
                        NavigationLink {
                            JobDetailView(job: job, applications: applications, employeeId: employeeId)
                        } label: {
                            SearchResultCard(job: job, accent: accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Circle().fill(GHTheme.hex(0xEDE9FE)).frame(width: 72, height: 72)
                .overlay(Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(accent))
                .padding(.top, 24)
            Text(L("search_for_jobs_title")).font(.headline).foregroundStyle(GHTheme.onBackground)
            Text(L("search_hint_subtitle")).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)

            Text(L("popular_searches_label")).font(.subheadline.weight(.semibold))
                .foregroundStyle(GHTheme.onBackground)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
            FlowChips(items: popular, accent: accent) { query = $0 }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Simple wrapping chip row (popular searches).
private struct FlowChips: View {
    let items: [String]
    let accent: Color
    let onTap: (String) -> Void

    var body: some View {
        // Two rows of three — matches the fixed popular-search list.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<((items.count + 2) / 3), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(items[(row * 3)..<min(row * 3 + 3, items.count)], id: \.self) { term in
                        Button { onTap(term) } label: {
                            Text(term).font(.callout.weight(.medium)).foregroundStyle(accent)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(GHTheme.hex(0xEDE9FE), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchResultCard: View {
    let job: Job
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.title).font(.headline).foregroundStyle(GHTheme.onBackground)
            HStack(spacing: 6) {
                Image(systemName: "building.2").font(.caption2).foregroundStyle(accent)
                Text(job.employerProfile?.companyName ?? "Company")
                    .font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            HStack(spacing: 8) {
                chip("mappin.circle", job.district ?? job.location, accent, GHTheme.hex(0xEDE9FE))
                if let pay = job.salaryRange, !pay.isEmpty {
                    chip("indianrupeesign", pay, GHTheme.hex(0x16A34A), GHTheme.hex(0xF0FDF4))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private func chip(_ icon: String, _ text: String, _ fg: Color, _ bg: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.caption.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(bg, in: Capsule())
    }
}

@MainActor
final class JobSearchViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var results: [Job] = []

    private let jobs: any JobRepository
    private var searchTask: Task<Void, Never>?

    init(jobs: any JobRepository) { self.jobs = jobs }

    /// Debounce ~300ms (Android parity), then search; empty query clears.
    func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; isLoading = false; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.run(q)
        }
    }

    private func run(_ q: String) async {
        isLoading = true
        defer { isLoading = false }
        results = (try? await IosHelpersKt.searchJobsOrThrow(jobs, query: q)) ?? []
    }
}
