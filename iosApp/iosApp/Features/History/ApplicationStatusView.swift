import SwiftUI
import Shared

/// "Application Status" — the vertical mountain-climb progress journey shown when
/// a History card is tapped. Port of Android's ApplicationDetailsScreen +
/// VerticalStatusTimeline: a mountain/flag header, then an "Application Progress"
/// card with a wavy violet ribbon connecting 8 stage nodes. Completed stages get
/// a purple gradient disc + check; the current stage adds a halo + "Current step"
/// pill; future stages are white discs with a lock + muted text.
struct ApplicationStatusView: View {
    let application: Application

    private struct Step {
        let label: String
        let description: String
        let icon: String
        let statuses: [ApplicationStatus]
    }

    private static let steps: [Step] = [
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
             icon: "wallet.pass.fill", statuses: [.paymentPending]),
        Step(label: "Completed", description: "Job completed. Payment will be credited to your account.",
             icon: "star.fill", statuses: [.completed]),
    ]

    private let gradTop = GHTheme.hex(0x8B5CF6)
    private let gradBottom = GHTheme.hex(0x5B21B6)
    private let ribbon = GHTheme.hex(0x8B5CF6)
    private let futureRibbon = GHTheme.hex(0xE9D5FF)
    private let surface = GHTheme.hex(0xF7F4FC)
    private let pillBg = GHTheme.hex(0xEDE9FE)
    private let pillText = GHTheme.hex(0x6D28D9)
    private let titleDark = GHTheme.hex(0x1F2937)
    private let descGray = GHTheme.hex(0x5B6470)
    private let mutedGray = GHTheme.muted

    private var currentIndex: Int {
        Self.steps.firstIndex { $0.statuses.contains(application.status) } ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressCard
            }
            .padding()
        }
        .background(GHTheme.pageGradient.ignoresSafeArea())
        .navigationTitle("Application Status")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Application Progress")
                .font(.title2.weight(.bold))
                .foregroundStyle(titleDark)

            MountainHeader(accent: ribbon)
                .frame(height: 140)
                .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                    stageRow(step, index: i)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    @ViewBuilder
    private func stageRow(_ step: Step, index: Int) -> some View {
        let isCompleted = index < currentIndex
        let isCurrent = index == currentIndex
        let reached = isCompleted || isCurrent
        let isLast = index == Self.steps.count - 1

        HStack(alignment: .top, spacing: 14) {
            // Rail: node disc + connecting ribbon below it.
            VStack(spacing: 0) {
                node(step, isCompleted: isCompleted, isCurrent: isCurrent)
                if !isLast {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(index < currentIndex ? ribbon : futureRibbon)
                        .frame(width: 6)
                        .frame(minHeight: 36)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 56)

            // Title + pill + description.
            VStack(alignment: .leading, spacing: 6) {
                Text(step.label)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(reached ? titleDark : mutedGray)
                if isCurrent {
                    Text("Current step")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pillText)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(pillBg, in: RoundedRectangle(cornerRadius: 10))
                }
                Text(step.description)
                    .font(.body)
                    .foregroundStyle(reached ? descGray : mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 18)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func node(_ step: Step, isCompleted: Bool, isCurrent: Bool) -> some View {
        let reached = isCompleted || isCurrent
        ZStack {
            if isCurrent {
                Circle().fill(GHTheme.hex(0xEDE6FB))
                    .frame(width: 60, height: 60)
                    .shadow(color: ribbon.opacity(0.4), radius: 8)
            }
            Circle().fill(.white).frame(width: 48, height: 48)
                .shadow(color: gradBottom.opacity(0.35), radius: 5)
            if reached {
                Circle()
                    .fill(LinearGradient(colors: [gradTop, gradBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                Image(systemName: isCompleted ? "checkmark" : step.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().fill(GHTheme.hex(0xF3F0FA))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(GHTheme.outline, lineWidth: 1.5))
                Image(systemName: "lock.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(GHTheme.hex(0xB9C0CC))
            }
        }
        .frame(width: 60, height: 60)
    }
}

/// Lavender mountain with a flag at the summit — the Android header illustration.
private struct MountainHeader: View {
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Back peak (lighter).
                Path { p in
                    p.move(to: CGPoint(x: w * 0.55, y: h * 0.35))
                    p.addLine(to: CGPoint(x: w * 0.95, y: h))
                    p.addLine(to: CGPoint(x: w * 0.20, y: h))
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.18))

                // Front peak.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.45, y: h * 0.22))
                    p.addLine(to: CGPoint(x: w * 0.80, y: h))
                    p.addLine(to: CGPoint(x: w * 0.08, y: h))
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.30))

                // Snow cap.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.45, y: h * 0.22))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.38))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.46))
                    p.addLine(to: CGPoint(x: w * 0.37, y: h * 0.38))
                    p.closeSubpath()
                }
                .fill(.white)

                // Flag pole + flag at the summit.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.45, y: h * 0.22))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.02))
                }
                .stroke(accent, lineWidth: 3)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.45, y: h * 0.02))
                    p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.07))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.13))
                    p.closeSubpath()
                }
                .fill(accent)
            }
        }
    }
}
