import SwiftUI
import Shared

/// Free-floating, draggable, collapsible live work-timer widget — iOS port of
/// Android's `FloatingWorkTimer` (ui/components/WorkTimerContext.kt). While a
/// WORK_IN_PROGRESS shift is active it floats over every employee tab:
///   - collapsed: a small gradient bubble (timer icon + pulsing red dot + HH:MM:SS),
///     parked at the bottom-right, draggable.
///   - expanded: a 300pt card with the big centered timer, job title, an earnings
///     strip, and a "View Details" button (opens the work-session/complete flow).
/// Tap the bubble to expand; tap the chevron/close to collapse.
struct ActiveJobBar: View {

    let applications: any ApplicationRepository
    let employeeId: String
    let onOpen: (Application) -> Void

    @StateObject private var viewModel: ActiveJobBarViewModel
    @State private var now = Date()
    @State private var expanded = false
    @State private var drag: CGSize = .zero
    @State private var committed: CGSize = .zero   // accumulated offset across drags

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let poll = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    init(applications: any ApplicationRepository, employeeId: String,
         onOpen: @escaping (Application) -> Void) {
        self.applications = applications
        self.employeeId = employeeId
        self.onOpen = onOpen
        _viewModel = StateObject(wrappedValue: ActiveJobBarViewModel(
            applications: applications, employeeId: employeeId
        ))
    }

    var body: some View {
        GeometryReader { geo in
            if let job = viewModel.job {
                let elapsed = max(now.timeIntervalSince(job.startedAt), 0)
                let earned = job.hourlyRate * (elapsed / 3600.0)
                // Widget half-extents (approx) so we can clamp its centre inside
                // the safe band between the top nav bar and the bottom tab bar.
                let halfW: CGFloat = expanded ? 150 : 60
                let halfH: CGFloat = expanded ? 110 : 24
                // Keep clear of the top nav bar and the bottom tab bar.
                let topLimit = geo.safeAreaInsets.top + 52 + halfH
                let bottomLimit = geo.size.height - geo.safeAreaInsets.bottom - 84 - halfH
                let leftLimit = halfW + 8
                let rightLimit = geo.size.width - halfW - 8
                // Default park = bottom-right of the safe band.
                let baseX = rightLimit
                let baseY = bottomLimit
                let rawX = baseX + committed.width + drag.width
                let rawY = baseY + committed.height + drag.height
                let clampedX = min(max(rawX, leftLimit), rightLimit)
                let clampedY = min(max(rawY, topLimit), bottomLimit)

                widget(job, elapsed: elapsed, earned: earned)
                    .position(x: clampedX, y: clampedY)
                    .gesture(
                        DragGesture()
                            .onChanged { drag = $0.translation }
                            .onEnded { _ in
                                // Commit the clamped delta so the next drag starts
                                // from the on-screen position (can't drift off-screen).
                                committed.width = min(max(committed.width + drag.width, leftLimit - baseX), rightLimit - baseX)
                                committed.height = min(max(committed.height + drag.height, topLimit - baseY), bottomLimit - baseY)
                                drag = .zero
                            }
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expanded)
        .animation(.easeInOut(duration: 0.25), value: viewModel.job)
        .task { await viewModel.refresh() }
        .onReceive(tick) { now = $0 }
        .onReceive(poll) { _ in Task { await viewModel.refresh() } }
    }

    @ViewBuilder
    private func widget(_ job: ActiveJobBarViewModel.ActiveJob, elapsed: TimeInterval, earned: Double) -> some View {
        if expanded {
            expandedCard(job, elapsed: elapsed, earned: earned)
        } else {
            collapsedBubble(elapsed: elapsed)
        }
    }

    // MARK: - Collapsed bubble

    private func collapsedBubble(elapsed: TimeInterval) -> some View {
        HStack(spacing: 8) {
            liveTimerIcon(size: 18, dot: 6)
            Text(clock(elapsed))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(gradient, in: Capsule())
        .shadow(color: GHTheme.hex(0x7C3AED).opacity(0.4), radius: 8, y: 3)
        .onTapGesture { expanded = true }
    }

    // MARK: - Expanded card

    private func expandedCard(_ job: ActiveJobBarViewModel.ActiveJob, elapsed: TimeInterval, earned: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                liveTimerIcon(size: 22, dot: 8)
                Text(L("ios_work_in_progress")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { expanded = false } label: {
                    Image(systemName: "chevron.down").font(.subheadline).foregroundStyle(.white)
                }
                Button { expanded = false } label: {
                    Image(systemName: "xmark").font(.subheadline).foregroundStyle(.white)
                }
            }
            Text(clock(elapsed))
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Image(systemName: "briefcase.fill").font(.caption).foregroundStyle(.white.opacity(0.85))
                Text(job.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            }
            if job.hourlyRate > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "indianrupeesign").font(.caption).foregroundStyle(.white)
                    Text(L("earnings_label")).font(.subheadline).foregroundStyle(.white)
                    Spacer()
                    Text(Money.rupees(earned))
                        .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
            Button {
                Task {
                    if let app = try? await IosHelpersKt.getApplicationByIdOrThrow(
                        applications, applicationId: job.applicationId
                    ) { onOpen(app) }
                }
            } label: {
                Text(L("view_details")).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 300)
        .background(
            LinearGradient(colors: [GHTheme.hex(0x5B21B6), GHTheme.hex(0x7C3AED)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .shadow(color: GHTheme.hex(0x7C3AED).opacity(0.4), radius: 12, y: 5)
    }

    // MARK: - Bits

    private var gradient: LinearGradient {
        LinearGradient(colors: [GHTheme.hex(0x5B21B6), GHTheme.hex(0x7C3AED)],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Timer glyph with a pulsing red "live" dot (Android's red dot).
    private func liveTimerIcon(size: CGFloat, dot: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "timer").font(.system(size: size)).foregroundStyle(.white)
            Circle().fill(GHTheme.hex(0xEF4444))
                .frame(width: dot, height: dot)
                .offset(x: dot * 0.5, y: -dot * 0.3)
                .opacity(now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1.4) < 0.7 ? 1 : 0.4)
        }
    }

    private func clock(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}
