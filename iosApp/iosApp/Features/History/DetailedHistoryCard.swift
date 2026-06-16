import SwiftUI
import Shared

/// Horizontal stage stepper for one application — the iOS port of Android's
/// StatusTimeline HorizontalProgressBar. Seven lifecycle nodes (Applied →
/// Selected → Accepted → Work Started → Completing → Payment → Completed) joined
/// by gentle cubic-bezier WAVE connectors. A small running-character icon surfs
/// the wave on the active segment. Auto-centers the active stage.
struct HistoryStepper: View {
    let status: ApplicationStatus
    /// Role accent — violet for employees, green for employers.
    var isEmployer: Bool = false

    private struct Step { let label: String; let icon: String }
    private static let steps: [Step] = [
        Step(label: "Applied", icon: "circle.fill"),
        Step(label: "Selected", icon: "hand.thumbsup.fill"),
        Step(label: "Accepted", icon: "checkmark"),
        Step(label: "Work Started", icon: "play.fill"),
        Step(label: "Completing", icon: "hourglass"),
        Step(label: "Payment", icon: "creditcard.fill"),
        Step(label: "Completed", icon: "checkmark.seal.fill"),
    ]

    // Active/brand accent: violet for employees, emerald for employers.
    private var accent: Color { isEmployer ? GHTheme.tertiary : GHTheme.primary }
    // Completed nodes + travelled lines use the SAME role accent (the reference
    // shows violet completed steps for employees, not a separate green).
    private var completed: Color { accent }
    private let futureLine = GHTheme.outline
    private let pendingTint = GHTheme.muted

    private let nodeSize: CGFloat = 44
    private let connectorWidth: CGFloat = 54
    private let connectorHeight: CGFloat = 34

    private var activeIndex: Int {
        switch status {
        case .applied, .shortlisted: return 0
        case .selected: return 1
        case .accepted, .otpRequested, .hired: return 2
        case .workInProgress: return 3
        case .completionPending: return 4
        case .paymentPending: return 5
        case .completed: return 6
        default: return 0
        }
    }

    private var isCancelled: Bool {
        switch status {
        case .rejected, .rejectedOnce, .rejectedAndReshown, .withdrawn,
             .noShow, .notInterested, .expired, .positionFilled, .jobCancelled:
            return true
        default: return false
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                        node(step, index: i).id(i)
                        if i < Self.steps.count - 1 {
                            // The connector AFTER node i is "travelled" once we've
                            // passed it; the active runner surfs the segment that
                            // leaves the current node.
                            ConnectorWithRunner(
                                travelled: !isCancelled && i < activeIndex,
                                showRunner: !isCancelled && i == activeIndex,
                                width: connectorWidth, height: connectorHeight,
                                doneColor: completed, futureColor: futureLine, runnerColor: accent
                            )
                            // Pull the wave into the node's empty side-space (the
                            // 44pt circle sits in a 72pt frame, ~14pt gap each
                            // side) so the line meets the icons with no gap.
                            .padding(.horizontal, -14)
                            .zIndex(-1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                guard !isCancelled else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(activeIndex, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func node(_ step: Step, index: Int) -> some View {
        let isCurrent = !isCancelled && index == activeIndex
        let isCompleted = !isCancelled && index < activeIndex
        let reached = isCurrent || isCompleted
        let fill: Color = isCompleted ? completed : (isCurrent ? accent : GHTheme.outline)

        VStack(spacing: 8) {
            ZStack {
                if isCurrent {
                    // Pulsing halo on the active node.
                    TimelineView(.animation) { t in
                        let p = abs((t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9) * 2 - 1)
                        Circle().fill(accent.opacity(0.25))
                            .frame(width: nodeSize, height: nodeSize)
                            .scaleEffect(1 + 0.25 * p)
                    }
                }
                Circle().fill(fill).frame(width: nodeSize, height: nodeSize)
                Image(systemName: isCompleted ? "checkmark" : step.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(reached ? .white : pendingTint)
            }
            .frame(width: nodeSize, height: nodeSize)

            Text(step.label)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? accent : pendingTint)
                .lineLimit(1).fixedSize()
        }
        .frame(width: 72)
    }
}

/// A cubic-bezier wave connector between two nodes; on the active segment a
/// running-character icon surfs the wave (animated), with a vertical bob.
private struct ConnectorWithRunner: View {
    let travelled: Bool
    let showRunner: Bool
    let width: CGFloat
    let height: CGFloat
    let doneColor: Color
    let futureColor: Color
    let runnerColor: Color

    // Control-point heights as fractions of the box height (dip then rise → S-wave).
    private let cp1 = 0.85, cp2 = 0.15

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Wave path.
            Path { p in
                let midY = height / 2
                p.move(to: CGPoint(x: 0, y: midY))
                p.addCurve(
                    to: CGPoint(x: width, y: midY),
                    control1: CGPoint(x: width * 0.33, y: height * cp1),
                    control2: CGPoint(x: width * 0.67, y: height * cp2)
                )
            }
            .stroke(travelled ? doneColor : futureColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))

            if showRunner {
                TimelineView(.animation) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let t = (now.truncatingRemainder(dividingBy: 1.6)) / 1.6        // 0..1 loop
                    let bob = sin(now / 0.3 * .pi) * 2                               // ±2 vertical bob
                    let pt = bezierPoint(t: t)
                    Circle()
                        .fill(runnerColor)
                        .frame(width: 22, height: 22)
                        .overlay(Image(systemName: "figure.run").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                        .position(x: pt.x, y: pt.y + bob)
                }
            }
        }
        .frame(width: width, height: height)
        .padding(.top, 10)   // align the wave centre with the node centres
    }

    /// Standard cubic bezier point at t for the wave above.
    private func bezierPoint(t: CGFloat) -> CGPoint {
        let midY = height / 2
        let p0 = CGPoint(x: 0, y: midY)
        let p1 = CGPoint(x: width * 0.33, y: height * cp1)
        let p2 = CGPoint(x: width * 0.67, y: height * cp2)
        let p3 = CGPoint(x: width, y: midY)
        let omt = 1 - t
        let x = omt*omt*omt*p0.x + 3*omt*omt*t*p1.x + 3*omt*t*t*p2.x + t*t*t*p3.x
        let y = omt*omt*omt*p0.y + 3*omt*omt*t*p1.y + 3*omt*t*t*p2.y + t*t*t*p3.y
        return CGPoint(x: x, y: y)
    }
}
