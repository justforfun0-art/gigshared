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
            content
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
                List {
                    ForEach(apps, id: \.id) { app in
                        row(for: app)
                            .swipeActions(edge: .trailing) {
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
                ApplicationRow(application: app)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(application.job?.title ?? "Job")
                .font(.headline)
            if let location = application.job?.location {
                Text(location).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
                StatusBadge(application.status)
                Spacer()
                if let applied = application.appliedAt {
                    Text(applied.prefix(10)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatusBadge: View {
    let status: ApplicationStatus
    init(_ status: ApplicationStatus) { self.status = status }

    var body: some View {
        Text(status.toDisplayString())
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        if status.isTerminal() {
            return status == ApplicationStatus.completed ? .green : .secondary
        }
        return .blue // active
    }
}
