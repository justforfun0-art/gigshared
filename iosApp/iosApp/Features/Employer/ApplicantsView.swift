import SwiftUI
import Shared

/// Applicants for a job: each row shows the worker + a context action based on
/// the application status (Review→select/reject, Accepted→start OTP,
/// CompletionPending→completion OTP, etc).
struct ApplicantsView: View {

    @StateObject private var viewModel: ApplicantsViewModel
    let job: Job

    init(applications: any ApplicationRepository, job: Job) {
        _viewModel = StateObject(wrappedValue: ApplicantsViewModel(applications: applications, jobId: job.id))
        self.job = job
    }

    var body: some View {
        content
            .navigationTitle(job.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Action failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
            .alert("Share this OTP", isPresented: otpBinding) {
                Button("Done", role: .cancel) { viewModel.presentedOtp = nil }
            } message: { Text(viewModel.presentedOtp ?? "") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }
    private var otpBinding: Binding<Bool> {
        Binding(get: { viewModel.presentedOtp != nil }, set: { if !$0 { viewModel.presentedOtp = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded(let apps):
            if apps.isEmpty {
                Text("No applicants yet").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(apps, id: \.id) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.employeeProfile?.name ?? "Applicant").font(.headline)
                        Text(app.status.toDisplayString()).font(.caption).foregroundStyle(.secondary)
                        actions(for: app)
                    }
                    .padding(.vertical, 2)
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button("Retry") { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func actions(for app: Application) -> some View {
        let s = app.status
        HStack(spacing: 8) {
            if s == ApplicationStatus.applied || s == ApplicationStatus.shortlisted {
                Button("Select") { Task { await viewModel.select(app) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Reject", role: .destructive) { Task { await viewModel.reject(app) } }
                    .buttonStyle(.bordered).controlSize(.small)
            } else if s == ApplicationStatus.accepted {
                Button("Generate start OTP") { Task { await viewModel.generateStartOtp(app) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else if s == ApplicationStatus.completionPending {
                Button("Verify completion") { Task { await viewModel.generateCompletionOtp(app) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
}
