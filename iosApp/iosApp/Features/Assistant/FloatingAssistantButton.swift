import SwiftUI

/// The floating AI-assistant button (iOS port of Android's FloatingAssistant
/// Button): a role-colored gradient circle with a pulsing halo and a sparkle
/// glyph (Android uses a Lottie character; iOS uses the sparkles symbol). Violet
/// for employees, emerald for employers.
struct FloatingAssistantButton: View {
    let isEmployer: Bool
    let onTap: () -> Void

    private var deep: Color { isEmployer ? GHTheme.hex(0x059669) : GHTheme.hex(0x7C3AED) }
    private var light: Color { isEmployer ? GHTheme.hex(0x10B981) : GHTheme.hex(0x8B5CF6) }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Pulsing halo.
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (t.truncatingRemainder(dividingBy: 1.4)) / 1.4   // 0..1
                    Circle()
                        .fill(deep)
                        .frame(width: 64, height: 64)
                        .scaleEffect(1.0 + 0.25 * phase)
                        .opacity(0.35 * (1 - phase))
                }
                // Gradient base + sparkle glyph.
                Circle()
                    .fill(LinearGradient(colors: [light, deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 60)
                    .shadow(color: deep.opacity(0.4), radius: 8, y: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
    }
}
