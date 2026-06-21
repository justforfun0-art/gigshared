import SwiftUI
import Shared

/// "Application Status" — the full application detail screen (port of Android's
/// ApplicationDetailsScreen). Top to bottom: a status-colored hero banner, a Job
/// Details card, the Application Progress timeline (wavy violet ribbon + 8
/// stages), a Work Summary card (when a work session exists), a Contact Employer
/// card, and the "Applied on …" footer.
struct ApplicationStatusView: View {
    let application: Application
    /// Messaging deps (optional so previews/older call sites still compile).
    var messages: (any MessageRepository)? = nil
    var myUserId: String? = nil
    /// Needed for the WORK_IN_PROGRESS live card (timer + complete). Optional so
    /// older call sites still compile; the WIP card only shows when present.
    var applications: (any ApplicationRepository)? = nil
    /// Tapped from the "Browse Jobs" CTA on terminal statuses (rejected/withdrawn).
    var onBrowseJobs: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var openingChat = false
    @State private var chat: ChatTarget? = nil
    @State private var completionCode: String? = nil
    @State private var openSession = false
    @State private var showWithdrawConfirm = false
    @State private var withdrawing = false
    @State private var actionError: String?
    // Inline completion code (COMPLETION_PENDING) — loaded from the work session.
    @State private var pendingCode: String?
    @State private var loadingCode = false
    @State private var regenerating = false

    private var job: Job? { application.job }

