import SwiftUI
import Shared

/// iOS port of Android's DetailedHistoryCard — an expandable stage tracker for
/// one application. Collapsed: shows the current stage inline (pulsing purple
/// dot + label). Expanded: the full vertical stage list with green checks for
/// completed stages and a pulsing purple dot + fading halo on the active stage.
///
/// This is the card-less content (it's embedded inside the application row's
/// existing GHCard), so it doesn't add its own card chrome.
struct HistoryProgress: View {
    let application: Application
    @State private var expanded = false

    private let titleColor = GHTheme.onSurfaceVariant
    private let activePurple = GHTheme.primary
    private let checkGreen = GHTheme.success

    // The 8 canonical stages, in order (mirrors Android buildEntries).
    private static let stageOrder: [ApplicationStatus] = [
        .applied, .selected, .accepted, .otpRequested,
        .workInProgress, .completionPending, .paymentPending, .completed,
    ]

    private struct Stage { let label: String; let timestamp: String? }

    /// Stages up to and including the current one (Android's `visible`).
    private var visibleStages: [Stage] {
        let idx = activeIndex
        return (0...idx).map { i in
            Stage(label: Self.label(for: Self.stageOrder[i]),
                  timestamp: timestamp(for: Self.stageOrder[i]))
        }
    }

    private var activeIndex: Int {
        let mapped = Self.mappedStage(for: application.status)
        return Self.stageOrder.firstIndex(of: mapped) ?? (Self.stageOrder.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                Divider().padding(.vertical, 8)
                ForEach(Array(visibleStages.enumerated()), id: \.offset) { i, stage in
                    stageRow(stage, isActive: i == activeIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // highPriority so the expand tap wins over an enclosing NavigationLink
        // (actionable rows are wrapped in one) instead of navigating away.
        .highPriorityGesture(
            TapGesture().onEnded { withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() } }
        )
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DETAILED HISTORY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(titleColor)
                if !expanded, let active = visibleStages.last {
                    HStack(spacing: 10) {
                        PulsingDot(color: activePurple, halo: GHTheme.hex(0xDDD6FE))
                        Text(active.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(activePurple)
                        Spacer()
                        if let ts = active.timestamp {
                            Text(ts).font(.system(size: 12)).foregroundStyle(activePurple.opacity(0.85))
                        }
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(titleColor)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
    }

    private func stageRow(_ stage: Stage, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if isActive {
                    PulsingDot(color: activePurple, halo: GHTheme.hex(0xDDD6FE))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(checkGreen)
                }
            }
            .frame(width: 20, height: 20)

            Text(stage.label)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? activePurple : GHTheme.onBackground)
            Spacer()
            Text(stage.timestamp ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(isActive ? activePurple.opacity(0.85) : titleColor)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Stage data

    /// Best-available timestamp per stage from the Application fields. (Fuller
    /// per-stage timestamps live on the WorkSession; this uses what the list row
    /// already has so no extra fetch is needed.)
    private func timestamp(for status: ApplicationStatus) -> String? {
        switch status {
        case .applied: return Self.shortDate(application.appliedAt ?? application.createdAt)
        case .completed: return Self.shortDate(application.paymentDate ?? application.updatedAt)
        default:
            // Intermediate stages: show the row's updatedAt only on the active one.
            return status == Self.mappedStage(for: application.status)
                ? Self.shortDate(application.updatedAt) : nil
        }
    }

    private static func shortDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return String(raw.prefix(10))
    }

    /// Collapse near-equivalent statuses onto a canonical stage.
    private static func mappedStage(for status: ApplicationStatus) -> ApplicationStatus {
        switch status {
        case .shortlisted: return .selected
        case .hired: return .completed
        case .rejected, .rejectedOnce, .rejectedAndReshown, .withdrawn,
             .notInterested, .noShow, .positionFilled, .expired, .jobCancelled:
            return status   // terminal — handled by activeIndex fallback
        default: return status
        }
    }

    private static func label(for status: ApplicationStatus) -> String {
        switch status {
        case .applied: return "Applied"
        case .selected, .shortlisted: return "Selected"
        case .accepted: return "Accepted"
        case .otpRequested: return "OTP Requested"
        case .workInProgress: return "Working"
        case .completionPending: return "Awaiting Verification"
        case .paymentPending: return "Payment Pending"
        case .completed, .hired: return "Completed"
        default: return status.toDisplayString()
        }
    }
}

/// A purple dot with a fading, scaling halo — the active-stage "heartbeat"
/// (Android's ActiveDot). Driven by TimelineView so it animates continuously.
private struct PulsingDot: View {
    let color: Color
    let halo: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // 1.1s triangle wave for the halo, 0.9s for the inner dot.
            let haloPhase = abs((t.truncatingRemainder(dividingBy: 1.1) / 1.1) * 2 - 1)
            let dotPhase = abs((t.truncatingRemainder(dividingBy: 0.9) / 0.9) * 2 - 1)
            ZStack {
                Circle()
                    .fill(halo)
                    .frame(width: 20, height: 20)
                    .scaleEffect(1.0 + 0.6 * haloPhase)
                    .opacity(0.55 * (1 - haloPhase))
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .scaleEffect(0.85 + 0.30 * dotPhase)
            }
            .frame(width: 20, height: 20)
        }
    }
}
