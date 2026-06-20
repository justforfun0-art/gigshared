import SwiftUI
import Shared

/// Live "work in progress" hero card on the Application Status screen — SwiftUI
/// port of Android's WorkTimerDisplay (ui/components/WorkTimerDisplay.kt). Shown
/// only while the application is WORK_IN_PROGRESS: a pulsing "WORK IN PROGRESS"
/// pill, a big centered HH:MM:SS timer, a "Started … · ₹/hr" sub-line, live
/// accruing earnings, and a "Tap to complete →" footer that generates the
/// completion code (WIP → COMPLETION_PENDING).
struct WorkInProgressDetailCard: View {
    let applications: any ApplicationRepository
    let application: Application
    /// Called after completion succeeds (parent refreshes / shows the code).
    var onCompleted: (String) -> Void = { _ in }

    @State private var startedAt: Date?
    @State private var hourlyRate: Double = 0
    @State private var now = Date()
    @State private var isCompleting = false
    @State private var loaded = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var job: Job? { application.job }

    var body: some View {
        VStack(spacing: 0) {
            if let startedAt {
                content(startedAt)
            } else {
                // Loading / unresolved start — show a neutral working pill.
                pill
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(
            LinearGradient(colors: [GHTheme.hex(0x3730A3), GHTheme.hex(0x4338CA)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .shadow(color: GHTheme.hex(0x3730A3).opacity(0.4), radius: 8, y: 3)
        .task { await load() }
        .onReceive(tick) { now = $0 }
    }

    @ViewBuilder
    private func content(_ start: Date) -> some View {
        let elapsed = max(now.timeIntervalSince(start), 0)
        let earned = hourlyRate > 0 ? (elapsed / 3600.0) * hourlyRate : 0
        VStack(spacing: 0) {
            pill
            Spacer().frame(height: 16)
            Text(clock(elapsed))
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Spacer().frame(height: 6)
            Text(subLine(start))
                .font(.footnote).foregroundStyle(GHTheme.hex(0xC7D2FE))
                .multilineTextAlignment(.center)
            Spacer().frame(height: 18)
            Text(L("earned_so_far")).font(.caption).foregroundStyle(GHTheme.hex(0xC7D2FE))
            Spacer().frame(height: 2)
            Text(Money.rupees(earned))
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(GHTheme.hex(0x4ADE80))

            Spacer().frame(height: 18)
            Button {
                Task { await complete() }
            } label: {
                HStack(spacing: 6) {
                    if isCompleting {
                        ProgressView().tint(.white)
                        Text(L("completing_ellipsis")).font(.subheadline.weight(.semibold))
                    } else {
                        Text(L("tap_to_complete")).font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.right").font(.subheadline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Circle().fill(GHTheme.hex(0xD1FAE5))
                .frame(width: 6, height: 6)
                .opacity(now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1.2) < 0.6 ? 1 : 0.45)
            Text("WORK IN PROGRESS")
                .font(.system(size: 10, weight: .bold)).kerning(1)
                .foregroundStyle(GHTheme.hex(0xD1FAE5))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(GHTheme.hex(0x166534).opacity(0.95), in: Capsule())
    }

    // MARK: - Data

    private func load() async {
        guard !loaded else { return }
        loaded = true
        let session = try? await IosHelpersKt.getWorkSessionOrThrow(applications, applicationId: application.id)
        let startStr = session?.workStartTime ?? application.updatedAt
        startedAt = startStr.flatMap { ActiveJobBarViewModel.parseISO($0) }
        hourlyRate = session?.hourlyRateUsed?.doubleValue
            ?? Self.rateFromSalary(job?.salaryRange) ?? 0
    }

    private func complete() async {
        isCompleting = true
        defer { isCompleting = false }
        if let code = try? await IosHelpersKt.generateCompletionOtpOrThrow(
            applications, applicationId: application.id
        ) {
            onCompleted(code)
        }
    }

    // MARK: - Format helpers

    private func subLine(_ start: Date) -> String {
        var parts: [String] = []
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.dateFormat = "h:mm a"
        parts.append("Started " + f.string(from: start).lowercased())
        if hourlyRate > 0 { parts.append("₹" + String(format: "%.0f", hourlyRate) + "/hr") }
        return parts.joined(separator: " · ")
    }

    private func clock(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    private static func rateFromSalary(_ s: String?) -> Double? {
        guard let s else { return nil }
        let digits = s.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}
