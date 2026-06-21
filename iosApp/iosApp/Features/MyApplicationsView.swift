import SwiftUI
import Shared

/// "History" — the employee's applications with filter tabs, rich cards, and an
/// inline horizontal stage stepper (port of Android's HistoryScreen). Every card
/// is tappable → the work-session detail screen.
struct MyApplicationsView: View {

    @StateObject private var viewModel: MyApplicationsViewModel
    private let applications: any ApplicationRepository
    private let messages: (any MessageRepository)?
    private let employeeId: String
    private let isEmployer: Bool
    @State private var filter: HistoryFilter
    @State private var employerFilter: EmployerFilter

    /// Role accent — violet for employees, green for employers.
    private var accent: Color { isEmployer ? GHTheme.tertiary : GHTheme.primary }

    init(applications: any ApplicationRepository, employeeId: String,
         messages: (any MessageRepository)? = nil, isEmployer: Bool = false,
         initialActive: Bool = false) {
        self.applications = applications
        self.messages = messages
        self.employeeId = employeeId
        self.isEmployer = isEmployer
        // Land on the Active tab when opened from the home "Active" tile.
        _filter = State(initialValue: initialActive ? .active : .all)
        _employerFilter = State(initialValue: initialActive ? .active : .active)
        _viewModel = StateObject(
            wrappedValue: MyApplicationsViewModel(applications: applications, employeeId: employeeId, isEmployer: isEmployer)
        )
    }

    enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "All", active = "Active", completed = "Completed"
        case expired = "Expired", rejected = "Rejected"
        var id: String { rawValue }
    }

    /// Employer applications use a different filter set (Android EmployerApplicationsScreen).
    enum EmployerFilter: String, CaseIterable, Identifiable {
        case active = "Active", all = "All", pending = "Pending"
        case selected = "Selected", inProgress = "In Progress", completed = "Completed"
        var id: String { rawValue }
    }
    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterTabs
                    content
                }
            }
            .navigationTitle(isEmployer ? L("nav_employer_applications") : L("cd_history"))
            .drawerToolbar()
            .if(isEmployer) { $0.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("search_applications")) }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Couldn’t withdraw", isPresented: errorBinding) {
                Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } })
    }

    // MARK: - Filter tabs

    @ViewBuilder
    private var filterTabs: some View {
        if isEmployer {
            employerFilterTabs
        } else {
            let apps = currentApps
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(HistoryFilter.allCases) { f in
                        let selected = f == filter
                        // Count shown only on the All and Active tabs.
                        let n = (f == .all || f == .active) ? historyCount(f, apps) : nil
                        VStack(spacing: 6) {
                            Text(n.map { "\(f.rawValue) (\($0))" } ?? f.rawValue)
                                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? accent : GHTheme.onSurfaceVariant)
                            Rectangle().fill(selected ? accent : .clear).frame(height: 2)
                        }
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { filter = f } }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
    }

    /// Count for an employee history filter (used for the All/Active tab badges).
    private func historyCount(_ f: HistoryFilter, _ apps: [Application]) -> Int {
        apps.filter { historyMatches(f, $0) }.count
    }
    private func historyMatches(_ f: HistoryFilter, _ app: Application) -> Bool {
        switch f {
        case .all: return true
        case .active: return app.status.isActive()
        case .completed: return app.status == .completed
        case .expired: return app.status == .expired
        case .rejected:
            return [.rejected, .rejectedOnce, .rejectedAndReshown, .noShow, .withdrawn, .notInterested]
                .contains(app.status)
        }
    }

    /// Employer filter tabs with live counts in the label, e.g. "Active (3)".
    private func employerCount(_ f: EmployerFilter, _ apps: [Application]) -> Int {
        apps.filter { employerMatches(f, $0) }.count
    }
    private func employerMatches(_ f: EmployerFilter, _ app: Application) -> Bool {
        switch f {
        case .all: return true
        case .active: return app.status.isActive()
        case .pending: return app.status == .applied
        case .selected: return app.status == .selected
        case .inProgress:
            return [.accepted, .otpRequested, .workInProgress, .completionPending, .paymentPending].contains(app.status)
        case .completed: return app.status == .completed
        }
    }

    @ViewBuilder
    private var employerFilterTabs: some View {
        let apps = currentApps
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(EmployerFilter.allCases) { f in
                    let selected = f == employerFilter
                    // Count shown only on the Active and All tabs.
                    let n = (f == .all || f == .active) ? employerCount(f, apps) : nil
                    VStack(spacing: 6) {
                        Text(n.map { "\(f.rawValue) (\($0))" } ?? f.rawValue)
                            .font(.system(size: 14, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? accent : GHTheme.onSurfaceVariant)
                        Rectangle().fill(selected ? accent : .clear).frame(height: 2)
                    }
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { employerFilter = f } }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    /// The raw application list from the loaded state (for count computation).
    private var currentApps: [Application] {
        if case .loaded(let apps) = viewModel.state { return apps }
        return []
    }

    private func matches(_ app: Application) -> Bool {
        switch filter {
        case .all: return true
        case .active: return app.status.isActive()
        case .completed: return app.status == .completed
        case .expired: return app.status == .expired
        case .rejected:
            return [.rejected, .rejectedOnce, .rejectedAndReshown, .noShow, .withdrawn, .notInterested]
                .contains(app.status)
        }
    }

    /// Sort to match Android's HistoryViewModel: most-recent-activity first
    /// (updatedAt → appliedAt → createdAt, ISO-8601 descending), and under "All"
    /// pin SELECTED offers to the very top so the worker sees new offers first.
    private func sorted(_ apps: [Application]) -> [Application] {
        let byRecency = apps.sorted {
            ($0.updatedAt ?? $0.appliedAt ?? $0.createdAt ?? "")
                > ($1.updatedAt ?? $1.appliedAt ?? $1.createdAt ?? "")
        }
        guard filter == .all else { return byRecency }
        // Stable pin: SELECTED first, otherwise keep recency order.
        return byRecency.enumerated()
            .sorted { lhs, rhs in
                let lSel = lhs.element.status == .selected
                let rSel = rhs.element.status == .selected
                if lSel != rSel { return lSel }      // SELECTED before others
                return lhs.offset < rhs.offset       // else preserve recency
            }
            .map(\.element)
    }

    /// Employer applications filtered by the selected tab + search, recency-sorted.
    private func employerFiltered(_ apps: [Application]) -> [Application] {
        let byTab = apps.filter { employerMatches(employerFilter, $0) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let bySearch = q.isEmpty ? byTab : byTab.filter { app in
            let hay = [app.job?.title, app.employeeProfile?.name, app.status.toDisplayString()]
                .compactMap { $0 }.joined(separator: " ").lowercased()
            return hay.contains(q)
        }
        return bySearch.sorted {
            ($0.updatedAt ?? $0.appliedAt ?? "") > ($1.updatedAt ?? $1.appliedAt ?? "")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            Spacer(); ProgressView("Loading…"); Spacer()
        case .loaded(let apps):
            let filtered = isEmployer ? employerFiltered(apps) : sorted(apps.filter(matches))
            if filtered.isEmpty {
                placeholder(title: "Nothing here yet", icon: "clock.arrow.circlepath",
                            message: "Applications in this category will show up here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(filtered, id: \.id) { app in
                            NavigationLink {
                                ApplicationStatusView(application: app, messages: messages, myUserId: employeeId, applications: applications)
                            } label: {
                                HistoryCard(application: app, isEmployer: isEmployer)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if viewModel.canWithdraw(app) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.withdraw(app) }
                                    } label: { Label(L("withdraw"), systemImage: "xmark.circle") }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                placeholder(title: "Couldn’t load", icon: "exclamationmark.triangle", message: message)
                Button(L("retry_btn")) { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent).tint(GHTheme.primary)
            }
        }
    }

    private func placeholder(title: String, icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// One application history card — left accent bar, briefcase icon, title +
/// employer, status badge, status subtitle, location/pay/date chips, the inline
/// horizontal stepper (for in-flight), and the "Applied …" footer.
private struct HistoryCard: View {
    let application: Application
    var isEmployer: Bool = false

    private var accent: Color { isEmployer ? GHTheme.tertiary : GHTheme.primary }
    private var job: Job? { application.job }
    private var inFlight: Bool { !application.status.isTerminal() }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar.
            Rectangle()
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                header
                if let subtitle = statusSubtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                chips
                if inFlight {
                    HistoryStepper(status: application.status, isEmployer: isEmployer)
                        .padding(.top, 2)
                }
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption2).foregroundStyle(GHTheme.muted)
                    Text("Applied \(formattedApplied)").font(.caption).foregroundStyle(GHTheme.muted)
                }
            }
            .padding(14)
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(accent)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "briefcase.fill").foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(job?.title ?? "Job")
                    .font(.headline).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                if let employer = job?.employerProfile?.companyName, !employer.isEmpty {
                    Text(employer).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                }
            }
            Spacer()
            StatusBadgeView(status: application.status)
        }
    }

    private var chips: some View {
        let tint = isEmployer ? GHTheme.tertiaryContainer : GHTheme.primaryContainer
        return HStack(spacing: 8) {
            if let loc = job?.district ?? job?.location {
                Chip(icon: "mappin", text: loc, accent: accent, tint: tint)
            }
            if let pay = job?.salaryRange, !pay.isEmpty {
                Chip(icon: "indianrupeesign", text: pay, accent: accent, tint: tint)
            }
            if let date = formatJobDate(job?.jobDate) {
                Chip(icon: "calendar", text: date, accent: accent, tint: tint)
            }
        }
    }

    private var statusSubtitle: String? {
        switch application.status {
        case .applied, .shortlisted: return "Under review"
        case .selected: return "You’re selected"
        case .accepted, .otpRequested: return "Ready to start"
        case .workInProgress: return "Work in progress"
        case .completionPending: return "Awaiting verification"
        case .paymentPending: return "Work verified — payment being processed"
        case .completed: return "Completed"
        default: return nil
        }
    }

    private var formattedApplied: String {
        formatJobDate(application.appliedAt ?? application.createdAt) ?? "—"
    }
}

/// A small role-tinted pill chip (icon + text) used for location/pay/date.
private struct Chip: View {
    let icon: String
    let text: String
    var accent: Color = GHTheme.primary
    var tint: Color = GHTheme.primaryContainer
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption).lineLimit(1)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint, in: Capsule())
    }
}

private extension View {
    /// Conditionally apply a modifier (used to add `.searchable` for employers only).
    @ViewBuilder func `if`<T: View>(_ condition: Bool, _ transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
