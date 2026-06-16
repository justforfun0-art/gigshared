import SwiftUI
import Shared

/// OTP login — phone entry that auto-advances to code entry once a valid
/// 10-digit number is typed (mirrors Android's LoginScreen). Native UI over the
/// shared AuthRepository via AuthViewModel. The phone field strips non-digits
/// and caps at 10; hitting 10 digits triggers `sendOtp`, which flips the
/// view-model phase to `.enterCode`.
struct AuthView: View {

    @ObservedObject var viewModel: AuthViewModel
    @State private var phone = ""
    @State private var code = ""
    @FocusState private var phoneFocused: Bool
    @FocusState private var codeFocused: Bool

    // Login background gradient (violet-50 → white → indigo-50, matching Android/web).
    private let bgGradient = LinearGradient(
        colors: [
            Color(red: 0xF5/255, green: 0xF3/255, blue: 0xFF/255),
            .white,
            Color(red: 0xEE/255, green: 0xF2/255, blue: 0xFF/255)
        ],
        startPoint: .top, endPoint: .bottom
    )
    private let violet = Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)

    var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 56)
                    appIcon
                    Spacer().frame(height: 20)
                    header

                    switch viewModel.phase {
                    case .enterPhone:
                        phoneBlock
                    case .enterCode(let phoneNumber, let method):
                        codeBlock(phoneNumber: phoneNumber, method: method)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            if viewModel.isBusy {
                Color.black.opacity(0.05).ignoresSafeArea()
                ProgressView()
            }
        }
    }

    // MARK: - Header

    private var appIcon: some View {
        // App-icon tile (asset "AppIcon" rendered into a rounded square; falls
        // back to a clock glyph if the image asset isn't present).
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [violet, Color(red: 0x4F/255, green: 0x46/255, blue: 0xE5/255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "clock.fill")
                .resizable().scaledToFit()
                .padding(24)
                .foregroundStyle(.white)
        }
        .frame(width: 100, height: 100)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(L("app_name"))
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.primary)
            Text(L("splash_tagline"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 36)
    }

    // MARK: - Phone entry

    private var phoneBlock: some View {
        VStack(spacing: 20) {
            Text(L("login_subtitle"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 8) {
                Text("+91")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Enter 10-digit mobile number", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .focused($phoneFocused)
                    .onChange(of: phone) { newValue in
                        // Strip non-digits, cap at 10 (mirrors updatePhoneNumber).
                        let cleaned = String(newValue.filter(\.isNumber).prefix(10))
                        if cleaned != phone { phone = cleaned }
                        viewModel.errorMessage = nil
                        // Auto-advance the moment a valid 10-digit number lands.
                        if cleaned.count == 10 && !viewModel.isBusy {
                            phoneFocused = false
                            Task { await viewModel.sendOtp(phone: cleaned) }
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(phoneFocused ? violet.opacity(0.7) : Color(red: 0xE2/255, green: 0xE8/255, blue: 0xF0/255),
                            lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Button {
                phoneFocused = false
                Task { await viewModel.sendOtp(phone: phone) }
            } label: {
                Text(L("send_otp"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(violet)
            .disabled(phone.count < 10 || viewModel.isBusy)
            .padding(.horizontal, 24)

            Text(L("ios_we_ll_text_you_a_one_time_code_standard_"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .onAppear { phoneFocused = true }
    }

    // MARK: - Code entry

    private func codeBlock(phoneNumber: String, method: String) -> some View {
        VStack(spacing: 20) {
            Text(L("ios_enter_the_code"))
                .font(.title3.weight(.semibold))
            Text("Sent via \(method) to +91 \(phoneNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title2.monospaced())
                .multilineTextAlignment(.center)
                .focused($codeFocused)
                .onChange(of: code) { newValue in
                    let cleaned = String(newValue.filter(\.isNumber).prefix(6))
                    if cleaned != code { code = cleaned }
                    viewModel.errorMessage = nil
                    if cleaned.count == 6 && !viewModel.isBusy {
                        codeFocused = false
                        Task { await viewModel.verify(otp: cleaned) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(violet.opacity(0.7), lineWidth: 1))
                .padding(.horizontal, 24)

            Button {
                codeFocused = false
                Task { await viewModel.verify(otp: code) }
            } label: {
                Text(L("verify"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(violet)
            .disabled(code.count < 4 || viewModel.isBusy)
            .padding(.horizontal, 24)

            Button(L("ios_change_number")) {
                code = ""
                viewModel.changeNumber()
            }
            .font(.subheadline)
            .tint(violet)
        }
        .onAppear { codeFocused = true }
    }
}
