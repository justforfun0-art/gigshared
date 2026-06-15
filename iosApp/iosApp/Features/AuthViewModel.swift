import Foundation
import Shared

/// Drives the OTP login flow over the shared `AuthRepository`. Two phases:
/// enter phone → send OTP → enter code → verify. On success the verified
/// `AuthData` is published; the app swaps to the signed-in UI.
///
/// Uses the IosHelpers `*OrThrow` shims so Kotlin `Result` surfaces as Swift
/// `async throws` (plain Result boxes opaquely over Obj-C).
@MainActor
final class AuthViewModel: ObservableObject {

    enum Phase: Equatable {
        case enterPhone
        case enterCode(phone: String, method: String)
    }

    @Published private(set) var phase: Phase = .enterPhone
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published private(set) var session: AuthData?

    private let auth: any AuthRepository
    private var authStateTask: Task<Void, Never>?

    init(auth: any AuthRepository) {
        self.auth = auth
    }

    deinit { authStateTask?.cancel() }

    var isSignedIn: Bool { session != nil }

    /// Reactively track the persisted session via the shared `getAuthState()`
    /// Flow, which SKIE bridges to a Swift `AsyncSequence`. This makes login
    /// state observed rather than only set imperatively in `verify` — e.g. a
    /// session restored on launch or cleared by `logout()` propagates here
    /// without an explicit reload. Call once from the root view's `.task`.
    func startObserving() {
        guard authStateTask == nil else { return }
        // SKIE bridges a plain Kotlin `Flow` to a non-throwing `AsyncSequence`,
        // so this is `for await` (no `try`). Iteration ends when the task is
        // cancelled (deinit) or the Flow completes.
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.auth.getAuthState() {
                self.session = state
                if state == nil { self.phase = .enterPhone }
            }
        }
    }

    func sendOtp(phone: String) async {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Enter your phone number"; return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let result = try await IosHelpersKt.sendOtpOrThrow(auth, phone: trimmed)
            if result.success {
                phase = .enterCode(phone: trimmed, method: result.method)
            } else {
                // Surface server message + rate-limit hint (retryAfter).
                if let retry = result.retryAfter {
                    errorMessage = (result.error ?? "Too many attempts.") + " Try again in \(retry.intValue)s."
                } else {
                    errorMessage = result.error ?? "Couldn’t send the code."
                }
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func verify(otp: String) async {
        guard case let .enterCode(phone, _) = phase else { return }
        let code = otp.trimmingCharacters(in: .whitespaces)
        guard code.count >= 4 else { errorMessage = "Enter the code you received"; return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            // verifyOtpOrThrow throws on wrong/expired OTP with the server's
            // message; on success it has already persisted the session (the
            // NonCancellable save in AuthRepositoryImpl).
            let data = try await IosHelpersKt.verifyOtpOrThrow(auth, phone: phone, otp: code)
            session = data
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func changeNumber() {
        phase = .enterPhone
        errorMessage = nil
    }

    func signOut() async {
        try? await auth.logout()
        session = nil
        phase = .enterPhone
    }
}
