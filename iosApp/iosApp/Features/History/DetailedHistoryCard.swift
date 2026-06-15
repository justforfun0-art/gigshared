import SwiftUI
import Shared

/// Horizontal stage stepper for one application — the iOS port of Android's
/// HistoryScreen HorizontalStepper. Seven lifecycle nodes (Applied → Selected →
/// Accepted → Work Started → Completing → Payment → Completed) connected by a
/// violet line that fills up to the active stage; the active node is larger and
/// violet. Scrolls horizontally and auto-centers the active stage.
struct HistoryStepper: View {
    let status: ApplicationStatus

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

    private let violet = GHTheme.primary
    private let track = GHTheme.outline
    private let pendingTint = GHTheme.muted

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
                        node(step, index: i)
                            .id(i)
                    }
                }
            }
            .onAppear {
                guard !isCancelled else { return }
                // Center the active stage after first layout.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(activeIndex, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func node(_ step: Step, index: Int) -> some View {
        let isCurrent = !isCancelled && index == activeIndex
        let isCompleted = !isCancelled && index < activeIndex
        let circle: CGFloat = isCurrent ? 52 : 40
        let nodeWidth: CGFloat = isCurrent ? 96 : 76
        // Connector halves: left filled once reached, right filled once passed.
        let leftFilled = !isCancelled && index <= activeIndex
        let rightFilled = !isCancelled && index < activeIndex

        VStack(spacing: 8) {
            ZStack {
                // Connector line behind the circle (left + right halves).
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(index == 0 ? Color.clear : (leftFilled ? violet : track))
                        .frame(height: 4)
                    Rectangle()
                        .fill(index == Self.steps.count - 1 ? Color.clear : (rightFilled ? violet : track))
                        .frame(height: 4)
                }
                // The node circle.
                Circle()
                    .fill(isCurrent || isCompleted ? violet : GHTheme.outline)
                    .frame(width: circle, height: circle)
                Image(systemName: step.icon)
                    .font(.system(size: isCurrent ? 22 : 16, weight: .semibold))
                    .foregroundStyle(isCurrent || isCompleted ? .white : pendingTint)
            }
            .frame(height: 52)

            Text(step.label)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? violet : pendingTint)
                .lineLimit(1)
        }
        .frame(width: nodeWidth)
    }
}