    /// A resolved conversation to push to (drives the chat NavigationDestination).
    struct ChatTarget: Identifiable, Hashable {
        let id: String          // conversation id
        let receiverId: String
        let title: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                VStack(spacing: 16) {
                    // Live work-in-progress card (timer + earnings + complete),
                    // mirroring Android's WorkTimerDisplay. Only while working.
                    if application.status == .workInProgress, let applications {
                        WorkInProgressDetailCard(
                            applications: applications,
                            application: application,
                            onCompleted: { completionCode = $0 }
                        )
                    }
                    actionSection
                    jobDetailsCard
                    ApplicationProgressTimeline(status: application.status)
                    contextBanner
                    contactCard
                    Text("Applied on \(appliedFooter)")
                        .font(.footnote).foregroundStyle(GHTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .background(GHTheme.hex(0xF8F9FB).ignoresSafeArea())
        .navigationTitle(L("application_status"))
        .navigationBarTitleDisplayMode(.inline)
        // iOS 16-compatible push (navigationDestination(item:) is iOS 17+).
        .background(
            NavigationLink(isActive: chatActive) {
                if let messages, let myUserId, let target = chat {
                    ConversationView(repo: messages, conversationId: target.id,
                                     myUserId: myUserId, receiverId: target.receiverId,
                                     title: target.title)
                }
            } label: { EmptyView() }
            .hidden()
        )
        // After "Tap to complete", show the completion code to read to the
        // employer (reuses the FOB/carousel sheet).
        .sheet(isPresented: completionActive) {
            if let code = completionCode, let applications {
                WorkerCompletionCodeSheet(
                    code: code,
                    onRegenerate: { try? await IosHelpersKt.regenerateCompletionOtpOrThrow(applications, applicationId: application.id) },
                    onDone: { completionCode = nil }
                )
            }
        }
        // The action-loop screen (accept / enter start OTP / complete / read code),
        // reached from the per-status primary action button.
        .background(
            NavigationLink(isActive: $openSession) {
                if let applications {
                    WorkSessionView(applications: applications, application: application)
                }
            } label: { EmptyView() }.hidden()
        )
        .alert(L("withdraw_application"), isPresented: $showWithdrawConfirm) {
            Button(L("cancel_filter"), role: .cancel) {}
            Button(L("withdraw_application"), role: .destructive) { Task { await withdraw() } }
        } message: { Text(L("ios_withdraw_confirm")) }
        .alert("Action failed", isPresented: actionErrorBinding) {
            Button(L("ok"), role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    /// Per-status primary action — Android's ApplicationDetails action block.
    /// Lifecycle actions reuse WorkSessionView (which has the right stage UI);
    /// APPLIED withdraws inline; terminal statuses offer "Browse Jobs".
    @ViewBuilder
    private var actionSection: some View {
        switch application.status {
        case .selected:
            primaryAction(L("accept_job"), "checkmark.circle.fill") { openSession = true }
        case .accepted:
            primaryAction(L("start_work"), "play.fill") { openSession = true }
        case .otpRequested:
            primaryAction(L("enter_otp_btn"), "key.fill") { openSession = true }
        case .completionPending:
            completionCodeCard
        case .applied, .shortlisted:
            if applications != nil {
                Button { showWithdrawConfirm = true } label: {
                    if withdrawing { ProgressView().frame(maxWidth: .infinity) }
                    else { Label(L("withdraw_application"), systemImage: "xmark.circle").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.bordered).tint(GHTheme.error).controlSize(.large)
                .disabled(withdrawing)
            }
        case .rejected, .rejectedOnce, .rejectedAndReshown, .noShow, .withdrawn, .notInterested, .expired, .positionFilled:
            primaryAction(L("browse_jobs_action"), "magnifyingglass") { browseJobs() }
        default:
            EmptyView()
        }
    }

    /// Inline completion-code card (Android's COMPLETION_PENDING card): green
    /// check + "share this code", the big monospace code, and Generate New Code.
    private var completionCodeCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Circle().fill(GHTheme.hex(0xD1FAE5)).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "checkmark.circle.fill").foregroundStyle(GHTheme.hex(0x10B981)))
                Text(L("share_code_to_verify"))
                    .font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                Spacer(minLength: 0)
            }
            Text(pendingCode ?? "------")
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .kerning(8)
                .foregroundStyle(GHTheme.hex(0x10B981))
                .frame(maxWidth: .infinity)
                .redacted(reason: loadingCode && pendingCode == nil ? .placeholder : [])

            Button { Task { await regenerateCode() } } label: {
                if regenerating { ProgressView().frame(maxWidth: .infinity) }
                else { Label(L("generate_new_code"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered).tint(GHTheme.hex(0x10B981)).controlSize(.large)
            .disabled(regenerating)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
        .task { await loadCode() }
    }

    /// Pull the existing completion OTP from the work session (Android shows the
    /// already-generated code, not a fresh one).
    private func loadCode() async {
        guard pendingCode == nil, let applications, !loadingCode else { return }
        loadingCode = true
        defer { loadingCode = false }
        if let session = try? await IosHelpersKt.getWorkSessionOrThrow(applications, applicationId: application.id),
           let otp = session.completionOtp, !otp.isEmpty {
            pendingCode = otp
        }
    }

    private func regenerateCode() async {
        guard let applications else { return }
        regenerating = true
        defer { regenerating = false }
        if let code = try? await IosHelpersKt.regenerateCompletionOtpOrThrow(applications, applicationId: application.id) {
            pendingCode = code
        }
    }

    /// Switch to the jobs feed if a handler was supplied; otherwise just pop back
    /// to the list (where the user can pick the Jobs tab).
    private func browseJobs() {
        if let onBrowseJobs { onBrowseJobs() } else { dismiss() }
    }

    private func primaryAction(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(GHTheme.primary).controlSize(.large)
    }

    private func withdraw() async {
        guard let applications else { return }
        withdrawing = true
        defer { withdrawing = false }
        do {
            _ = try await IosHelpersKt.withdrawApplicationOrThrow(applications, applicationId: application.id)
            browseJobs()   // bounce back to the feed after a successful withdraw
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }

    private var completionActive: Binding<Bool> {
        Binding(get: { completionCode != nil }, set: { if !$0 { completionCode = nil } })
    }

    private var chatActive: Binding<Bool> {
        Binding(get: { chat != nil }, set: { if !$0 { chat = nil } })
    }

    /// Open (or create) the conversation with this job's employer, then navigate.
    private func openChat() {
        guard let messages, let myUserId, let employerId = job?.employerId, !openingChat else { return }
        openingChat = true
        Task {
            defer { openingChat = false }
            do {
                let convo = try await IosHelpersKt.getOrCreateConversationOrThrow(
                    messages, employeeId: myUserId, employerId: employerId, jobId: job?.id
                )
                chat = ChatTarget(id: convo.id, receiverId: employerId,
                                  title: job?.employerProfile?.companyName ?? "Employer")
            } catch {
                // Surface silently for now; a fuller UI could show an alert.
            }
        }
    }

    // MARK: - Hero banner

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 56, height: 56)
                Circle().fill(.white.opacity(0.20)).frame(width: 42, height: 42)
                Image(systemName: Self.statusIcon(application.status))
                    .font(.system(size: 22)).foregroundStyle(.white)
            }
            Text(application.status.toDisplayString())
                .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            Text(Self.statusDescription(application.status))
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 22)
        .background(
            LinearGradient(colors: Self.statusGradient(application.status),
                           startPoint: .leading, endPoint: .trailing)
        )
    }

    // MARK: - Job details

    private var jobDetailsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("job_details_label")).font(.title3.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                detailRow(icon: "briefcase.fill", label: "Job Title", value: job?.title ?? "—")
                detailRow(icon: "mappin.and.ellipse", label: "Location",
                          value: [job?.district, job?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ").ifEmptyDash())
                detailRow(icon: "calendar", label: "Date & Time", value: dateTimeLine)
                detailRow(icon: "indianrupeesign", label: "Salary",
                          value: job?.salaryRange ?? "—", valueColor: GHTheme.tertiaryVariant)
                if JobLocation.parse(job?.workGoogleMapLocation) != nil {
                    JobLocationMap(location: job?.workGoogleMapLocation,
                                   addressFallback: job?.workAddress ?? job?.location)
                }
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String, valueColor: Color = GHTheme.onBackground) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(GHTheme.onSurfaceVariant).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(value).font(.body.weight(.semibold)).foregroundStyle(valueColor)
            }
            Spacer()
        }
    }

