import SwiftUI
import Shared

/// The worker's work-session screen for one hired application. Renders the
/// current stage of the OTP loop and the matching action:
///
///  - SELECTED            → "Accept offer"
///  - ACCEPTED / OTP_REQUESTED → enter the start OTP the employer gave you
///  - WORK_IN_PROGRESS    → "Complete work" (generates the completion code)
///  - COMPLETION_PENDING  → read the completion code to your employer (+ regenerate)
///  - terminal/other      → a status line only
///
/// Reached from the "My Applications" list via the row's "Open" affordance.
struct WorkSessionView: View {

    @StateObject private var viewModel: WorkSessionViewModel

    init(applications: any ApplicationRepository, application: Application) {
        _viewModel = StateObject(
            wrappedValue: WorkSessionViewModel(applications: applications, application: application)
        )
    }

    var body: some View {
        Form {
            Section {
                Text(viewModel.application.job?.title ?? "Job").font(.headline)
                if let location = viewModel.application.job?.location {
                    Text(location).font(.subheadline).foregroundStyle(.secondary)
                }
                LabeledContent("Status", value: viewModel.status.toDisplayString())
            }

            stageSection
        }
        .navigationTitle("Work session")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
        .alert("Couldn’t complete that", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })
    }

    @ViewBuilder
    private var stageSection: some View {
        if viewModel.needsAccept {
            Section("You’ve been selected") {
                Text("Accept this offer to confirm you’ll work this gig.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Task { await viewModel.accept() }
                } label: {
                    busyLabel("Accept offer")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        } else if viewModel.needsStartOtp {
            Section("Enter start OTP") {
                Text("Ask your employer for the start code, then enter it here to begin work.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("6-digit code", text: $viewModel.otpInput)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2.monospaced())
                Button {
                    Task { await viewModel.submitStartOtp() }
                } label: {
                    busyLabel("Start work")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy || viewModel.otpInput.trimmingCharacters(in: .whitespaces).count < 4)
            }
        } else if viewModel.isWorking {
            Section("Finish the gig") {
                Text("When you’ve finished the work, generate the completion code and read it to your employer.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Task { await viewModel.completeWork() }
                } label: {
                    busyLabel("Complete work")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        } else if viewModel.awaitingCompletionVerify {
            Section("Read this code to your employer") {
                if let code = viewModel.completionCode {
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    Text("Your employer types this in to finish the gig and release payment.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Generate a new code") {
                        Task { await viewModel.regenerateCompletionCode() }
                    }
                    .disabled(viewModel.isBusy)
                } else {
                    HStack { ProgressView(); Text("Loading code…").foregroundStyle(.secondary) }
                }
            }
        } else {
            Section {
                Text("No action needed right now.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func busyLabel(_ title: String) -> some View {
        if viewModel.isBusy {
            ProgressView()
        } else {
            Text(title)
        }
    }
}
