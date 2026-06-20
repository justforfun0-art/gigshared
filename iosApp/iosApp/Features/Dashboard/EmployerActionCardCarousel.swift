import SwiftUI
import Shared

/// Employer Home action-card carousel (Android ActionCardCarousel, isEmployer=true).
/// Surfaces in-flight applicants to the employer's jobs as status cards:
///   ACCEPTED / OTP_REQUESTED → green WorkerAccepted card; generate + show the
///     6-digit start OTP INLINE (read it to the worker).
///   WORK_IN_PROGRESS / COMPLETION_PENDING → indigo card → View Progress / Enter
///     Code (opens the applicant detail / completion-entry).
///   PAYMENT_PENDING → amber card → Process Payment (opens the Payments flow).
struct EmployerActionCardCarousel: View {
    let applications: any ApplicationRepository
    let employerId: String
    /// Open the applicant/detail screen for an application (View Progress / Enter Code).
    let onOpenApplicant: (Application) -> Void
    /// Open the Payments flow (Process Payment).
    let onProcessPayment: (Application) -> Void

    @StateObject private var viewModel: EmployerActionCarouselViewModel
    @State private var containerWidth: CGFloat = 0

    init(applications: any ApplicationRepository, employerId: String,
         onOpenApplicant: @escaping (Application) -> Void,
         onProcessPayment: @escaping (Application) -> Void) {
        self.applications = applications
        self.employerId = employerId
        self.onOpenApplicant = onOpenApplicant
        self.onProcessPayment = onProcessPayment
        _viewModel = StateObject(wrappedValue: EmployerActionCarouselViewModel(
            applications: applications, employerId: employerId
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.items.isEmpty {
                Label(L("ios_needs_your_attention"), systemImage: "person.badge.clock")
                    .font(.headline)
                GeometryReader { geo in
                    let spacing: CGFloat = 12
                    let peek: CGFloat = viewModel.items.count > 1 ? 36 : 0
                    let cardWidth = max(geo.size.width - peek, 1)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(viewModel.items, id: \.id) { app in
                                EmployerActionCard(
                                    application: app,
                                    count: viewModel.items.count,
                                    otp: viewModel.otps[app.id],
                                    isBusy: viewModel.busyId == app.id,
                                    onGenerateOtp: { Task { await viewModel.generateOtp(app) } },
                                    onOpen: { onOpenApplicant(app) },
                                    onProcessPayment: { onProcessPayment(app) }
                                )
                                .frame(width: cardWidth)
                            }
                        }
                    }
                }
                .frame(height: 220)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task { await viewModel.load() }
        .alert("Couldn’t complete that", isPresented: errorBinding) {
            Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
        } message: { Text(viewModel.actionError ?? "") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }
}

// MARK: - Card

private struct EmployerActionCard: View {
    let application: Application
    let count: Int
    let otp: String?
    let isBusy: Bool
    let onGenerateOtp: () -> Void
    let onOpen: () -> Void
    let onProcessPayment: () -> Void

    private var applicantName: String { application.employeeProfile?.name ?? "Applicant" }
    private var jobTitle: String { application.job?.title ?? "Job" }

    var body: some View {
        switch application.status {
        case .accepted, .otpRequested:
            workerAcceptedCard
        case .workInProgress, .completionPending:
            inProgressCard
        case .paymentPending:
            paymentPendingCard
        default:
            inProgressCard
        }
    }

    // ACCEPTED / OTP_REQUESTED — green, inline OTP.
    private var workerAcceptedCard: some View {
        let hasOtp = (otp?.isEmpty == false)
        return cardShell(grad(0x10B981, 0x059669)) {
            header(hasOtp ? L("emp_otp_ready") : L("emp_worker_accepted"),
                   hasOtp ? L("emp_share_otp") : L("emp_generate_otp"))
            innerPanel {
                workerRow(avatar: grad(0x34D399, 0x10B981))
                if hasOtp, let otp {
                    // Big spaced OTP for the employer to read out.
                    Text(otp.map(String.init).joined(separator: " "))
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(GHTheme.hex(0x059669))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    cta(L("emp_regenerate_otp"), grad(0x34D399, 0x059669), busy: isBusy, action: onGenerateOtp)
                } else {
                    cta(L("emp_generate_otp_cta"), grad(0x34D399, 0x059669), icon: "key.fill", busy: isBusy, action: onGenerateOtp)
                }
            }
            Spacer(minLength: 8)
            footer(hasOtp ? L("emp_read_otp_hint") : L("emp_tap_generate_hint"), onOpen)
        }
    }

    // WORK_IN_PROGRESS / COMPLETION_PENDING — indigo.
    private var inProgressCard: some View {
        let completion = application.status == .completionPending
        return cardShell(grad(0x6366F1, 0x7C3AED)) {
            header(completion ? L("emp_work_completed") : L("emp_in_progress"),
                   completion ? L("emp_enter_code_sub") : L("emp_worker_working"))
            innerPanel {
                workerRow(avatar: grad(0x34D399, 0x10B981))
                cta(completion ? L("emp_enter_code") : L("emp_view_progress"),
                    completion ? grad(0x10B981, 0x059669) : grad(0x6366F1, 0x4F46E5),
                    icon: completion ? "checkmark.seal.fill" : "chart.bar.fill",
                    action: onOpen)
            }
            Spacer(minLength: 8)
            footer(completion ? L("emp_tap_enter_code_hint") : L("emp_tap_view_progress_hint"), onOpen)
        }
    }

    // PAYMENT_PENDING — amber.
    private var paymentPendingCard: some View {
        cardShell(grad(0xF59E0B, 0xD97706)) {
            header(L("emp_payment_pending"), L("emp_process_payment_sub"))
            innerPanel {
                workerRow(avatar: grad(0xFBBF24, 0xF59E0B))
                if let amt = application.paymentAmount?.doubleValue, amt > 0 {
                    HStack {
                        Text(L("estimated_payment_label")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                        Spacer()
                        Text(Money.rupees(amt)).font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.hex(0xD97706))
                    }
                }
                cta(L("emp_process_payment"), grad(0xFBBF24, 0xD97706), icon: "creditcard.fill", action: onProcessPayment)
            }
            Spacer(minLength: 8)
            footer(L("emp_tap_process_payment_hint"), onOpen)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func header(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.weight(.bold)).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
            Text("\(count)").font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(.white.opacity(0.2), in: Circle())
        }
    }

    private func workerRow(avatar: LinearGradient) -> some View {
        HStack(spacing: 10) {
            Circle().fill(avatar).frame(width: 40, height: 40)
                .overlay(Text(String(applicantName.prefix(1)).uppercased())
                    .font(.headline).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(applicantName).font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                Text(jobTitle).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func innerPanel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func cta(_ title: String, _ gradient: LinearGradient, icon: String? = nil, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy { ProgressView().tint(.white) }
                else {
                    if let icon { Image(systemName: icon).font(.caption.weight(.bold)) }
                    Text(title).font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(gradient, in: Capsule())
        }
        .buttonStyle(.plain).disabled(busy)
    }

    private func footer(_ hint: String, _ onTap: @escaping () -> Void) -> some View {
        HStack {
            Text(hint).font(.caption).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onTap) {
                HStack(spacing: 2) { Text(L("view_details")).font(.caption.weight(.semibold)); Text("→").font(.caption) }
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
    }

    private func cardShell<C: View>(_ gradient: LinearGradient, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            .background(gradient, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private func grad(_ a: UInt, _ b: UInt) -> LinearGradient {
        LinearGradient(colors: [GHTheme.hex(a), GHTheme.hex(b)], startPoint: .top, endPoint: .bottom)
    }
}
