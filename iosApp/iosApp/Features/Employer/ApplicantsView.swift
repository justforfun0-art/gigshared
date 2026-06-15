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
            .sheet(item: $viewModel.verifyingCompletion) { app in
                CompletionCodeSheet(app: app, viewModel: viewModel)
            }
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
            } else if s == ApplicationStatus.workInProgress {
                Label("Work in progress", systemImage: "clock")
                    .font(.caption).foregroundStyle(.orange)
            } else if s == ApplicationStatus.completionPending {
                Button("Enter completion code") { viewModel.beginCompletionVerify(app) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
}

/// Modal where the employer types the 6-digit completion code the worker read
/// out, finishing the gig (`verifyCompletionOtp`).
private struct CompletionCodeSheet: View {
    let app: Application
    @ObservedObject var viewModel: ApplicantsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(app.employeeProfile?.name ?? "Worker").font(.headline)
                    Text("Ask the worker for their completion code and enter it below to finish the gig and release payment.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    TextField("6-digit code", text: $viewModel.completionInput)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.monospaced())
                }
                if let err = viewModel.actionError {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Complete gig")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.verifyingCompletion = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { Task { await viewModel.submitCompletionCode() } }
                        .disabled(viewModel.isVerifying
                                  || viewModel.completionInput.trimmingCharacters(in: .whitespaces).count != 6)
                }
            }
        }
    }
}

/// `Application` comes from the Kotlin framework without Swift's `Identifiable`;
/// its stable `id` lets it drive `sheet(item:)` / `ForEach`.
extension Application: Identifiable {}
