import Foundation
import Shared

/// Backs the employer Home action-card carousel (Android ActionCardCarousel with
/// isEmployer=true). Loads the in-flight applicants to the employer's jobs and
/// supports generating/showing the start OTP inline on the WorkerAccepted card.
@MainActor
final class EmployerActionCarouselViewModel: ObservableObject {

    /// Stage order for the cards (most-urgent first).
    private static let order: [ApplicationStatus] = [
        .accepted, .otpRequested, .workInProgress, .completionPending, .paymentPending
    ]

    @Published private(set) var items: [Application] = []
    /// Start OTPs the employer generated, keyed by application id (shown inline).
    @Published private(set) var otps: [String: String] = [:]
    @Published private(set) var busyId: String?
    @Published var actionError: String?

    private let applications: any ApplicationRepository
    private let employerId: String

    init(applications: any ApplicationRepository, employerId: String) {
        self.applications = applications
        self.employerId = employerId
    }

    func load() async {
        do {
            let all = try await IosHelpersKt.getActiveEmployerApplicationsOrThrow(
                applications, employerId: employerId
            )
            items = all
                .filter { Self.order.contains($0.status) }
                .sorted { lhs, rhs in
                    let l = Self.order.firstIndex(of: lhs.status) ?? Int.max
                    let r = Self.order.firstIndex(of: rhs.status) ?? Int.max
                    if l != r { return l < r }
                    return (lhs.updatedAt ?? lhs.appliedAt ?? "") > (rhs.updatedAt ?? rhs.appliedAt ?? "")
                }
            // Pre-load any already-issued start OTPs (OTP_REQUESTED) so the card
            // shows the code without the employer regenerating.
            await loadExistingOtps()
        } catch {
            items = []
        }
    }

    private func loadExistingOtps() async {
        for app in items where app.status == .otpRequested {
            if let session = try? await IosHelpersKt.getWorkSessionOrThrow(applications, applicationId: app.id),
               !session.otp.isEmpty {
                otps[app.id] = session.otp
            }
        }
    }

    /// Generate (ACCEPTED) or re-issue (OTP_REQUESTED) the start OTP; show inline.
    func generateOtp(_ app: Application) async {
        busyId = app.id; actionError = nil
        defer { busyId = nil }
        do {
            let otp = try await IosHelpersKt.generateStartOtpOrThrow(applications, applicationId: app.id)
            otps[app.id] = otp
            await load()   // refresh so status flips ACCEPTED → OTP_REQUESTED
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }
}
