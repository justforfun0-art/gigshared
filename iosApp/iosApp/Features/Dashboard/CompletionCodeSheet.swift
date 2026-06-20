import SwiftUI
import Shared

/// The "Show Code" completion-OTP display — a SwiftUI port of Android's
/// CompletionOtpDisplayDialog (ui/components/OtpDialogs.kt). A pastel
/// indigo→purple→pink card with an amber key header, the giant 6-digit code in
/// a white amber-bordered panel ("Valid for 30 minutes"), an info strip telling
/// the worker the employer types this in, and New-Code (regenerate) + Done
/// buttons. The worker reads this code to their employer to finish the job.
struct WorkerCompletionCodeSheet: View {
    let code: String
    /// Regenerate handler → returns the fresh code (nil on failure).
    let onRegenerate: () async -> String?
    let onDone: () -> Void

    @State private var current: String
    @State private var isRegenerating = false
    @State private var regenError: String?

    init(code: String, onRegenerate: @escaping () async -> String?, onDone: @escaping () -> Void) {
        self.code = code
        self.onRegenerate = onRegenerate
        self.onDone = onDone
        _current = State(initialValue: code)
    }

    private let pastel = LinearGradient(
        colors: [GHTheme.hex(0xEEF2FF), GHTheme.hex(0xFAF5FF), GHTheme.hex(0xFDF2F8)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private let cta = LinearGradient(
        colors: [GHTheme.hex(0xF97316), GHTheme.hex(0xF59E0B)],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            pastel.ignoresSafeArea()

            // Close button (top-right), like Android.
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GHTheme.onSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.7), in: Circle())
            }
            .padding(16)

            VStack(spacing: 14) {
                // Amber key header tile.
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [GHTheme.hex(0xFBBF24), GHTheme.hex(0xF59E0B)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "key.fill").font(.system(size: 26)).foregroundStyle(.white))

                Text(L("completion_code_title"))
                    .font(.title2.weight(.bold)).foregroundStyle(GHTheme.hex(0x111827))
                Text(L("completion_code_share_subtitle"))
                    .font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                    .multilineTextAlignment(.center)

                // Giant code panel.
                VStack(spacing: 6) {
                    Text(spacedCode)
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundStyle(GHTheme.hex(0xEA580C))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(L("valid_for_30_minutes"))
                        .font(.caption).foregroundStyle(GHTheme.hex(0xB45309).opacity(0.85))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 22)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.hex(0xFDE68A), lineWidth: 1))

                // Info strip.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill").font(.caption).foregroundStyle(GHTheme.hex(0xF59E0B))
                    Text(L("employer_enters_code_msg"))
                        .font(.caption).foregroundStyle(GHTheme.hex(0x374151))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(GHTheme.outline, lineWidth: 1))

                if let regenError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(GHTheme.hex(0xB91C1C))
                        Text(regenError).font(.caption).foregroundStyle(GHTheme.hex(0xB91C1C))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(GHTheme.hex(0xFEF2F2), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(GHTheme.hex(0xFCA5A5), lineWidth: 1))
                }

                // New Code + Done.
                HStack(spacing: 12) {
                    Button(action: regenerate) {
                        HStack(spacing: 6) {
                            if isRegenerating { ProgressView().tint(GHTheme.hex(0xEA580C)) }
                            else { Image(systemName: "arrow.clockwise").font(.caption.weight(.bold)) }
                            Text(L("new_code")).fontWeight(.semibold)
                        }
                        .foregroundStyle(GHTheme.hex(0xEA580C))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GHTheme.hex(0xFED7AA), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRegenerating)

                    Button(action: onDone) {
                        Text(L("done")).fontWeight(.semibold).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(cta, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
    }

    /// "368548" → "3 6 8 5 4 8" for the spaced Android look.
    private var spacedCode: String {
        current.map(String.init).joined(separator: " ")
    }

    private func regenerate() {
        isRegenerating = true; regenError = nil
        Task {
            if let fresh = await onRegenerate() { current = fresh }
            else { regenError = L("completion_code_regen_failed") }
            isRegenerating = false
        }
    }
}
