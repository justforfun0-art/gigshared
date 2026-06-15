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
    @State private var filter: HistoryFilter = .all
    @State private var showInbox = false

    init(applications: any ApplicationRepository, employeeId: String, messages: (any MessageRepository)? = nil) {
        self.applications = applications
        self.messages = messages
        self.employeeId = employeeId
        _viewModel = StateObject(
            wrappedValue: MyApplicationsViewModel(applications: applications, employeeId: employeeId)
        )
    }

    enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "All", active = "Active", completed = "Completed"
        case expired = "Expired", rejected = "Rejected"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterTabs
                    content
                }
            }
            .navigationTitle("History")
            .toolbar {
                if messages != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showInbox = true } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                    }
                }
            }
            .sheet(isPresented: $showInbox) {
                if let messages {
                    MessagesView(repo: messages, myUserId: employeeId)
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Couldn’t withdraw", isPresented: errorBinding) {
                Button("OK", role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } })
    }

    // MARK: - Filter tabs

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(HistoryFilter.allCases) { f in
                    let selected = f == filter
                    VStack(spacing: 6) {
                        Text(f.rawValue)
                            .font(.system(size: 15, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? GHTheme.primary : GHTheme.onSurfaceVariant)
                        Rectangle()
                            .fill(selected ? GHTheme.primary : .clear)
                            .frame(height: 2)
                    }
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { filter = f } }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            Spacer(); ProgressView("Loading…"); Spacer()
        case .loaded(let apps):
            let filtered = apps.filter(matches)
            if filtered.isEmpty {
                placeholder(title: "Nothing here yet", icon: "clock.arrow.circlepath",
                            message: "Applications in this category will show up here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(filtered, id: \.id) { app in
                            NavigationLink {
                                ApplicationStatusView(application: app, messages: messages, myUserId: employeeId)
                            } label: {
                                HistoryCard(application: app)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if viewModel.canWithdraw(app) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.withdraw(app) }
                                    } label: { Label("Withdraw", systemImage: "xmark.circle") }
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
                Button("Retry") { Task { await viewModel.load() } }
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

    private var job: Job? { application.job }
    private var inFlight: Bool { !application.status.isTerminal() }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar.
            Rectangle()
                .fill(GHTheme.primary)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                header
                if let subtitle = statusSubtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                chips
                if inFlight {
                    HistoryStepper(status: application.status)
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
                .fill(GHTheme.primary)
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
        HStack(spacing: 8) {
            if let loc = job?.district ?? job?.location {
                Chip(icon: "mappin", text: loc)
            }
            if let pay = job?.salaryRange, !pay.isEmpty {
                Chip(icon: "indianrupeesign", text: pay)
            }
            if let date = formatJobDate(job?.jobDate) {
                Chip(icon: "calendar", text: date)
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

/// A small violet-tinted pill chip (icon + text) used for location/pay/date.
private struct Chip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption).lineLimit(1)
        }
        .foregroundStyle(GHTheme.primary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(GHTheme.primaryContainer, in: Capsule())
    }
}
