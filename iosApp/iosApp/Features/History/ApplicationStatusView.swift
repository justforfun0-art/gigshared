import SwiftUI
import Shared

/// "Application Status" — the full application detail screen (port of Android's
/// ApplicationDetailsScreen). Top to bottom: a status-colored hero banner, a Job
/// Details card, the Application Progress timeline (wavy violet ribbon + 8
/// stages), a Work Summary card (when a work session exists), a Contact Employer
/// card, and the "Applied on …" footer.
struct ApplicationStatusView: View {
    let application: Application

    private var job: Job? { application.job }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                VStack(spacing: 16) {
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
        .navigationTitle("Application Status")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("Job Details").font(.title3.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                detailRow(icon: "briefcase.fill", label: "Job Title", value: job?.title ?? "—")
                detailRow(icon: "mappin.and.ellipse", label: "Location",
                          value: [job?.district, job?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ").ifEmptyDash())
                detailRow(icon: "calendar", label: "Date & Time", value: dateTimeLine)
                detailRow(icon: "indianrupeesign", label: "Salary",
                          value: job?.salaryRange ?? "—", valueColor: GHTheme.tertiaryVariant)
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
                Text("Contact Employer").font(.title3.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                Button { } label: {
                    Label("Message", systemImage: "message.fill")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(GHTheme.tertiaryVariant, in: RoundedRectangle(cornerRadius: 14))
                }
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
            Text("Application Progress").font(.title2.weight(.bold)).foregroundStyle(GHTheme.hex(0x1F2937))

            ZStack(alignment: .top) {
                ribbonCanvas
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

    /// The continuous S-curve ribbon down the rail, violet up to the active node
    /// then light-violet beyond (drawn behind the nodes).
    private var ribbonCanvas: some View {
        Canvas { ctx, size in
            let cx = railWidth / 2
            let total = Self.steps.count
            func y(_ i: Int) -> CGFloat { rowHeight * CGFloat(i) + rowHeight / 2 }
            // Build one wavy path through all node centers.
            var path = Path()
            path.move(to: CGPoint(x: cx, y: y(0)))
            for i in 1..<total {
                let prev = CGPoint(x: cx, y: y(i - 1))
                let cur = CGPoint(x: cx, y: y(i))
                let midY = (prev.y + cur.y) / 2
                let bow: CGFloat = (i % 2 == 0) ? 12 : -12
                path.addCurve(
                    to: cur,
                    control1: CGPoint(x: cx + bow, y: midY - 6),
                    control2: CGPoint(x: cx + bow, y: midY + 6)
                )
            }
            // Full path in the future color, then overdraw the reached portion.
            ctx.stroke(path, with: .color(futureRibbon), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            if currentIndex > 0 {
                var reached = Path()
                reached.move(to: CGPoint(x: cx, y: y(0)))
                for i in 1...currentIndex {
                    let prev = CGPoint(x: cx, y: y(i - 1))
                    let cur = CGPoint(x: cx, y: y(i))
                    let midY = (prev.y + cur.y) / 2
                    let bow: CGFloat = (i % 2 == 0) ? 12 : -12
                    reached.addCurve(
                        to: cur,
                        control1: CGPoint(x: cx + bow, y: midY - 6),
                        control2: CGPoint(x: cx + bow, y: midY + 6)
                    )
                }
                ctx.stroke(reached, with: .color(ribbon), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }
        }
        .frame(width: railWidth)
        .frame(maxWidth: railWidth, alignment: .leading)
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
                    Text("Current step")
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