    private var dateTimeLine: String {
        let date = formatJobDate(job?.jobDate) ?? "—"
        if let s = job?.startTime, let e = job?.endTime {
            return "\(date) • \(s) - \(e)"
        }
        return date
    }

    // MARK: - Contextual banner + contact

    @ViewBuilder
    private var contextBanner: some View {
        if let (text, tint) = Self.contextBanner(application.status) {
            HStack(spacing: 12) {
                Circle().fill(tint.opacity(0.18)).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "creditcard.fill").foregroundStyle(tint))
                Text(text).font(.subheadline).foregroundStyle(GHTheme.onBackground)
                Spacer()
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(GHTheme.outline, lineWidth: 1))
        }
    }

    private var contactCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("contact_employer")).font(.title3.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                Button { openChat() } label: {
                    HStack {
                        if openingChat { ProgressView().tint(.white) }
                        else { Label(L("message"), systemImage: "message.fill") }
                    }
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(GHTheme.tertiaryVariant, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(messages == nil || openingChat)
            }
        }
    }

    private var appliedFooter: String {
        formatJobDate(application.appliedAt ?? application.createdAt) ?? "—"
    }

    // MARK: - Card chrome

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(GHTheme.outline, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: - Status → visuals (mirrors Android getStatus*)

    static func statusGradient(_ s: ApplicationStatus) -> [Color] {
        switch s {
        case .applied, .shortlisted: return [GHTheme.hex(0x3B82F6), GHTheme.hex(0x2563EB)]
        case .selected: return [GHTheme.hex(0x8B5CF6), GHTheme.hex(0x7C3AED)]
        case .accepted, .hired: return [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)]
        case .otpRequested: return [GHTheme.hex(0x6366F1), GHTheme.hex(0x4F46E5)]
        case .workInProgress: return [GHTheme.hex(0x312E81), GHTheme.hex(0x4338CA)]
        case .completionPending, .paymentPending: return [GHTheme.hex(0xF59E0B), GHTheme.hex(0xD97706)]
        case .completed: return [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)]
        case .rejected, .rejectedOnce, .rejectedAndReshown, .noShow:
            return [GHTheme.hex(0xEF4444), GHTheme.hex(0xDC2626)]
        default: return [GHTheme.hex(0x6B7280), GHTheme.hex(0x4B5563)]
        }
    }

    static func statusIcon(_ s: ApplicationStatus) -> String {
        switch s {
        case .applied, .shortlisted: return "paperplane.fill"
        case .selected: return "checkmark.circle.fill"
        case .accepted, .hired: return "hand.thumbsup.fill"
        case .otpRequested: return "key.fill"
        case .workInProgress: return "play.fill"
        case .completionPending: return "checkmark"
        case .paymentPending: return "creditcard.fill"
        case .completed: return "star.fill"
        case .expired: return "nosign"
        default: return "xmark.circle.fill"
        }
    }

    static func statusDescription(_ s: ApplicationStatus) -> String {
        switch s {
        case .applied: return "Your application is being reviewed by the employer"
        case .shortlisted: return "You have been shortlisted for this position"
        case .selected: return "Congratulations! You have been selected for this job"
        case .accepted, .hired: return "You accepted this job. Wait for further instructions"
        case .otpRequested: return "The employer has requested verification"
        case .workInProgress: return "Work session is in progress"
        case .completionPending: return "Waiting for work completion confirmation"
        case .paymentPending: return "Work completed. Payment is pending"
        case .completed: return "Job completed successfully"
        case .rejected, .rejectedOnce: return "Unfortunately, your application was not selected"
        case .expired: return "This job posting has expired"
        case .withdrawn: return "You withdrew your application"
        case .noShow: return "Marked as no-show by the employer"
        default: return ""
        }
    }

    static func contextBanner(_ s: ApplicationStatus) -> (String, Color)? {
        switch s {
        case .paymentPending: return ("Work completed. Waiting for employer to process payment.", GHTheme.warning)
        case .completionPending: return ("Awaiting employer verification of your work.", GHTheme.warning)
        case .completed: return ("Payment credited to your account.", GHTheme.success)
        default: return nil
        }
    }
}

