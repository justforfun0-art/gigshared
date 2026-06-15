import SwiftUI
import Shared

/// OTP login screen — phone entry, then code entry. Thin native UI over the
/// shared AuthRepository via AuthViewModel.
struct AuthView: View {

    @ObservedObject var viewModel: AuthViewModel
    @State private var phone = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.phase {
                case .enterPhone:
                    phoneSection
                case .enterCode(_, let method):
                    codeSection(method: method)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Sign in")
            .disabled(viewModel.isBusy)
            .overlay { if viewModel.isBusy { ProgressView() } }
        }
    }

    private var phoneSection: some View {
        Section("Phone") {
            TextField("Phone number", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            Button("Send code") {
                Task { await viewModel.sendOtp(phone: phone) }
            }
            .disabled(phone.isEmpty)
        }
    }

    private func codeSection(method: String) -> some View {
        Section("Enter the \(method) code") {
            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            Button("Verify") {
                Task { await viewModel.verify(otp: code) }
            }
            .disabled(code.isEmpty)
            Button("Change number", role: .cancel) {
                code = ""
                viewModel.changeNumber()
            }
        }
    }
}
