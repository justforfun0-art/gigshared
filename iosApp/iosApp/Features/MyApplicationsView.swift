import SwiftUI
import Shared

/// "My Applications" — the employee's applications with status + swipe-to-withdraw.
struct MyApplicationsView: View {

    @StateObject private var viewModel: MyApplicationsViewModel
    private let applications: any ApplicationRepository

    init(applications: any ApplicationRepository, employeeId: String) {
        self.applications = applications
        _viewModel = StateObject(
            wrappedValue: MyApplicationsViewModel(applications: applications, employeeId: employeeId)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle("My Applications")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Couldn’t withdraw", isPresented: errorBinding) {
                Button("OK", role: .cancel) { viewModel.actionError = nil }
            } message: {
                Text(viewModel.actionError ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded(let apps):
            if apps.isEmpty {
                placeholder(title: "No applications yet", icon: "doc.text",
                            message: "Jobs you apply to show up here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(apps, id: \.id) { app in
                            row(for: app)
                                .contextMenu {
                                    if viewModel.canWithdraw(app) {
                                        Button(role: .destructive) {
                                            Task { await viewModel.withdraw(app) }
                                        } label: {
                                            Label("Withdraw", systemImage: "xmark.circle")
                                        }
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
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Hired/in-flight applications open the work-session screen (OTP loop);
    /// everything else is a plain status row.
    @ViewBuilder
    private func row(for app: Application) -> some View {
        if Self.isActionable(app.status) {
            NavigationLink {
                WorkSessionView(applications: applications, application: app)
            } label: {
                ApplicationRow(application: app, actionable: true)
            }
            .buttonStyle(.plain)
        } else {
            ApplicationRow(application: app)
        }
    }

    private static func isActionable(_ status: ApplicationStatus) -> Bool {
        status == .selected || status == .accepted || status == .otpRequested
            || status == .workInProgress || status == .completionPending
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

private struct ApplicationRow: View {
    let application: Application
    /// Actionable rows show a chevron to hint they open the work-session screen.
    var actionable: Bool = false

    var body: some View {
        GHCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(application.job?.title ?? "Job")
                            .font(.headline)
                            .foregroundStyle(GHTheme.onBackground)
                        if let location = application.job?.location {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption2).foregroundStyle(GHTheme.muted)
                                Text(location).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                            }
                        }
                    }
                    Spacer()
                    if actionable {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(GHTheme.muted)
                    }
                }
                HStack {
                    StatusBadgeView(status: application.status)
                    Spacer()
                    if let applied = application.appliedAt {
                        Text(applied.prefix(10)).font(.caption).foregroundStyle(GHTheme.muted)
                    }
                }
                // In-flight applications get the expandable stage tracker
                // (Android's DetailedHistoryCard). Actionable rows are wrapped in
                // a NavigationLink (→ the work-session screen, which already shows
                // live progress + OTP), so the inline tracker is only added to
                // non-actionable in-flight rows where the tap is free to expand.
                if !application.status.isTerminal() && !actionable {
                    Divider().padding(.top, 4)
                    HistoryProgress(application: application)
                }
            }
        }
    }
}