private extension String {
    func ifEmptyDash() -> String { isEmpty ? "—" : self }
}

/// The "Application Progress" card — a vertical wavy violet ribbon connecting 8
/// stage nodes. Completed: purple gradient disc + check. Current: purple disc +
/// step icon + halo + "Current step" pill. Future: white disc + lock + muted.
private struct ApplicationProgressTimeline: View {
    let status: ApplicationStatus

    struct Step { let label: String; let description: String; let icon: String; let statuses: [ApplicationStatus] }
    static let steps: [Step] = [
        Step(label: "Applied", description: "Your application has been sent to the employer.",
             icon: "paperplane.fill", statuses: [.applied, .shortlisted]),
        Step(label: "Selected", description: "You’ve been shortlisted. Tap Accept to confirm.",
             icon: "checkmark.circle.fill", statuses: [.selected]),
        Step(label: "Accepted", description: "Your application has been accepted.",
             icon: "hand.thumbsup.fill", statuses: [.accepted, .hired]),
        Step(label: "OTP Requested", description: "Wait at the job site. The employer will generate a Start OTP for you.",
             icon: "key.fill", statuses: [.otpRequested]),
        Step(label: "Working", description: "Work in progress. Track your hours on the job.",
             icon: "play.fill", statuses: [.workInProgress]),
        Step(label: "Awaiting Verification", description: "We are verifying your work and details.",
             icon: "checkmark", statuses: [.completionPending]),
        Step(label: "Payment Pending", description: "Payment is being processed.",
             icon: "creditcard.fill", statuses: [.paymentPending]),
        Step(label: "Completed", description: "Job completed. Payment will be credited to your account.",
             icon: "star.fill", statuses: [.completed]),
    ]

    private let gradTop = GHTheme.hex(0x8B5CF6)
    private let gradBottom = GHTheme.hex(0x5B21B6)
    private let ribbon = GHTheme.hex(0x8B5CF6)
    private let futureRibbon = GHTheme.hex(0xE9D5FF)
    private let rowHeight: CGFloat = 104
    private let railWidth: CGFloat = 64

    private var currentIndex: Int {
        Self.steps.firstIndex { $0.statuses.contains(status) } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("application_progress_title")).font(.title2.weight(.bold)).foregroundStyle(GHTheme.hex(0x1F2937))

