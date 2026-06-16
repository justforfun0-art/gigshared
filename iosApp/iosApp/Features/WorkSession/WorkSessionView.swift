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
        .navigationTitle(L("ios_work_session"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
        .alert("Couldn’t complete that", isPresented: errorBinding) {
            Button(L("ok"), role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })
    }

    @ViewBuilder
    private var stageSection: some View {
        if viewModel.needsAccept {
            Section(L("youve_been_selected")) {
                Text(L("ios_accept_this_offer_to_confirm_you_ll_work"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Task { await viewModel.accept() }
                } label: {
                    busyLabel(L("ios_accept_offer"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        } else if viewModel.needsStartOtp {
            Section(L("ios_enter_start_otp")) {
                Text(L("ios_ask_your_employer_for_the_start_code_the"))
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("6-digit code", text: $viewModel.otpInput)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2.monospaced())
                Button {
                    Task { await viewModel.submitStartOtp() }
                } label: {
                    busyLabel(L("start_work"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy || viewModel.otpInput.trimmingCharacters(in: .whitespaces).count < 4)
            }
        } else if viewModel.isWorking {
            Section(L("ios_finish_the_gig")) {
                Text(L("ios_when_you_ve_finished_the_work_generate_t"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    Task { await viewModel.completeWork() }
                } label: {
                    busyLabel(L("status_help_complete_work"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy)
            }
        } else if viewModel.awaitingCompletionVerify {
            Section(L("ios_read_this_code_to_your_employer")) {
                if let code = viewModel.completionCode {
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    Text(L("ios_your_employer_types_this_in_to_finish_th"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(L("ios_generate_a_new_code")) {
                        Task { await viewModel.regenerateCompletionCode() }
                    }
                    .disabled(viewModel.isBusy)
                } else {
                    HStack { ProgressView(); Text(L("ios_loading_code")).foregroundStyle(.secondary) }
                }
            }
        } else {
            Section {
                Text(L("ios_no_action_needed_right_now"))
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