            // The ribbon Canvas is pinned to the LEFT rail (railWidth wide) and
            // sits behind the rows, whose node column is the same railWidth — so
            // the wave threads through the node centers instead of drifting to
            // the screen center.
            ZStack(alignment: .topLeading) {
                ribbonCanvas
                    .frame(width: railWidth, height: rowHeight * CGFloat(Self.steps.count))
                VStack(spacing: 0) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                        stageRow(step, index: i).frame(height: rowHeight)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GHTheme.hex(0xF7F4FC), in: RoundedRectangle(cornerRadius: 24))
    }

    /// The continuous, gently-breathing sine ribbon down the left rail — a sine
    /// whose zero-crossings land on each node center (so it threads through every
    /// node) and bows out between them. Light-violet for the full length, then
    /// the brand violet overdrawn up to the active node, plus a white shimmer
    /// gliding down the travelled portion. Animated via TimelineView.
    private var ribbonCanvas: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // breathe: 7s amplitude pulse (matches Android wavePhase).
            let breathe = 0.85 + 0.15 * sin(t * (2 * .pi / 7))
            // shimmer: 0..1 glide every 2.6s.
            let shimmer = (t.truncatingRemainder(dividingBy: 2.6)) / 2.6

            Canvas { ctx, size in
                let cx = railWidth / 2
                let amp: CGFloat = 12
                let total = Self.steps.count
                func nodeY(_ i: Int) -> CGFloat { rowHeight * CGFloat(i) + rowHeight / 2 }
                // Sine zero-crossings on node centers; bow between.
                func waveX(_ y: CGFloat) -> CGFloat {
                    let phase = y / rowHeight - 0.5
                    return cx + amp * CGFloat(breathe) * CGFloat(sin(Double(phase) * .pi))
                }
                func snake(_ y0: CGFloat, _ y1: CGFloat) -> Path {
                    var p = Path()
                    p.move(to: CGPoint(x: waveX(y0), y: y0))
                    var y = y0
                    let stepPx = rowHeight / 12
                    while y < y1 { y += stepPx; p.addLine(to: CGPoint(x: waveX(y), y: y)) }
                    p.addLine(to: CGPoint(x: waveX(y1), y: y1))
                    return p
                }

                let startY = nodeY(0)
                let endY = nodeY(total - 1)

                // Future ribbon (light) for the full length.
                ctx.stroke(snake(startY, endY), with: .color(futureRibbon),
                           style: StrokeStyle(lineWidth: 18, lineCap: .round))

                // Travelled portion in brand violet, up to the active node.
                let reachedEnd = nodeY(min(max(currentIndex, 0), total - 1))
                if reachedEnd > startY {
                    ctx.stroke(snake(startY, reachedEnd), with: .color(ribbon),
                               style: StrokeStyle(lineWidth: 18, lineCap: .round))

                    // White shimmer sliding down the travelled portion.
                    let shimmerY = startY + (reachedEnd - startY) * CGFloat(shimmer)
                    let glow = rowHeight * 0.9
                    let top = max(shimmerY - glow / 2, startY)
                    let bot = min(shimmerY + glow / 2, reachedEnd)
                    if bot > top {
                        ctx.stroke(snake(top, bot), with: .color(.white.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func stageRow(_ step: Step, index: Int) -> some View {
        let isCompleted = index < currentIndex
        let isCurrent = index == currentIndex
        let reached = isCompleted || isCurrent
        return HStack(alignment: .center, spacing: 14) {
            node(step, isCompleted: isCompleted, isCurrent: isCurrent)
                .frame(width: railWidth)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.label)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(reached ? GHTheme.hex(0x1F2937) : GHTheme.muted)
                if isCurrent {
                    Text(L("timeline_current_step_pill"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GHTheme.hex(0x6D28D9))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(GHTheme.hex(0xEDE9FE), in: RoundedRectangle(cornerRadius: 10))
                }
                Text(step.description)
                    .font(.subheadline)
                    .foregroundStyle(reached ? GHTheme.hex(0x5B6470) : GHTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func node(_ step: Step, isCompleted: Bool, isCurrent: Bool) -> some View {
        let reached = isCompleted || isCurrent
        ZStack {
            if isCurrent {
                Circle().fill(GHTheme.hex(0xEDE6FB)).frame(width: 58, height: 58)
                    .shadow(color: ribbon.opacity(0.4), radius: 8)
            }
            Circle().fill(.white).frame(width: 46, height: 46)
                .shadow(color: gradBottom.opacity(0.35), radius: 5)
            if reached {
                Circle()
                    .fill(LinearGradient(colors: [gradTop, gradBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: 38, height: 38)
                Image(systemName: isCompleted ? "checkmark" : step.icon)
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().fill(GHTheme.hex(0xF3F0FA)).frame(width: 38, height: 38)
                    .overlay(Circle().stroke(GHTheme.outline, lineWidth: 1.5))
                Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(GHTheme.hex(0xB9C0CC))
            }
        }
    }
}
